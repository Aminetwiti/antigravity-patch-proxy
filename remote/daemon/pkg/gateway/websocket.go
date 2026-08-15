package gateway

import (
	"bytes"
	"context"
	"crypto/subtle"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/antigravity/remote-daemon/pkg/connectrpc"
	"github.com/antigravity/remote-daemon/pkg/discovery"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: checkOrigin,
}

// logJSON : logger structuré du gateway (JSON, niveau configurable).
// Utilisé par les événements lifecycle ; les erreurs portent requestId pour
// corréler mobile ↔ hub (C4).
var logJSON = slog.Default()

// SetLogJSON permet au main de brancher le logger rotatif (health.go).
func SetLogJSON(l *slog.Logger) { logJSON = l }

// RPCClient est l'ensemble des méthodes du backend LanguageServer utilisées
// par le gateway (interface minimale pour permettre les tests avec un faux).
type RPCClient interface {
	Heartbeat() ([]byte, error)
	CreateCascade(uri string, projectID string, modelUID string, modelEnum uint64) ([]byte, error)
	GetAllCascades() ([]byte, error)
	SendMessageStream(cascadeID, text string, onFrame func([]byte) error) error
	// SendMessageStreamModel : variante avec modèle explicite (sélection
	// mobile par message) — le daemon laisse le téléphone choisir le modèle.
	SendMessageStreamModel(cascadeID, text, modelUID string, modelEnum uint64, onFrame func([]byte) error) error
	SubmitToolApproval(cascadeID, trajectoryID string, stepIndex uint32, oneofField int, oneofPayload []byte) ([]byte, error)
	SetBrowserOpenConversation(cascadeID string) ([]byte, error)
	SendCommand(commandText string) ([]byte, error)
	// ListModels récupère la liste des modèles disponibles (GetAvailableModels).
	ListModels() ([]byte, error)
	// DeleteCascade supprime une session (DeleteCascadeTrajectory).
	DeleteCascade(cascadeID string) ([]byte, error)
	// ReadFile lit un fichier via le RPC officiel du LS (ReadFile).
	ReadFile(uri string) ([]byte, error)
	// WriteFile écrit un fichier via le RPC officiel du LS (WriteFile).
	WriteFile(uri string, content []byte, overwrite bool) ([]byte, error)
	// GetCascadeTrajectory récupère l'historique structuré d'une session
	// (GetCascadeTrajectory) — verbosity 0 = défaut du LS.
	GetCascadeTrajectory(cascadeID string, verbosity uint64) ([]byte, error)
	// GetTurnDiff récupère le diff officiel d'un tour (GetTurnDiff).
	// stepIndex < 0 → le LS résout le dernier tour.
	GetTurnDiff(conversationID string, stepIndex int64) ([]byte, error)
	// GetRevertPreview demande la prévisualisation du rollback d'une cascade.
	GetRevertPreview(cascadeID string, stepIndex int64) ([]byte, error)
	// RevertToCascadeStep applique le rollback de la cascade à une étape donnée.
	RevertToCascadeStep(cascadeID string, stepIndex int64) error
	// SendStepsToBackground bascule des étapes en tâche d'arrière-plan.
	SendStepsToBackground(conversationID string, stepIndices []int64) error
	// SkipBrowserSubagent saute une étape de sous-agent de navigation.
	SkipBrowserSubagent(cascadeID string, stepIndex int64) error
	// RetrieveUserQuotaSummary récupère le résumé des quotas utilisateur du Language Server.
	RetrieveUserQuotaSummary() ([]byte, error)
}

// checkOrigin rejette les navigateurs web arbitraires (CSWSH) tout en
// acceptant les apps natives (Origin absent) et le localhost.
func checkOrigin(r *http.Request) bool {
	o := r.Header.Get("Origin")
	if o == "" || o == "null" {
		return true // clients natifs (app mobile, curl) — pas d'Origin
	}
	u, err := url.Parse(o)
	if err != nil {
		return false
	}
	h := strings.ToLower(u.Hostname())
	if h == "localhost" || h == "127.0.0.1" || h == "::1" {
		return true
	}
	// Plages LAN privées strictes (CIDR) — un préfixe naïf "172." accepterait
	// 172.evil.com ; le parse CIDR le rejette.
	ip := net.ParseIP(h)
	if ip != nil {
		for _, cidr := range []string{"192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12"} {
			if _, n, err := net.ParseCIDR(cidr); err == nil && n.Contains(ip) {
				return true
			}
		}
	}
	return strings.HasSuffix(h, ".trycloudflare.com") || strings.HasSuffix(h, ".pinggy.link") ||
		strings.HasSuffix(h, ".ngrok.io") || strings.HasSuffix(h, ".ngrok-free.app")
}

// pendingApproval : une approbation émise mais pas encore répondue, avec les
// infos nécessaires à l'auto-refus (trajectoryId + stepIndex + payload), le
// timer d'expiration (approvalTimeout, défaut 5 min) et la corrélation mobile
// (callId + cascadeId : le client peut la ré-ouvrir après un tap-notification
// via get_pending_approval).
type pendingApproval struct {
	callID       string
	cascadeID    string
	trajectoryID string
	stepIndex    uint32
	approvalType string
	command      string
	filePath     string
	timer        *time.Timer
}

type Server struct {
	RPCClient RPCClient
	AuthToken string
	clients   map[*websocket.Conn]bool
	mu        sync.Mutex
	// writeLocks (défini plus bas dans le struct) sérialise les écritures PAR
	// connexion : gorilla/websocket n'autorise qu'un seul writer concurrent par
	// connexion — le broadcast, les réponses unary et la goroutine de ping
	// passent tous par le mutex de LA connexion ciblée, jamais par un mutex
	// global (qui causait des réponses croisées entre clients).
	// approvals : cascadeId → approbation en attente (posée par
	// MarkApprovalPending quand un événement approval_required est émis,
	// retirée à la décision utilisateur ou à l'expiration).
	approvals map[string]*pendingApproval
	// approvalTimeout : délai avant auto-refus d'une approbation sans réponse
	// (sécurité : téléphone perdu). 0 = désactivé. Défaut 5 minutes.
	approvalTimeout time.Duration
	// sessionApprovals : cascadeId+approvalType → l'utilisateur a choisi
	// « toujours autoriser pour cette session » (B3). Les demandes suivantes
	// du même type sont auto-approuvées sans repasser par le téléphone.
	sessionApprovals map[string]bool
	// activeCascades : cascadeId → le daemon est en train de streamer un tour
	// pour cette cascade (C5 : compteur d'activité exposé au /health).
	activeCascades map[string]bool
	// lastError : dernière erreur RPC notable, exposée au /health (C5).
	lastError string
	// startedAt : horodatage de démarrage du serveur (C5, uptime).
	startedAt time.Time
	// sentRequestIDs : requestId déjà traités (C1, idempotence). Un send_prompt
	// retransmis après coupure Wi-Fi ne duplique pas le tour : le hub reçoit
	// chaque requête au plus une fois.
	sentRequestIDs map[string]bool
	// clientInFlight : nombre de send_prompt en cours PAR CLIENT (C3, limite
	// de streams simultanés — un client ne peut pas saturer le hub).
	clientInFlight map[*websocket.Conn]int
	// writeLocks : mutex d'écriture PAR CONNEXION (remplace l'ancien writeMu
	// global). Deux clients concurrents n'ont plus AUCUN point de sérialisation
	// commun : 20 clients × 30 heartbeats ne produisent plus de réponses
	// croisées (les écritures sont ordonnées par connexion, pas globalement).
	writeLocks map[*websocket.Conn]*sync.Mutex
	// streamBuffer : tampon circulaire StepRecovery pour reprise sur déconnexion 4G/Wi-Fi
	streamBuffer *SessionStreamBuffer
	// activeCancels : cascadeId → fonction d'annulation active
	activeCancels map[string]context.CancelFunc
	// activeRequestIDs : cascadeId → requestId en cours
	activeRequestIDs map[string]string
	// scheduledTasks : taskId → tâche planifiée gérée par le daemon
	scheduledTasks map[string]*ScheduledTask
	// sessionsCache : résultat list_sessions déjà calculé (GetAllCascades coûte
	// ~9,5 s côté hub) + single-flight (fetchInFlight) pour que N reconnexions
	// simultanées du mobile ne déclenchent qu'UN appel LS au lieu de N.
	sessionsCache    []byte
	sessionsCachedAt time.Time
	fetchInFlight    bool
}

// ScheduledTask représente une tâche planifiée / cron job gérée par le daemon.
type ScheduledTask struct {
	ID             string               `json:"id"`
	Name           string               `json:"name"`
	Prompt         string               `json:"prompt"`
	WorkspaceName  string               `json:"workspaceName"`
	CronExpression string               `json:"cronExpression,omitempty"`
	DurationSeconds int                 `json:"durationSeconds,omitempty"`
	IsDaemon       bool                 `json:"isDaemon"`
	IterationsRun  int                  `json:"iterationsRun"`
	NextRunAt      string               `json:"nextRunAt,omitempty"`
	IsEnabled      bool                 `json:"isEnabled"`
	Status         string               `json:"status"`
	Uptime         string               `json:"uptime"`
	Events         []ScheduledTaskEvent `json:"events"`
}

type ScheduledTaskEvent struct {
	ID         string `json:"id"`
	Timestamp  string `json:"timestamp"`
	Outcome    string `json:"outcome"`
	Message    string `json:"message"`
	DurationMs int    `json:"durationMs,omitempty"`
}

// Stats snapshot de l'état du serveur pour l'endpoint /health (C5).
// Champs JSON stables — le mobile (ou un script) peut les afficher tels quels.
type Stats struct {
	Status         string   `json:"status"`
	Sessions       int      `json:"sessions"`
	Streams        int      `json:"streams"`
	Clients        int      `json:"clients"`
	Uptime         string   `json:"uptime"`
	ActiveCascades []string `json:"activeCascades"`
	LastError      string   `json:"lastError,omitempty"`
}

func NewServer(client RPCClient, authToken string) *Server {
	return &Server{
		RPCClient:        client,
		AuthToken:        authToken,
		clients:          make(map[*websocket.Conn]bool),
		approvals:        make(map[string]*pendingApproval),
		approvalTimeout:  5 * time.Minute,
		sessionApprovals: make(map[string]bool),
		activeCascades:   make(map[string]bool),
		startedAt:        time.Now(),
		sentRequestIDs:   make(map[string]bool),
		clientInFlight:   make(map[*websocket.Conn]int),
		writeLocks:       make(map[*websocket.Conn]*sync.Mutex),
		streamBuffer:     NewSessionStreamBuffer(100),
		activeCancels:    make(map[string]context.CancelFunc),
		activeRequestIDs: make(map[string]string),
		scheduledTasks:   make(map[string]*ScheduledTask),
	}
}

// sessionsCacheTTL : durée de fraîcheur du cache list_sessions. Le mobile
// rafraîchit la liste à chaque reconnexion ; le LS met ~9,5 s à répondre.
// 5 s = 1 seule recharge si l'utilisateur rouvre l'app 2 fois de suite, mais
// la liste reste assez fraîche pour un usage réel.
const sessionsCacheTTL = 5 * time.Second

// cachedSessions retourne le résultat list_sessions frais s'il existe (moins
// de sessionsCacheTTL), sinon (nil, false).
func (s *Server) cachedSessions() ([]byte, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.sessionsCache) > 0 && time.Since(s.sessionsCachedAt) < sessionsCacheTTL {
		return s.sessionsCache, true
	}
	return nil, false
}

// cachedProjectID resolve le projectID d'un workspace à partir du cache
// list_sessions déjà chaud (coût nul). Retourne ("", false) si le cache est
// vide — l'appelant retombe alors sur le comportement cascade "orpheline".
// Ponctuellement utilisé par create_cascade pour éviter le GetAllCascades
// synchrone (~9,5 s) sur le chemin critique.
func (s *Server) cachedProjectID(uri string) (string, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.sessionsCache) == 0 {
		return "", false
	}
	for _, sum := range connectrpc.ParseTrajectories(s.sessionsCache) {
		if sum.ProjectID != "" && strings.EqualFold(sum.Workspace, uri) {
			return sum.ProjectID, true
		}
	}
	return "", false
}

// fetchSessionsSingleFlight : un seul appel GetAllCascades à la fois, quel que
// soit le nombre de clients qui demandent la liste. Les appelants concurrents
// attendent le même résultat au lieu de marteler le hub LS.
func (s *Server) fetchSessionsSingleFlight() []byte {
	s.mu.Lock()
	if s.fetchInFlight {
		s.mu.Unlock()
		for {
			time.Sleep(50 * time.Millisecond)
			if raw, ok := s.cachedSessions(); ok {
				return raw
			}
			s.mu.Lock()
			inFlight := s.fetchInFlight
			s.mu.Unlock()
			if !inFlight {
				break
			}
		}
	} else {
		s.fetchInFlight = true
		s.mu.Unlock()
	}

	// Premier appelant : fait l'appel LS et peuple le cache.
	raw, err := s.RPCClient.GetAllCascades()
	s.mu.Lock()
	s.fetchInFlight = false
	if err == nil && len(raw) > 0 {
		s.sessionsCache = raw
		s.sessionsCachedAt = time.Now()
	}
	s.mu.Unlock()
	return raw
}

// SetApprovalTimeout expose le délai d'auto-refus des approbations (5 min par
// défaut) aux Settings mobile via le message WS "set_approval_timeout".
func (s *Server) SetApprovalTimeout(d time.Duration) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.approvalTimeout = d
}

// mcpProxyBase est le point d'entrée HTTP du proxy MCP Antigravity desktop
// (antigravity-patch-proxy, écoute sur 127.0.0.1:50999). Le daemon y route
// les appels d'outils MCP venus du mobile — la session du PC fait foi pour
// l'authentification et l'allowlist des serveurs MCP.
const mcpProxyBase = "http://127.0.0.1:50999"

// CancelGeneration interrompt une cascade active et diffuse stream_end(cancelled).
func (s *Server) CancelGeneration(cascadeID string) {
	s.mu.Lock()
	cancel, hasCancel := s.activeCancels[cascadeID]
	reqID := s.activeRequestIDs[cascadeID]
	s.mu.Unlock()

	if hasCancel && cancel != nil {
		cancel()
	}
	s.clearApproval(cascadeID)
	s.ClearCascadeActive(cascadeID)

	s.broadcast(OutgoingMessage{
		Type:      "stream_end",
		RequestID: reqID,
		Data: map[string]interface{}{
			"cascadeId":  cascadeID,
			"outcome":    "cancelled",
			"message":    "Generation stopped by user",
			"hostActive": false,
		},
	})
}

// MarkCascadeActive marque une cascade comme « en cours de stream » (posé à
// l'entrée de send_prompt, retiré à la sortie). Servi au /health.
func (s *Server) MarkCascadeActive(cascadeID string) {
	s.mu.Lock()
	s.activeCascades[cascadeID] = true
	s.mu.Unlock()
}

// ClearCascadeActive retire la marque de stream en cours.
func (s *Server) ClearCascadeActive(cascadeID string) {
	s.mu.Lock()
	delete(s.activeCascades, cascadeID)
	s.mu.Unlock()
}

// Stats renvoie un snapshot cohérent de l'état du serveur (C5).
func (s *Server) Stats() Stats {
	s.mu.Lock()
	defer s.mu.Unlock()
	active := make([]string, 0, len(s.activeCascades))
	for c := range s.activeCascades {
		active = append(active, c)
	}
	sort.Strings(active)
	st := Stats{
		Sessions:       len(s.activeCascades),
		Streams:        len(s.activeCascades),
		Clients:        len(s.clients),
		Uptime:         time.Since(s.startedAt).Round(time.Second).String(),
		ActiveCascades: active,
		LastError:      s.lastError,
	}
	st.Status = "ok"
	if s.lastError != "" {
		st.Status = "degraded"
	}
	return st
}

// maxWSMessageSize borne la taille des messages WebSocket entrants (1 Mo)
// pour empêcher un client de faire un DoS mémoire.
const maxWSMessageSize = 1 << 20

// maxConcurrentStreams : nombre maximum de send_prompt simultanés PAR CLIENT
// (C3). Au-delà, la requête est refusée avec une erreur explicite — un seul
// téléphone ne peut pas saturer le hub.
const maxConcurrentStreams = 2

// hostActiveWindow : fenêtre d'activité clavier/souris du PC hôte (C7-B).
// Si l'utilisateur a interagi dans les 90 dernières secondes, on considère
// qu'il est devant le PC → le mobile supprime la notification d'approbation.
const hostActiveWindow = 90 * time.Second

// pingInterval / pongWait : garde-fous de connexions mortes. Le ping échoue
// si le pair ne répond pas (network parti, app fermée) → read error → le
// client est retiré du broadcast.
const (
	pingInterval = 30 * time.Second
	pongWait     = 60 * time.Second
)

// writeTimeout : deadline d'écriture par message. Un client mort (buffer TCP
// plein) ferait sinon bloquer WriteJSON indéfiniment sous writeMu → head-of-line
// blocking sur TOUTES les connexions (le broadcast passe par le même mutex).
const writeTimeout = 10 * time.Second

// writeJSON envoie un message à une connexion donnée (writer unique par
// connexion : un seul goroutine écrit sur un websocket.Conn à la fois — le
// broadcast, les réponses unary et la goroutine de ping passent tous par le
// mutex de LA connexion ciblée, jamais par un mutex global).
func (s *Server) writeJSON(conn *websocket.Conn, msg OutgoingMessage) error {
	s.writeLock(conn).Lock()
	defer s.writeLock(conn).Unlock()
	conn.SetWriteDeadline(time.Now().Add(writeTimeout))
	if err := conn.WriteJSON(msg); err != nil {
		logJSON.Warn("write_error", "err", err)
		return err
	}
	return nil
}

// writeLock retourne le mutex d'écriture dédié à conn (créé à la volée si le
// client s'est connecté avant l'initialisation — chemin de test uniquement).
func (s *Server) writeLock(conn *websocket.Conn) *sync.Mutex {
	s.mu.Lock()
	defer s.mu.Unlock()
	if lk, ok := s.writeLocks[conn]; ok {
		return lk
	}
	lk := &sync.Mutex{}
	s.writeLocks[conn] = lk
	return lk
}

// releaseWriteLock libère la mémoire du mutex d'écriture d'un client déconnecté.
func (s *Server) releaseWriteLock(conn *websocket.Conn) {
	s.mu.Lock()
	delete(s.writeLocks, conn)
	s.mu.Unlock()
}

// mcpTimeout borne l'appel HTTP vers le proxy MCP desktop (30 s) — aligné sur
// le timeout 15 s côté mobile + la marge de traversée tunnel/4G.
const mcpTimeout = 30 * time.Second

// handleMcpAction relaie call_mcp_tool / connect_mcp_server /
// refresh_mcp_oauth_token vers le proxy MCP Antigravity desktop
// (127.0.0.1:50999). Le mobile n'a ni les identifiants ni l'allowlist MCP :
// la session du PC est le seul détenteur légitime — le daemon n'est qu'un
// tunnel. La réponse JSON du proxy est relayée telle quelle dans Data.
func (s *Server) handleMcpAction(conn *websocket.Conn, msg IncomingMessage) {
	if msg.ServerName == "" {
		s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "serverName requis"})
		return
	}

	payload := map[string]interface{}{
		"serverName": msg.ServerName,
	}
	if msg.ToolName != "" {
		payload["toolName"] = msg.ToolName
	}
	if msg.Arguments != nil {
		payload["arguments"] = msg.Arguments
	}
	if msg.Endpoint != "" {
		payload["endpoint"] = msg.Endpoint
	}
	if msg.GrantType != "" {
		payload["grantType"] = msg.GrantType
	}

	body, err := json.Marshal(payload)
	if err != nil {
		s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "erreur d'encodage: " + err.Error()})
		return
	}

	client := &http.Client{Timeout: mcpTimeout}
	resp, err := client.Post(mcpProxyBase+"/"+msg.Type, "application/json", bytes.NewReader(body))
	if err != nil {
		s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "proxy MCP injoignable: " + err.Error()})
		return
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "lecture de la réponse proxy: " + err.Error()})
		return
	}
	if resp.StatusCode >= 400 {
		s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "proxy MCP " + itoa(resp.StatusCode) + ": " + strings.TrimSpace(string(respBody))})
		return
	}

	var proxyResp map[string]interface{}
	if err := json.Unmarshal(respBody, &proxyResp); err != nil {
		s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: map[string]interface{}{"raw": string(respBody)}})
		return
	}
	s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: proxyResp})
}

// broadcast envoie le même message à TOUS les clients connectés : c'est ce qui
// permet la synchronisation multi-surface (un téléphone voit le stream déclenché
// par le PC ou par un autre téléphone). Un client dont l'écriture échoue
// (deadline dépassée) est retiré de la liste — il ne doit pas bloquer ni
// ré-échouer les broadcasts suivants (il sera aussi purgé par la boucle de
// lecture côté HandleWebSocket).
func (s *Server) broadcast(msg OutgoingMessage) {
	s.mu.Lock()
	conns := make([]*websocket.Conn, 0, len(s.clients))
	for c := range s.clients {
		conns = append(conns, c)
	}
	s.mu.Unlock()
	for _, c := range conns {
		if s.writeJSON(c, msg) != nil {
			s.mu.Lock()
			delete(s.clients, c)
			delete(s.clientInFlight, c)
			s.mu.Unlock()
			s.releaseWriteLock(c)
		}
	}
}

type IncomingMessage struct {
	Type            string                 `json:"type"`
	RequestID       string                 `json:"requestId"`
	WorkspaceURI    string                 `json:"workspaceUri"`
	WorkspacePath   string                 `json:"workspacePath,omitempty"`
	CascadeID       string                 `json:"cascadeId,omitempty"`
	CallID          string                 `json:"callId,omitempty"`
	TrajectoryID    string                 `json:"trajectoryID,omitempty"`
	StepIndex       int64                  `json:"stepIndex,omitempty"`
	ApprovalType    string                 `json:"approvalType,omitempty"`
	Decision        string                 `json:"decision,omitempty"`
	Scope           string                 `json:"scope,omitempty"`
	Prompt          string                 `json:"prompt,omitempty"`
	FilePath        string                 `json:"filePath,omitempty"`
	StreamCount     int                    `json:"streamCount,omitempty"`
	Command         string                 `json:"command,omitempty"`
	LastStepIndex   int64                  `json:"lastStepIndex,omitempty"`
	SelectedAnswers []string               `json:"selectedAnswers,omitempty"`
	CustomAnswer    string                 `json:"customAnswer,omitempty"`
	TaskID          string                 `json:"taskId,omitempty"`
	Base64Data      string                 `json:"base64Data,omitempty"`
	FileName        string                 `json:"fileName,omitempty"`
	MimeType        string                 `json:"mimeType,omitempty"`
	Data            map[string]interface{} `json:"data,omitempty"`
	Images          []string               `json:"images,omitempty"`
	// ModelUID : identifiant du modèle sélectionné dans l'app mobile
	// (requested_model_uid du cascade_config). Vide → repli sur ModelEnum.
	ModelUID string `json:"modelUID,omitempty"`
	// ModelEnum : repli historique (requested_model_id) quand ModelUID est vide.
	ModelEnum uint64 `json:"modelEnum,omitempty"`
	// Confirm : confirmation explicite exigée pour les actions destructives
	// (delete_cascade) — le mobile DOIT l'envoyer à true après dialog natif.
	Confirm bool `json:"confirm,omitempty"`
	// Content : contenu du fichier pour write_file (encodage base64 JSON → bytes).
	Content string `json:"content,omitempty"`
	// Overwrite : autorise l'écrasement pour write_file (sinon erreur si existe).
	Overwrite       bool                   `json:"overwrite,omitempty"`
	ConversationID  string                 `json:"conversationId,omitempty"`
	StepIndices     []int64                `json:"stepIndices,omitempty"`
	// Champs MCP (call_mcp_tool / connect_mcp_server / refresh_mcp_oauth_token) :
	// relayés au proxy Antigravity desktop (127.0.0.1:50999).
	ServerName string                 `json:"serverName,omitempty"`
	ToolName   string                 `json:"toolName,omitempty"`
	Arguments  map[string]interface{} `json:"arguments,omitempty"`
	Endpoint   string                 `json:"endpoint,omitempty"`
	GrantType  string                 `json:"grantType,omitempty"`
}

func (m *IncomingMessage) UnmarshalJSON(data []byte) error {
	type Alias IncomingMessage
	var raw struct {
		Alias
		ConfirmRaw   interface{} `json:"confirm"`
		OverwriteRaw interface{} `json:"overwrite"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	*m = IncomingMessage(raw.Alias)
	if raw.ConfirmRaw != nil {
		switch v := raw.ConfirmRaw.(type) {
		case bool:
			m.Confirm = v
		case string:
			m.Confirm = strings.EqualFold(v, "true") || v == "1"
		}
	}
	if raw.OverwriteRaw != nil {
		switch v := raw.OverwriteRaw.(type) {
		case bool:
			m.Overwrite = v
		case string:
			m.Overwrite = strings.EqualFold(v, "true") || v == "1"
		}
	}
	return nil
}

// hasPendingApproval rapporte si une approbation est en attente pour cette
// cascade (posée par MarkApprovalPending, retirée à la décision ou à
// l'expiration). Sans marquage, la valeur de repli est false → le stream est
// classé "done" (comportement hérité, tests inchangés).
func (s *Server) hasPendingApproval(cascadeID string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, ok := s.approvals[cascadeID]
	return ok
}

// MarkApprovalPending enregistre une approbation en attente pour une cascade
// (appelé quand un événement approval_required est émis) et arme le timer
// d'auto-refus si approvalTimeout > 0.
func (s *Server) MarkApprovalPending(cascadeID string, ev connectrpc.StreamEvent) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if prev, ok := s.approvals[cascadeID]; ok && prev.timer != nil {
		prev.timer.Stop() // une nouvelle approbation remplace l'ancienne
	}
	p := &pendingApproval{
		callID:       ev.CallID,
		cascadeID:    cascadeID,
		trajectoryID: ev.TrajectoryID,
		stepIndex:    ev.StepIndex,
		approvalType: ev.Tool,
		command:      extractCommand(ev.Detail),
		filePath:     "",
	}
	s.approvals[cascadeID] = p
	if s.approvalTimeout > 0 {
		p.timer = time.AfterFunc(s.approvalTimeout, func() { s.expireApproval(cascadeID) })
	}
}

// pendingApprovalInfo renvoie le contexte d'approbation en attente pour un
// client qui la ré-ouvre (tap sur la notification locale) : null si aucune.
// Les champs sont stables même si le stream_delta d'origine a été perdu
// (app tuée entre l'émission et le tap).
func (s *Server) pendingApprovalInfo(cascadeID string) map[string]interface{} {
	s.mu.Lock()
	defer s.mu.Unlock()
	p, ok := s.approvals[cascadeID]
	if !ok {
		return nil
	}
	expiresAt := int64(0)
	if p.timer != nil {
		expiresAt = time.Now().Add(s.approvalTimeout).UnixMilli()
	}
	return map[string]interface{}{
		"cascadeId":    p.cascadeID,
		"callId":       p.callID,
		"trajectoryId": p.trajectoryID,
		"stepIndex":    p.stepIndex,
		"approvalType": p.approvalType,
		"command":      p.command,
		"expiresAt":    expiresAt,
	}
}

// clearApproval retire une approbation en attente (décision utilisateur) et
// stoppe son timer d'expiration.
func (s *Server) clearApproval(cascadeID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if p, ok := s.approvals[cascadeID]; ok {
		if p.timer != nil {
			p.timer.Stop()
		}
		delete(s.approvals, cascadeID)
	}
}

// purgeCascadeState nettoie TOUT l'état local d'une cascade supprimée :
// buffer StepRecovery, approbation en attente, auto-approbations de session,
// stream actif. Sans cette purge, un get_pending_approval sur une cascade
// supprimée répondrait un fantôme.
func (s *Server) purgeCascadeState(cascadeID string) {
	s.streamBuffer.ClearCascade(cascadeID)
	s.mu.Lock()
	if p, ok := s.approvals[cascadeID]; ok {
		if p.timer != nil {
			p.timer.Stop()
		}
		delete(s.approvals, cascadeID)
	}
	// sessionApprovals : clés "cascadeID|type" — purge par préfixe.
	prefix := cascadeID + "|"
	for k := range s.sessionApprovals {
		if strings.HasPrefix(k, prefix) {
			delete(s.sessionApprovals, k)
		}
	}
	delete(s.activeCascades, cascadeID)
	if cancel, ok := s.activeCancels[cascadeID]; ok && cancel != nil {
		cancel()
	}
	delete(s.activeCancels, cascadeID)
	delete(s.activeRequestIDs, cascadeID)
	s.mu.Unlock()
}

// expireApproval est le callback du timer : l'approbation n'a pas reçu de
// réponse à temps → auto-refus (sécurité : téléphone perdu) puis broadcast
// approval_expired pour que toutes les surfaces nettoient la carte.
func (s *Server) expireApproval(cascadeID string) {
	s.mu.Lock()
	p, ok := s.approvals[cascadeID]
	if !ok {
		s.mu.Unlock()
		return // déjà traitée (submit) — timer obsolète
	}
	delete(s.approvals, cascadeID)
	s.mu.Unlock()

	logJSON.Info("approval_expired", "cascadeId", cascadeID)
	if p.trajectoryID != "" {
		oneofField, oneofPayload := buildApprovalPayload(p.approvalType, false, p.command, p.filePath)
		if _, err := s.RPCClient.SubmitToolApproval(cascadeID, p.trajectoryID, p.stepIndex, oneofField, oneofPayload); err != nil {
			logJSON.Error("auto_deny_failed", "cascadeId", cascadeID, "err", err)
		}
	}
	s.broadcast(OutgoingMessage{
		Type: "approval_expired",
		Data: map[string]interface{}{"cascadeId": cascadeID},
	})
}

// commandLineRe extrait la commande proposée du détail d'approbation
// run_command — accepte "command_line" (format réel) et "run_command"
// (format du blob de corrélation), comme le fallback mobile (stream_parser.dart).
var commandLineRe = regexp.MustCompile(`"(?:command_line|commandline|run_command)"\s*:\s*"((?:[^"\\]|\\.)*)"`)

func extractCommand(detail string) string {
	if m := commandLineRe.FindStringSubmatch(detail); m != nil {
		return m[1]
	}
	return ""
}

// buildApprovalPayload construit le oneof + payload HandleCascadeUserInteraction
// pour une décision. run_command = 5, file_permission = 19, permission = 21,
// approval = 23 (fallback générique). Partagé entre submit_approval et
// l'auto-refus d'expiration.
func buildApprovalPayload(approvalType string, confirm bool, command, filePath string) (int, []byte) {
	oneofField := connectrpc.InteractionApproval // fallback générique
	var oneofPayload []byte
	switch strings.ToLower(approvalType) {
	case "run_command":
		oneofField = connectrpc.InteractionRunCommand
		oneofPayload = connectrpc.BuildRunCommandInteraction(confirm, command, "")
	case "file_permission":
		oneofField = connectrpc.InteractionFilePermission
		oneofPayload = connectrpc.BuildFilePermissionInteraction(confirm, 2, filePath)
	case "permission":
		oneofField = connectrpc.InteractionPermission
		oneofPayload = connectrpc.BuildPermissionInteraction(confirm, 2)
	default:
		oneofPayload = connectrpc.BuildApprovalInteraction(confirm)
	}
	return oneofField, oneofPayload
}

// sessionApprovalKey : clé de cache « toujours autoriser pour cette session ».
func sessionApprovalKey(cascadeID, approvalType string) string {
	return cascadeID + "|" + strings.ToLower(approvalType)
}

// hasSessionApproval rapporte si l'utilisateur a déjà auto-approuvé ce type
// d'approbation pour cette cascade (B3).
func (s *Server) hasSessionApproval(cascadeID, approvalType string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.sessionApprovals[sessionApprovalKey(cascadeID, approvalType)]
}

// markSessionApproval enregistre l'auto-approbation pour le reste de la session.
func (s *Server) markSessionApproval(cascadeID, approvalType string) {
	s.mu.Lock()
	s.sessionApprovals[sessionApprovalKey(cascadeID, approvalType)] = true
	s.mu.Unlock()
}

type OutgoingMessage struct {
	Type      string      `json:"type"`
	RequestID string      `json:"requestId,omitempty"`
	Data      interface{} `json:"data,omitempty"`
	Error     string      `json:"error,omitempty"`
}

// toWorkspaceURI normalise un chemin Windows en URI file:///
func toWorkspaceURI(path string) string {
	if strings.HasPrefix(path, "file:///") {
		return path
	}
	return "file:///" + strings.ReplaceAll(path, "\\", "/")
}

// TrajectoryVerbosityFull est la verbosité par défaut de get_trajectory
// (enum ClientTrajectoryVerbosity, language_server_pb.ts ligne 257) :
// 3 = FULL → vue structurée complète (steps + métadonnées).
const TrajectoryVerbosityFull uint64 = 3

// trajectoryOut convertit une réponse GetCascadeTrajectoryResponse brute en
// JSON stable pour le mobile. Schéma vérifié dans antigravity-client
// (language_server_pb.ts ligne 8760) :
//
//	GetCascadeTrajectoryResponse {1: Trajectory, 2: status, 3: num_total_steps}
//	Trajectory {1: trajectory_id, 6: cascade_id, 2: repeated Step}
//
// Le détail des steps (oneof variants) n'est pas décodé ici : le mobile
// reçoit le nombre + les champs d'en-tête, et peut demander le diff d'un
// tour précis via get_turn_diff. Best-effort : un schéma inconnu renvoie
// le dump champs (toOutgoing) plutôt qu'une erreur.
func trajectoryOut(raw []byte) interface{} {
	if len(raw) == 0 {
		return map[string]interface{}{"steps": []interface{}{}, "numTotalSteps": 0}
	}
	// Dé-framming gRPC-Web : flags(1) + longueur BE(4) + payload.
	payload := raw
	for len(payload) >= 5 {
		length := int(binary.BigEndian.Uint32(payload[1:5]))
		if length <= 0 || 5+length > len(payload) {
			break
		}
		if payload[0]&0x80 == 0 { // frame de données
			payload = payload[5 : 5+length]
			break
		}
		payload = payload[5+length:]
	}

	fields := connectrpc.DecodeFields(payload)
	out := map[string]interface{}{
		"steps":         []interface{}{},
		"numTotalSteps": 0,
		"status":        0,
	}
	for _, f := range fields {
		switch f.Num {
		case 1: // Trajectory
			if f.WireType == 2 {
				for _, tf := range connectrpc.DecodeFields(f.Bytes) {
					switch tf.Num {
					case 1:
						if tf.WireType == 2 {
							out["trajectoryId"] = string(tf.Bytes)
						}
					case 6:
						if tf.WireType == 2 {
							out["cascadeId"] = string(tf.Bytes)
						}
					case 2: // repeated Step
						if tf.WireType == 2 {
							steps, _ := out["steps"].([]interface{})
							steps = append(steps, stepSummary(tf.Bytes))
							out["steps"] = steps
						}
					}
				}
			}
		case 2:
			if f.WireType == 0 {
				out["status"] = f.Varint
			}
		case 3:
			if f.WireType == 0 {
				out["numTotalSteps"] = f.Varint
			}
		}
	}
	return out
}

// stepSummary extrait d'un Step gemini_coder (trajectory_pb.ts ligne 302)
// les champs stables : type, status, et un best-effort du texte visible
// (description de l'action exécutée par l'agent).
func stepSummary(blob []byte) map[string]interface{} {
	s := map[string]interface{}{"type": 0, "status": 0}
	for _, f := range connectrpc.DecodeFields(blob) {
		switch f.Num {
		case 1:
			if f.WireType == 0 {
				s["type"] = f.Varint
			}
		case 4:
			if f.WireType == 0 {
				s["status"] = f.Varint
			}
		case 5, 28, 140, 12: // metadata, run_command, generic, finish
			if f.WireType == 2 {
				if text := firstReadable(f.Bytes); text != "" && s["text"] == nil {
					s["text"] = text
				}
			}
		}
	}
	return s
}

// firstReadable cherche la première chaîne UTF-8 lisible (≤300 octets) dans
// un blob de sous-message protobuf — best-effort, jamais fatal.
func firstReadable(b []byte) string {
	if s := strings.TrimSpace(string(b)); s != "" && connectrpc.IsPrintable(s) && len(s) < 300 {
		return s
	}
	for _, f := range connectrpc.DecodeFields(b) {
		if f.WireType != 2 || len(f.Bytes) == 0 {
			continue
		}
		if s := strings.TrimSpace(string(f.Bytes)); s != "" && connectrpc.IsPrintable(s) && len(s) < 300 {
			return s
		}
	}
	return ""
}

// turnDiffOut convertit une réponse GetTurnDiffResponse brute en JSON stable
// pour le mobile. Schéma vérifié (language_server_pb.ts ligne 7883) :
//
//	GetTurnDiffResponse {
//	  1: repeated FileDiffsEntry {1: key(path), 2: FileDiffData}
//	  2: total_additions   3: total_deletions
//	  4: user_input (CortexStepUserInput)   5: turn_start_index
//	  6: turn_end_index_exclusive
//	}
//	FileDiffData {1: additions, 2: deletions, 3: original_contents,
//	              4: modified_contents, 5: is_artifact_file}
func turnDiffOut(raw []byte) interface{} {
	if len(raw) == 0 {
		return map[string]interface{}{"fileDiffs": []interface{}{}, "totalAdditions": 0, "totalDeletions": 0}
	}
	payload := raw
	for len(payload) >= 5 {
		length := int(binary.BigEndian.Uint32(payload[1:5]))
		if length <= 0 || 5+length > len(payload) {
			break
		}
		if payload[0]&0x80 == 0 {
			payload = payload[5 : 5+length]
			break
		}
		payload = payload[5+length:]
	}

	fields := connectrpc.DecodeFields(payload)
	out := map[string]interface{}{
		"fileDiffs":     []interface{}{},
		"totalAdditions": 0,
		"totalDeletions": 0,
	}
	for _, f := range fields {
		switch f.Num {
		case 1: // FileDiffsEntry {1: key, 2: FileDiffData}
			if f.WireType == 2 {
				var path string
				var diff map[string]interface{}
				for _, ef := range connectrpc.DecodeFields(f.Bytes) {
					switch ef.Num {
					case 1:
						if ef.WireType == 2 {
							path = string(ef.Bytes)
						}
					case 2:
						if ef.WireType == 2 {
							diff = fileDiffData(ef.Bytes)
						}
					}
				}
				if path != "" {
					entry := map[string]interface{}{"path": path}
					if diff != nil {
						entry["diff"] = diff
					}
					diffs, _ := out["fileDiffs"].([]interface{})
					out["fileDiffs"] = append(diffs, entry)
				}
			}
		case 2:
			if f.WireType == 0 {
				out["totalAdditions"] = int64(f.Varint)
			}
		case 3:
			if f.WireType == 0 {
				out["totalDeletions"] = int64(f.Varint)
			}
		case 5:
			if f.WireType == 0 {
				out["turnStartIndex"] = int64(f.Varint)
			}
		case 6:
			if f.WireType == 0 {
				out["turnEndIndexExclusive"] = int64(f.Varint)
			}
		}
	}
	return out
}

// fileDiffData extrait un FileDiffData {1: additions, 2: deletions,
// 3: original_contents, 4: modified_contents, 5: is_artifact_file}.
func fileDiffData(blob []byte) map[string]interface{} {
	d := map[string]interface{}{
		"additions": 0, "deletions": 0,
		"originalContents": "", "modifiedContents": "", "isArtifactFile": false,
	}
	for _, f := range connectrpc.DecodeFields(blob) {
		switch f.Num {
		case 1:
			if f.WireType == 0 {
				d["additions"] = int64(f.Varint)
			}
		case 2:
			if f.WireType == 0 {
				d["deletions"] = int64(f.Varint)
			}
		case 3:
			if f.WireType == 2 {
				d["originalContents"] = string(f.Bytes)
			}
		case 4:
			if f.WireType == 2 {
				d["modifiedContents"] = string(f.Bytes)
			}
		case 5:
			if f.WireType == 0 {
				d["isArtifactFile"] = f.Varint == 1
			}
		}
	}
	return d
}

// uuidRe : les cascadeId sont des UUID v4 (36 chars, hex + tirets) émis par
// le language server. Validation stricte = pas de traversal via "../".
var uuidRe = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

// saveUploadedImage décode une image base64 et la sauvegarde dans le dossier scratch de la cascade.
func saveUploadedImage(cascadeID, fileName, base64Data string) (string, string, error) {
	if cascadeID == "" {
		return "", "", fmt.Errorf("cascadeId requis")
	}
	// Frontière de confiance : cascadeID vient du mobile (send_prompt/upload_media).
	// Un UUID v4 strict ne peut contenir ni ".." ni "/" ni "\" — un seul test
	// regex suffit à bloquer tout path traversal.
	if !uuidRe.MatchString(cascadeID) {
		return "", "", fmt.Errorf("cascadeId invalide: %q", cascadeID)
	}
	if base64Data == "" {
		return "", "", fmt.Errorf("base64Data requis")
	}

	if idx := strings.Index(base64Data, ","); idx != -1 {
		base64Data = base64Data[idx+1:]
	}

	rawBytes, err := base64.StdEncoding.DecodeString(base64Data)
	if err != nil {
		return "", "", fmt.Errorf("erreur de décodage base64: %w", err)
	}

	if len(rawBytes) > 15<<20 {
		return "", "", fmt.Errorf("image trop volumineuse (max 15 Mo)")
	}

	home, err := os.UserHomeDir()
	if err != nil {
		return "", "", fmt.Errorf("impossible de localiser le home directory: %w", err)
	}

	scratchDir := filepath.Join(home, ".gemini", "antigravity", "brain", cascadeID, "scratch")
	if err := os.MkdirAll(scratchDir, 0755); err != nil {
		return "", "", fmt.Errorf("erreur de création du dossier scratch: %w", err)
	}

	ext := ".png"
	lower := strings.ToLower(fileName)
	if strings.HasSuffix(lower, ".jpg") || strings.HasSuffix(lower, ".jpeg") {
		ext = ".jpg"
	} else if strings.HasSuffix(lower, ".webp") {
		ext = ".webp"
	} else if strings.HasSuffix(lower, ".gif") {
		ext = ".gif"
	}

	timestamp := time.Now().UnixMilli()
	safeName := fmt.Sprintf("upload_%d%s", timestamp, ext)
	targetPath := filepath.Join(scratchDir, safeName)

	if err := os.WriteFile(targetPath, rawBytes, 0644); err != nil {
		return "", "", fmt.Errorf("erreur d'écriture du fichier image: %w", err)
	}

	absPath := filepath.ToSlash(targetPath)
	markdownRef := fmt.Sprintf("![Uploaded Image](file:///%s)", absPath)
	return targetPath, markdownRef, nil
}

// toOutgoing convertit une réponse protobuf brute en JSON lisible (hex + champs).
func toOutgoing(raw []byte) interface{} {
	fields := connectrpc.DecodeFields(raw)
	if len(fields) == 0 {
		return map[string]interface{}{"rawBytes": len(raw)}
	}
	items := make([]map[string]interface{}, 0, len(fields))
	for _, f := range fields {
		item := map[string]interface{}{"field": f.Num, "wireType": f.WireType}
		if f.WireType == 0 {
			item["value"] = f.Varint
		} else {
			item["bytes"] = len(f.Bytes)
			// tente une lecture UTF-8 lisible (cascadeId, workspace, texte…)
			s := strings.TrimSpace(string(f.Bytes))
			if s != "" && connectrpc.IsPrintable(s) && len(s) < 300 {
				item["text"] = s
			}
		}
		items = append(items, item)
	}
	return map[string]interface{}{"fields": items, "rawBytes": len(raw)}
}

// sessionsOut convertit la réponse GetAllCascadeTrajectories en une liste de
// sessions structurées (cascadeId, titre, workspace, statut, updatedAt) en
// appliquant le filtre Antigravity 2.0 (exclut archivées, killed, subagents).
// Le parsing protobuf vit côté Go (connectrpc.ParseTrajectories) — le mobile
// reçoit du JSON propre au lieu d'un dump de champs binaires.
func sessionsOut(raw []byte) interface{} {
	summaries := connectrpc.ParseTrajectories(raw)
	if len(summaries) == 0 {
		local := ListLocalSessions()
		if len(local) > 0 {
			return map[string]interface{}{"sessions": local}
		}
		return map[string]interface{}{"sessions": []map[string]interface{}{}, "rawBytes": len(raw)}
	}
	items := make([]map[string]interface{}, 0, len(summaries))
	for _, s := range summaries {
		if s.Archived || s.Killed || s.Source == 16 {
			continue
		}
		items = append(items, map[string]interface{}{
			"cascadeId": s.CascadeID,
			"title":     s.Title,
			"workspace": s.Workspace,
			"projectId": s.ProjectID,
			"status":    s.Status,
			"updatedAt": s.UpdatedAt,
		})
	}
	if len(items) == 0 {
		local := ListLocalSessions()
		if len(local) > 0 {
			return map[string]interface{}{"sessions": local}
		}
	}
	return map[string]interface{}{"sessions": items}
}

func (s *Server) HandleWebSocket(w http.ResponseWriter, r *http.Request) {
	// Vérification de l'authentification si AuthToken est défini.
	// ConstantTimeCompare : évite le timing attack (token comparé en temps
	// constant) — le comportement "token optionnel" reste inchangé.
	if s.AuthToken != "" {
		clientToken := r.URL.Query().Get("token")
		if clientToken == "" {
			clientToken = r.URL.Query().Get("auth_token")
		}
		if clientToken == "" {
			clientToken = r.Header.Get("Authorization")
			clientToken = strings.TrimPrefix(clientToken, "Bearer ")
		}

		if subtle.ConstantTimeCompare([]byte(clientToken), []byte(s.AuthToken)) != 1 {
			logJSON.Warn("auth_rejected", "remote", r.RemoteAddr)
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		logJSON.Error("upgrade_error", "err", err)
		return
	}

	// Bornes anti-DoS : 1 Mo max par message + deadline globale de lecture.
	conn.SetReadLimit(maxWSMessageSize)
	conn.SetReadDeadline(time.Now().Add(pongWait))
	conn.SetPongHandler(func(string) error {
		return conn.SetReadDeadline(time.Now().Add(pongWait))
	})

	defer func() {
		s.mu.Lock()
		delete(s.clients, conn)
		delete(s.clientInFlight, conn)
		clients := len(s.clients)
		s.mu.Unlock()
		s.releaseWriteLock(conn)
		logJSON.Info("client_disconnected", "remote", conn.RemoteAddr().String(), "clients", clients)
		conn.Close()
	}()

	s.mu.Lock()
	s.clients[conn] = true
	s.clientInFlight[conn] = 0
	s.mu.Unlock()
	// Le mutex d'écriture de cette connexion existe avant la première réponse.
	s.writeLock(conn)

	logJSON.Info("client_connected", "remote", conn.RemoteAddr().String())

	// Goroutine de ping : si le pair est mort, l'écriture échoue et la
	// prochaine lecture échoue aussi → le client est purgé du broadcast.
	go func() {
		ticker := time.NewTicker(pingInterval)
		defer ticker.Stop()
		for {
			select {
		case <-ticker.C:
			s.writeLock(conn).Lock()
			err := conn.WriteControl(websocket.PingMessage, nil, time.Now().Add(10*time.Second))
			s.writeLock(conn).Unlock()
				if err != nil {
					return
				}
			}
		}
	}()

	for {
		_, message, err := conn.ReadMessage()
		if err != nil {
			logJSON.Debug("read_error", "err", err)
			break
		}
		conn.SetReadDeadline(time.Now().Add(pongWait))

		var msg IncomingMessage
		if err := json.Unmarshal(message, &msg); err != nil {
			s.writeJSON(conn, OutgoingMessage{Type: "error", Error: "Invalid JSON format"})
			continue
		}
		// send_prompt est long (streaming jusqu'à 120 s) : il tourne en
		// goroutine pour ne PAS bloquer la boucle de lecture — sinon un hub
		// lent gèlerait heartbeat, submit_approval et les autres messages
		// de la même connexion (C3). Les réponses portent leur requestId,
		// donc le client les corrèle sans ordre garanti.
		if msg.Type == "send_prompt" {
			go s.handleAction(conn, msg)
			continue
		}
		s.handleAction(conn, msg)
	}
}

func (s *Server) handleAction(conn *websocket.Conn, msg IncomingMessage) {
	uri := msg.WorkspaceURI
	if uri == "" && msg.WorkspacePath != "" {
		uri = toWorkspaceURI(msg.WorkspacePath)
	}

	var raw []byte
	var err error

	// Garde anti-blocage (C3) : tout handler unary RPC (list_sessions,
	// get_context, …) est borné par une deadline courte. Un hub lent ne doit
	// JAMAIS laisser une réponse unary indéfiniment en attente — sinon le
	// mobile (timeout 10 s) considère le daemon mort et boucle reconnexion.
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if msg.Type != "send_prompt" && msg.Type != "cancel_generation" &&
		msg.Type != "create_cascade" &&
		msg.Type != "get_pending_approval" && msg.Type != "list_files" &&
		msg.Type != "read_file" && msg.Type != "sync_session" &&
		msg.Type != "get_quota_summary" && msg.Type != "system.get_quota_summary" {
		c := make(chan struct{})
		go func() {
			select {
			case <-ctx.Done():
				s.writeJSON(conn, OutgoingMessage{Type: "error", RequestID: msg.RequestID, Error: "rpc timeout after 15s"})
			case <-c:
			}
		}()
		defer close(c)
	}

	switch msg.Type {
	// Keep-alive applicatif : le mobile envoie {"type":"ping"} toutes les
	// 20 s quand il est en arrière-plan. Même sans réponse, toute frame
	// reçue reset le read deadline (pongWait) — le ping seul suffit à
	// garder la connexion ouverte côté serveur. On répond quand même
	// pour que le client puisse mesurer la latence (round-trip).
	case "ping":
		s.writeJSON(conn, OutgoingMessage{Type: "pong", RequestID: msg.RequestID, Data: map[string]interface{}{"ts": time.Now().UnixMilli()}})
		return

	case "heartbeat":
		raw, err = s.RPCClient.Heartbeat()

	case "create_cascade":
		if uri == "" {
			err = fmt.Errorf("workspaceUri requis")
		} else {
			// projectID : résolu depuis le cache list_sessions quand dispo (coût
			// nul) — JAMAIS via un GetAllCascades synchrone ici (~9,5 s) sinon le
			// create part avec 10 s de retard et le mobile (deadline 10 s) timeoute
			// → boucle connect/disconnect. Sans cache, cascade "orpheline" : le LS
			// crée la cascade sur le workspace URI (comportement déjà existant).
			projectID, _ := s.cachedProjectID(uri)

			if projectID != "" {
				logJSON.Info("cascade_created", "projectId", projectID)
			} else {
				logJSON.Info("cascade_created_orphan")
			}

			// Le modèle vient du mobile (ModelUID) ; en l'absence de sélection
			// explicite on garde le repli commun (DefaultModelEnum, cf.
			// protobuf.go — même valeur que plan_model de BuildCascadeConfig).
			modelEnum := msg.ModelEnum
			if modelEnum == 0 && msg.ModelUID == "" {
				modelEnum = connectrpc.DefaultModelEnum
			}
			raw, err = s.RPCClient.CreateCascade(uri, projectID, msg.ModelUID, modelEnum)
		}

	case "send_command":
		if msg.Command == "" {
			err = fmt.Errorf("command requis (ex: /model, /compact)")
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: err.Error()})
			return
		}
		logJSON.Info("slash_command", "command", msg.Command)
		raw, err = s.RPCClient.SendCommand(msg.Command)

	case "list_sessions":
		// C4 : borne l'appel au LS (60 s max côté hub, on n'attend pas plus de
		// 15 s ici) — sinon un hub lent laisse la réponse unary arriver trop
		// tard : le mobile a déjà timeouté (10 s) et s'est déconnecté → boucle
		// connect/disconnect. Timeout local + réponse d'erreur explicite.
		// Cache single-flight : les reconnexions en rafale du mobile partagent
		// un SEUL appel GetAllCascades (~9,5 s) au lieu de le multiplier.
		if raw, ok := s.cachedSessions(); ok {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: sessionsOut(raw)})
			return
		}
		raw = s.fetchSessionsSingleFlight()
		if ctx.Err() != nil {
			s.writeJSON(conn, OutgoingMessage{Type: "error", RequestID: msg.RequestID, Error: "rpc timeout after 15s"})
			return
		}
		if len(raw) > 0 {
			// sessionsOut applique le filtre Antigravity 2.0 (archivées,
			// killed, subagents) + fallback sessions locales si vide.
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: sessionsOut(raw)})
			return
		}
		local := ListLocalSessions()
		s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: map[string]interface{}{"sessions": local}})
		return


	case "get_session_history":
		if msg.CascadeID == "" {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "cascadeId is required"})
			return
		}
		history, err := GetSessionHistory(msg.CascadeID)
		if err != nil {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: err.Error()})
			return
		}
		s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: map[string]interface{}{"messages": history}})
		return

	case "sync_session":
		if msg.CascadeID == "" {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "cascadeId requis"})
			return
		}
		missed, currentSeq := s.streamBuffer.GetEventsSince(msg.CascadeID, msg.LastStepIndex)
		s.writeJSON(conn, OutgoingMessage{
			Type:      "sync_catchup",
			RequestID: msg.RequestID,
			Data: map[string]interface{}{
				"cascadeId":        msg.CascadeID,
				"missedEvents":     missed,
				"currentStepIndex": currentSeq,
			},
		})
		return

	case "submit_question_response":
		if msg.CascadeID == "" {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "cascadeId requis"})
			return
		}
		var responseText string
		if len(msg.SelectedAnswers) > 0 {
			responseText = strings.Join(msg.SelectedAnswers, ", ")
		}
		if msg.CustomAnswer != "" {
			if responseText != "" {
				responseText += " (" + msg.CustomAnswer + ")"
			} else {
				responseText = msg.CustomAnswer
			}
		}
		if responseText == "" {
			responseText = "Option confirmed"
		}
		logJSON.Info("question_response", "cascadeId", msg.CascadeID, "answer", responseText)

		if s.hasPendingApproval(msg.CascadeID) {
			s.clearApproval(msg.CascadeID)
			oneofField, oneofPayload := buildApprovalPayload("ask_question", true, responseText, "")
			raw, err = s.RPCClient.SubmitToolApproval(msg.CascadeID, msg.TrajectoryID, uint32(msg.StepIndex), oneofField, oneofPayload)
			// Réponse unary au client demandeur (même contrat que
			// submit_approval) — sinon le fallthrough écrirait un dump protobuf
			// vide, et une écriture sans lecture préalable créerait une course
			// avec le stream_end diffusé en parallèle.
			if err == nil {
				s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: map[string]interface{}{"status": "submitted"}})
			}
			return
		}
		// Réponse libre : fire-and-forget vers le LS (le flux arrive par
		// SendMessageStream) — le mobile n'attend pas de réponse unary ici,
		// c'est le prochain stream_delta qui fait foi.
		go func() {
			_ = s.RPCClient.SendMessageStream(msg.CascadeID, responseText, func([]byte) error { return nil })
		}()
		return

	case "cancel_generation", "stop_generation":
		if msg.CascadeID == "" {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "cascadeId requis"})
			return
		}
		logJSON.Info("cancel_generation", "cascadeId", msg.CascadeID)
		s.CancelGeneration(msg.CascadeID)
		s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: map[string]interface{}{"status": "cancelled", "cascadeId": msg.CascadeID}})
		return

	case "send_prompt":
		if msg.CascadeID == "" || msg.Prompt == "" {
			err = fmt.Errorf("cascadeId + prompt requis")
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: err.Error()})
			return
		}
		// C1 — idempotence : un requestId déjà traité ne rejoue PAS le tour
		// (retransmission après coupure Wi-Fi). Réponse dédupliquée.
		s.mu.Lock()
		if s.sentRequestIDs[msg.RequestID] {
			s.mu.Unlock()
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: map[string]interface{}{"deduplicated": true}})
			return
		}
		// C3 — plafond de streams simultanés PAR CLIENT (anti-saturation hub).
		// Vérifié AVANT le marquage idempotent : un requestId refusé ici doit
		// pouvoir être retransmis une fois un slot libéré.
		if s.clientInFlight[conn] >= maxConcurrentStreams {
			s.mu.Unlock()
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "trop de streams simultanés (max " + itoa(maxConcurrentStreams) + ")"})
			return
		}
		s.sentRequestIDs[msg.RequestID] = true
		// C1 — borne mémoire : la map d'idempotence ne doit pas grossir sans
		// limite (un mobile qui spamme des requestId uniques). Purge FIFO simple.
		if len(s.sentRequestIDs) > 10000 {
			oldest := ""
			for id := range s.sentRequestIDs {
				if oldest == "" || id < oldest {
					oldest = id
				}
			}
			delete(s.sentRequestIDs, oldest)
		}
		s.clientInFlight[conn]++
		s.mu.Unlock()

		ctx, cancel := context.WithCancel(context.Background())
		s.mu.Lock()
		s.activeCancels[msg.CascadeID] = cancel
		s.activeRequestIDs[msg.CascadeID] = msg.RequestID
		s.mu.Unlock()

		s.MarkCascadeActive(msg.CascadeID)
		defer func() {
			s.ClearCascadeActive(msg.CascadeID)
			s.mu.Lock()
			cancel()
			delete(s.activeCancels, msg.CascadeID)
			delete(s.activeRequestIDs, msg.CascadeID)
			s.clientInFlight[conn]--
			s.mu.Unlock()
		}()
		s.broadcast(OutgoingMessage{Type: "stream_start", RequestID: msg.RequestID, Data: map[string]string{"cascadeId": msg.CascadeID}})
		logJSON.Info("stream_start", "requestId", msg.RequestID, "cascadeId", msg.CascadeID)

		// 1. Force l'IDE à afficher la conversation avant de lancer le prompt
		// (best-effort : le LS 2.5+ répond 200 sans frame de données pour
		// SetBrowserOpenConversation — l'échec est attendu et n'affecte pas
		// le stream ; le mobile re-synchronise la session lui-même).
		if _, errSet := s.RPCClient.SetBrowserOpenConversation(msg.CascadeID); errSet != nil {
			logJSON.Debug("open_conversation_failed", "cascadeId", msg.CascadeID, "err", errSet)
		}

		promptText := msg.Prompt
		if msg.Base64Data != "" {
			if _, mdRef, errImg := saveUploadedImage(msg.CascadeID, msg.FileName, msg.Base64Data); errImg == nil {
				promptText += "\n\n" + mdRef
			}
		}
		for i, b64 := range msg.Images {
			if _, mdRef, errImg := saveUploadedImage(msg.CascadeID, fmt.Sprintf("img_%d.png", i), b64); errImg == nil {
				promptText += "\n\n" + mdRef
			}
		}

		frameIndex := 0
		onFrameHandler := func(frame []byte) error {
			select {
			case <-ctx.Done():
				return fmt.Errorf("generation cancelled")
			default:
			}
			frameIndex++
			events := connectrpc.ParseFrameEvents(frame, msg.CascadeID)
			// Étape 4/6 : si la frame porte une demande d'approbation, la cascade
			// est considérée « en attente » — le stream_end le reflètera, et le
			// timer d'auto-refus est armé (approvalTimeout).
			for _, ev := range events {
				if ev.Kind == connectrpc.EventKindApprovalRequired {
					// B3 : auto-approbation si l'utilisateur a choisi
					// « toujours autoriser ce type pour la session ».
					if s.hasSessionApproval(msg.CascadeID, ev.Tool) {
						oneofField, oneofPayload := buildApprovalPayload(ev.Tool, true, extractCommand(ev.Detail), "")
						if _, errSubmit := s.RPCClient.SubmitToolApproval(
							msg.CascadeID, ev.TrajectoryID, ev.StepIndex,
							oneofField, oneofPayload,
						); errSubmit != nil {
							logJSON.Error("auto_approve_failed", "cascadeId", msg.CascadeID, "tool", ev.Tool, "err", errSubmit)
						}
					} else {
						s.MarkApprovalPending(msg.CascadeID, ev)
					}
				}
			}
			// B2 : push dédié approval_pending (avec contexte) en plus du
			// stream_delta — le mobile s'en sert au tap-notification pour
			// ré-ouvrir l'approbation même si le delta a été perdu.
			if len(events) > 0 {
				for _, ev := range events {
					if ev.Kind == connectrpc.EventKindApprovalRequired && !s.hasSessionApproval(msg.CascadeID, ev.Tool) {
						pending := s.pendingApprovalInfo(msg.CascadeID)
						// C7-B : idle detection hôte — si l'utilisateur est actif sur
						// le PC, le mobile ne sonne pas (la boîte de dialogue
						// d'approbation est déjà sous ses yeux).
						pending["hostActive"] = hostActiveSince(hostActiveWindow)
						s.broadcast(OutgoingMessage{
							Type: "approval_pending",
							Data: pending,
						})
					}
				}
			}
			data := map[string]interface{}{
				"frameIndex": frameIndex,
				"events":     events,
				"raw":        toOutgoing(frame),
				// C7-B : hostActive=true quand l'utilisateur interagit avec le
				// PC hôte → le mobile supprime ses notifications d'approbation
				// (le dialogue d'approbation est visible sur l'écran du PC).
				"hostActive": hostActiveSince(hostActiveWindow),
			}
			deltaMsg := OutgoingMessage{
				Type:      "stream_delta",
				RequestID: msg.RequestID,
				Data:      data,
			}
			stepIdx := s.streamBuffer.RecordEvent(msg.CascadeID, deltaMsg)
			data["stepIndex"] = stepIdx
			s.broadcast(deltaMsg)
			return nil
		}

		err = s.RPCClient.SendMessageStreamModel(msg.CascadeID, promptText, msg.ModelUID, msg.ModelEnum, onFrameHandler)

		// 3. Force l'IDE à ouvrir cette nouvelle session (best-effort, cf. ci-dessus).
		if _, errSet := s.RPCClient.SetBrowserOpenConversation(msg.CascadeID); errSet != nil {
			logJSON.Debug("open_conversation_failed", "cascadeId", msg.CascadeID, "err", errSet)
		}

		if ctx.Err() != nil {
			return
		}

		endData := map[string]interface{}{"cascadeId": msg.CascadeID}
		endData["hostActive"] = hostActiveSince(hostActiveWindow)
		switch {
		case err != nil && strings.Contains(err.Error(), "cancelled"):
			endData["outcome"] = "cancelled"
			endData["message"] = "Generation stopped by user"
			s.broadcast(OutgoingMessage{Type: "stream_end", RequestID: msg.RequestID, Data: endData})
		case err != nil:
			endData["outcome"] = "error"
			endData["message"] = err.Error()
			s.mu.Lock()
			s.lastError = err.Error()
			s.mu.Unlock()
			s.broadcast(OutgoingMessage{Type: "stream_end", RequestID: msg.RequestID, Data: endData, Error: err.Error()})
		case s.hasPendingApproval(msg.CascadeID):
			endData["outcome"] = "approval"
			endData["message"] = "Action requise"
			s.broadcast(OutgoingMessage{Type: "stream_end", RequestID: msg.RequestID, Data: endData})
		default:
			endData["outcome"] = "done"
			endData["message"] = ""
			s.broadcast(OutgoingMessage{Type: "stream_end", RequestID: msg.RequestID, Data: endData})
		}
		logJSON.Info("stream_end", "requestId", msg.RequestID, "cascadeId", msg.CascadeID, "outcome", endData["outcome"])
		return

	case "submit_approval":
		if msg.TrajectoryID == "" || msg.StepIndex < 0 {
			err = fmt.Errorf("trajectoryId + stepIndex requis (protocole HandleCascadeUserInteraction)")
			break
		}
		confirm := true
		if strings.EqualFold(msg.Decision, "deny") {
			confirm = false
		}
		// Étape 6 : la décision utilisateur annule le timer d'expiration AVANT
		// l'envoi (pas de course entre submit et auto-refus).
		s.clearApproval(msg.CascadeID)

		// B3 : « pour toute la session » → le daemon ne redemandera plus pour
		// ce type d'approbation sur cette cascade.
		if msg.Scope == "session" && confirm {
			s.markSessionApproval(msg.CascadeID, msg.ApprovalType)
		}

		oneofField, oneofPayload := buildApprovalPayload(msg.ApprovalType, confirm, msg.Command, msg.FilePath)
		raw, err = s.RPCClient.SubmitToolApproval(msg.CascadeID, msg.TrajectoryID, uint32(msg.StepIndex), oneofField, oneofPayload)

	case "get_pending_approval":
		// B2 : un client qui revient (tap sur la notification locale) demande
		// le contexte de l'approbation en attente — même si son stream_delta
		// d'origine a été perdu (app tuée). Réponse unary, null si aucune.
		s.writeJSON(conn, OutgoingMessage{
			Type:      "response",
			RequestID: msg.RequestID,
			Data:      s.pendingApprovalInfo(msg.CascadeID),
		})
		return
	case "list_files":
		if msg.WorkspacePath == "" {
			err = fmt.Errorf("workspacePath requis")
			break
		}
		tree, errList := buildFileTree(homeRoot(msg.WorkspacePath), "", 0)
		if errList != nil {
			err = errList
			break
		}
		s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: map[string]interface{}{"files": tree}})
		return

	case "read_file":
		if msg.FilePath == "" {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "filePath requis"})
			return
		}
		if msg.WorkspacePath != "" {
			// Confinement : le fichier doit être sous la racine workspace.
			abs, errRes := resolvePath(homeRoot(msg.WorkspacePath), msg.FilePath)
			if errRes != nil {
				s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: errRes.Error()})
				return
			}
			content, errRead := os.ReadFile(abs)
			if errRead != nil {
				s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: errRead.Error()})
				return
			}
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: map[string]interface{}{"content": string(content)}})
			return
		}
		raw, err = s.RPCClient.ReadFile(toWorkspaceURI(msg.FilePath))
		if err == nil {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: map[string]interface{}{"content": string(raw)}})
			return
		}

	case "get_context":
		var cascadeIDs []string
		if raw, errList := s.RPCClient.GetAllCascades(); errList == nil && len(raw) > 0 {
			for _, sum := range connectrpc.ParseTrajectories(raw) {
				cascadeIDs = append(cascadeIDs, sum.CascadeID)
			}
		}
		if len(cascadeIDs) == 0 {
			for _, loc := range ListLocalSessions() {
				if cid, ok := loc["cascadeId"].(string); ok && cid != "" {
					cascadeIDs = append(cascadeIDs, cid)
				}
			}
		}
		stats := map[string]int{
			"subagentsCount":       0,
			"filesChangedCount":    0,
			"artifactsCount":       0,
			"uploadsCount":         0,
			"backgroundTasksCount": 0,
		}
		for _, cid := range cascadeIDs {
			counts := countTranscriptActivity(cid)
			stats["subagentsCount"] += counts["subagents"]
			stats["filesChangedCount"] += counts["files"]
			stats["artifactsCount"] += counts["artifacts"]
			stats["uploadsCount"] += counts["uploads"]
			stats["backgroundTasksCount"] += counts["tasks"]
		}
		s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: stats})
		return


	case "upload_media", "upload_image":
		cascadeID := msg.CascadeID
		base64Data := msg.Base64Data
		fileName := msg.FileName
		if msg.Data != nil {
			if cid, ok := msg.Data["cascadeId"].(string); ok && cascadeID == "" {
				cascadeID = cid
			}
			if b64, ok := msg.Data["base64Data"].(string); ok && base64Data == "" {
				base64Data = b64
			}
			if fn, ok := msg.Data["fileName"].(string); ok && fileName == "" {
				fileName = fn
			}
		}
		if cascadeID == "" || base64Data == "" {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "cascadeId + base64Data requis"})
			return
		}
		path, mdRef, errUpload := saveUploadedImage(cascadeID, fileName, base64Data)
		if errUpload != nil {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: errUpload.Error()})
			return
		}
		logJSON.Info("media_uploaded", "cascadeId", cascadeID, "path", path)
		s.writeJSON(conn, OutgoingMessage{
			Type:      "response",
			RequestID: msg.RequestID,
			Data: map[string]interface{}{
				"filePath":    path,
				"markdownRef": mdRef,
				"status":      "ok",
			},
		})
		return

	case "list_git_branches":
		targetPath := msg.WorkspacePath
		if targetPath == "" {
			targetPath = "."
		}
		branches, errBranches := discovery.ListGitBranches(targetPath)
		if errBranches != nil {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: errBranches.Error()})
			return
		}
		s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: map[string]interface{}{"branches": branches}})
		return

	case "list_git_worktrees":
		targetPath := msg.WorkspacePath
		if targetPath == "" {
			targetPath = "."
		}
		wts, errWts := discovery.ListGitWorktrees(targetPath)
		if errWts != nil {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: errWts.Error()})
			return
		}
		s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: map[string]interface{}{"worktrees": wts}})
		return

	case "list_models":
		raw, err = s.RPCClient.ListModels()
		if err == nil {
			models, ok := connectrpc.ParseModels(raw)
			if !ok {
				// Dégradation gracieuse : schéma inconnu → liste vide + warning.
				s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: map[string]interface{}{"models": []interface{}{}, "warning": "schéma GetAvailableModels non décodable"}})
				return
			}
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: map[string]interface{}{"models": models}})
			return
		}

	case "delete_cascade":
		if msg.CascadeID == "" {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "cascadeId requis"})
			return
		}
		// Destructif et irréversible : confirmation explicite obligatoire.
		if !msg.Confirm {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "confirmation requise (champ confirm=true)"})
			return
		}
		logJSON.Info("cascade_deleted", "cascadeId", msg.CascadeID)
		_, err = s.RPCClient.DeleteCascade(msg.CascadeID)
		if err == nil {
			s.purgeCascadeState(msg.CascadeID)
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: map[string]interface{}{"status": "deleted"}})
			return
		}

	case "write_file":
		if msg.FilePath == "" || msg.Content == "" {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "filePath + content requis"})
			return
		}
		content, errDec := base64.StdEncoding.DecodeString(msg.Content)
		if errDec != nil {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "content doit être base64: " + errDec.Error()})
			return
		}
		// Confinement : comme read_file, le fichier doit être sous la racine
		// workspace — un chemin "../" venu du mobile ne doit pas écrire ailleurs.
		if msg.WorkspacePath != "" {
			abs, errRes := resolvePath(homeRoot(msg.WorkspacePath), msg.FilePath)
			if errRes != nil {
				s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: errRes.Error()})
				return
			}
			if errWrite := os.WriteFile(abs, content, 0644); errWrite != nil {
				s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: errWrite.Error()})
				return
			}
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: map[string]interface{}{"status": "written"}})
			return
		}
		_, err = s.RPCClient.WriteFile(toWorkspaceURI(msg.FilePath), content, msg.Overwrite)
		if err == nil {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: map[string]interface{}{"status": "written"}})
			return
		}

	case "list_scheduled_tasks":
		s.mu.Lock()
		tasksList := make([]*ScheduledTask, 0, len(s.scheduledTasks))
		for _, t := range s.scheduledTasks {
			tasksList = append(tasksList, t)
		}
		s.mu.Unlock()
		s.writeJSON(conn, OutgoingMessage{
			Type:      "response",
			RequestID: msg.RequestID,
			Data: map[string]interface{}{
				"tasks": tasksList,
			},
		})
		return

	case "schedule_task", "create_scheduled_task":
		taskID := msg.TaskID
		if taskID == "" {
			taskID = fmt.Sprintf("task_%d", time.Now().UnixMilli())
		}
		name := msg.Prompt
		if msg.Data != nil {
			if n, ok := msg.Data["name"].(string); ok && n != "" {
				name = n
			}
		}
		prompt := msg.Prompt
		if msg.Data != nil {
			if p, ok := msg.Data["prompt"].(string); ok && p != "" {
				prompt = p
			}
		}
		wsName := "antigravity-add-model-main"
		if msg.Data != nil {
			if w, ok := msg.Data["workspaceName"].(string); ok && w != "" {
				wsName = w
			}
		}
		cron := "0 9 * * *"
		if msg.Data != nil {
			if c, ok := msg.Data["cronExpression"].(string); ok && c != "" {
				cron = c
			}
		}
		enabled := true
		if msg.Data != nil {
			if en, ok := msg.Data["isEnabled"].(bool); ok {
				enabled = en
			}
		}

		task := &ScheduledTask{
			ID:             taskID,
			Name:           name,
			Prompt:         prompt,
			WorkspaceName:  wsName,
			CronExpression: cron,
			IsDaemon:       true,
			IterationsRun:  0,
			IsEnabled:      enabled,
			Status:         "Running",
			Uptime:         "0m",
			Events:         []ScheduledTaskEvent{},
		}

		s.mu.Lock()
		s.scheduledTasks[taskID] = task
		s.mu.Unlock()

		logJSON.Info("scheduled_task_created", "taskId", taskID, "name", name)
		s.broadcast(OutgoingMessage{
			Type: "scheduled_task_created",
			Data: map[string]interface{}{"task": task},
		})
		s.writeJSON(conn, OutgoingMessage{
			Type:      "response",
			RequestID: msg.RequestID,
			Data: map[string]interface{}{
				"task":   task,
				"status": "created",
			},
		})
		return

	case "update_scheduled_task":
		taskID := msg.TaskID
		if msg.Data != nil {
			if tid, ok := msg.Data["id"].(string); ok && taskID == "" {
				taskID = tid
			} else if tid, ok := msg.Data["taskId"].(string); ok && taskID == "" {
				taskID = tid
			}
		}
		if taskID == "" {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "taskId requis"})
			return
		}

		s.mu.Lock()
		task, exists := s.scheduledTasks[taskID]
		if !exists {
			task = &ScheduledTask{
				ID:        taskID,
				Status:    "Running",
				Uptime:    "1m",
				Events:    []ScheduledTaskEvent{},
				IsDaemon:  true,
				IsEnabled: true,
			}
			s.scheduledTasks[taskID] = task
		}
		if msg.Data != nil {
			if n, ok := msg.Data["name"].(string); ok {
				task.Name = n
			}
			if p, ok := msg.Data["prompt"].(string); ok {
				task.Prompt = p
			}
			if c, ok := msg.Data["cronExpression"].(string); ok {
				task.CronExpression = c
			}
			if en, ok := msg.Data["isEnabled"].(bool); ok {
				task.IsEnabled = en
				if en {
					task.Status = "Running"
				} else {
					task.Status = "Paused"
				}
			}
			if st, ok := msg.Data["status"].(string); ok {
				task.Status = st
			}
		}
		s.mu.Unlock()

		logJSON.Info("scheduled_task_updated", "taskId", taskID)
		s.broadcast(OutgoingMessage{
			Type: "scheduled_task_updated",
			Data: map[string]interface{}{"task": task},
		})
		s.writeJSON(conn, OutgoingMessage{
			Type:      "response",
			RequestID: msg.RequestID,
			Data: map[string]interface{}{
				"task":   task,
				"status": "updated",
			},
		})
		return

	case "trigger_scheduled_task":
		taskId := msg.TaskID
		if msg.Data != nil {
			if tid, ok := msg.Data["taskId"].(string); ok && taskId == "" {
				taskId = tid
			} else if tid, ok := msg.Data["id"].(string); ok && taskId == "" {
				taskId = tid
			}
		}
		logJSON.Info("scheduled_task_triggered", "taskId", taskId)
		// ponytail: aucun moteur cron réel dans le daemon — refuser explicitement
		// plutôt que de fabriquer un événement "done" (mock prod interdit).
		// Upgrade path : brancher un scheduler (robfig/cron) et exécuter le prompt.
		s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID,
			Error: "scheduled tasks not implemented: no cron engine in daemon"})
		return

	case "cancel_scheduled_task", "delete_scheduled_task":
		taskId := msg.TaskID
		if msg.Data != nil {
			if tid, ok := msg.Data["taskId"].(string); ok && taskId == "" {
				taskId = tid
			} else if tid, ok := msg.Data["id"].(string); ok && taskId == "" {
				taskId = tid
			}
		}
		s.mu.Lock()
		delete(s.scheduledTasks, taskId)
		s.mu.Unlock()

		logJSON.Info("scheduled_task_cancelled", "taskId", taskId)
		s.broadcast(OutgoingMessage{
			Type: "scheduled_task_deleted",
			Data: map[string]interface{}{"taskId": taskId},
		})
		s.writeJSON(conn, OutgoingMessage{
			Type:      "response",
			RequestID: msg.RequestID,
			Data: map[string]interface{}{
				"taskId": taskId,
				"status": "cancelled",
			},
		})
		return

	case "set_approval_timeout":
		var minutes float64
		if msg.Data != nil {
			if m, ok := msg.Data["minutes"].(float64); ok {
				minutes = m
			} else if m, ok := msg.Data["minutes"].(int); ok {
				minutes = float64(m)
			}
		} else {
			minutes = -1
		}
		if minutes < 0 {
			s.writeJSON(conn, OutgoingMessage{
				Type:      "response",
				RequestID: msg.RequestID,
				Error:     "minutes (nombre ≥ 0) requis",
			})
			return
		}
		s.SetApprovalTimeout(time.Duration(minutes * float64(time.Minute)))
		s.writeJSON(conn, OutgoingMessage{
			Type:      "response",
			RequestID: msg.RequestID,
			Data: map[string]interface{}{
				"approvalTimeoutMinutes": minutes,
			},
		})
		return

	case "get_trajectory":
		// C9 — historique structuré d'une session : le mobile demande le
		// détail d'une cascade (turns, steps) via le RPC officiel
		// GetCascadeTrajectory. Réponse unary — le JSON structuré est fourni
		// par trajectoryOut (pas le dump binaire).
		if msg.CascadeID == "" {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "cascadeId requis"})
			return
		}
		verbosity := TrajectoryVerbosityFull
		if msg.Data != nil {
			if v, ok := msg.Data["verbosity"].(float64); ok && v >= 0 {
				verbosity = uint64(v)
			}
		}
		raw, err = s.RPCClient.GetCascadeTrajectory(msg.CascadeID, verbosity)
		if err == nil {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: trajectoryOut(raw)})
			return
		}

	case "get_turn_diff":
		// C9 — diff officiel d'un tour : {conversationId, stepIndex} → diff
		// des fichiers modifiés par ce tour (GetTurnDiff). stepIndex absent
		// ou négatif → le LS résout le dernier tour.
		conversationID := msg.CascadeID
		if msg.Data != nil {
			if cid, ok := msg.Data["conversationId"].(string); ok && cid != "" {
				conversationID = cid
			}
		}
		if conversationID == "" {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "conversationId requis"})
			return
		}
		stepIndex := int64(-1) // absent → le LS résout le dernier tour
		if msg.StepIndex != 0 {
			stepIndex = msg.StepIndex
		}
		if msg.Data != nil {
			if si, ok := msg.Data["stepIndex"].(float64); ok {
				stepIndex = int64(si)
			}
		}
		raw, err = s.RPCClient.GetTurnDiff(conversationID, stepIndex)
		if err == nil {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: turnDiffOut(raw)})
			return
		}

	case "get_revert_preview", "cascade.get_revert_preview":
		if msg.CascadeID == "" {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "cascadeId requis"})
			return
		}
		raw, err = s.RPCClient.GetRevertPreview(msg.CascadeID, msg.StepIndex)
		if err == nil {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: toOutgoing(raw)})
			return
		}

	case "revert_to_step", "cascade.revert_to_step":
		if msg.CascadeID == "" || msg.StepIndex < 0 {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "cascadeId + stepIndex requis"})
			return
		}
		err = s.RPCClient.RevertToCascadeStep(msg.CascadeID, msg.StepIndex)
		if err == nil {
			s.broadcast(OutgoingMessage{
				Type: "cascade_reverted",
				Data: map[string]interface{}{
					"cascadeId": msg.CascadeID,
					"stepIndex": msg.StepIndex,
				},
			})
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: map[string]interface{}{"status": "reverted", "cascadeId": msg.CascadeID, "stepIndex": msg.StepIndex}})
			return
		}

	case "send_steps_to_background", "cascade.send_to_background":
		convID := msg.ConversationID
		if convID == "" {
			convID = msg.CascadeID
		}
		if convID == "" {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "conversationId ou cascadeId requis"})
			return
		}
		indices := msg.StepIndices
		if len(indices) == 0 && msg.StepIndex >= 0 {
			indices = []int64{msg.StepIndex}
		}
		err = s.RPCClient.SendStepsToBackground(convID, indices)
		if err == nil {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: map[string]interface{}{"status": "sent_to_background", "conversationId": convID, "stepIndices": indices}})
			return
		}

	case "skip_browser_subagent", "cascade.skip_subagent":
		if msg.CascadeID == "" {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: "cascadeId requis"})
			return
		}
		err = s.RPCClient.SkipBrowserSubagent(msg.CascadeID, msg.StepIndex)
		if err == nil {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: map[string]interface{}{"status": "skipped", "cascadeId": msg.CascadeID, "stepIndex": msg.StepIndex}})
			return
		}

	case "get_quota_summary", "system.get_quota_summary":
		raw, err = s.RPCClient.RetrieveUserQuotaSummary()
		if err == nil {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: toOutgoing(raw)})
			return
		}

	case "call_mcp_tool", "connect_mcp_server", "refresh_mcp_oauth_token":
		// Route les actions MCP vers le proxy Antigravity desktop
		// (127.0.0.1:50999). Le mobile n'a pas les identifiants MCP :
		// la session du PC est le seul détenteur des jetons OAuth et de
		// l'allowlist stricte. Réponse unary relayée telle quelle.
		s.handleMcpAction(conn, msg)
		return

	default:
		s.writeJSON(conn, OutgoingMessage{Type: "error", RequestID: msg.RequestID, Error: "Unknown action type: " + msg.Type})
		return
	}

	if err != nil {
		s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: err.Error()})
		return
	}
	// Réponse unary au client DEMANDEUR uniquement : un broadcast polluerait
	// les autres surfaces (elles n'ont pas ce requestId) et casserait la
	// corrélation des tests.
	s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: toOutgoing(raw)})
}

// homeRoot : résout un chemin relatif (ex: .gemini/antigravity-ide/brain/...)
// contre le home de l'utilisateur — le CWD du daemon n'est pas fiable (il peut
// être lancé depuis n'importe où). Les chemins absolus passent inchangés.
func homeRoot(root string) string {
	if root == "" || filepath.IsAbs(root) {
		return root
	}
	if home, err := os.UserHomeDir(); err == nil {
		return filepath.Join(home, root)
	}
	return root
}

// resolvePath confine un chemin demandé sous une racine : rejette les
// traversées (..), les chemins absolus hors racine et les variantes
// casse/volumes qui sortiraient de root.
func resolvePath(root, requested string) (string, error) {
	rootAbs, err := filepath.Abs(root)
	if err != nil {
		return "", err
	}
	// Le chemin demandé peut être relatif au workspace, ou absolu mais
	// sous la racine (le mobile envoie des fullPath issus du tree).
	requested = filepath.Clean(requested)
	var candidate string
	if filepath.IsAbs(requested) {
		candidate = requested
	} else {
		candidate = filepath.Join(rootAbs, requested)
	}
	candidate = filepath.Clean(candidate)

	rel, err := filepath.Rel(rootAbs, candidate)
	if err != nil {
		return "", err
	}
	if rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("chemin hors workspace: %s", requested)
	}
	return candidate, nil
}

// maxTreeDepth borne la récursion de buildFileTree (anti-boucle symlink).
const maxTreeDepth = 8

func buildFileTree(root, relativePath string, depth int) ([]map[string]interface{}, error) {
	if depth > maxTreeDepth {
		return nil, nil
	}
	var result []map[string]interface{}
	fullPath := filepath.Join(root, relativePath)
	entries, err := os.ReadDir(fullPath)
	if err != nil {
		return nil, err
	}

	sort.Slice(entries, func(i, j int) bool {
		if entries[i].IsDir() == entries[j].IsDir() {
			return entries[i].Name() < entries[j].Name()
		}
		return entries[i].IsDir()
	})

	for _, entry := range entries {
		name := entry.Name()
		if name == ".git" || name == "node_modules" || name == "build" || name == "dist" || name == ".dart_tool" {
			continue
		}

		// Anti-symlink : un lien vers un répertoire parent créerait une
		// récursion infinie (depth n'est pas borné par le contenu réel).
		info, errInfo := os.Lstat(fullPath + string(filepath.Separator) + name)
		if errInfo != nil {
			continue
		}
		if info.Mode()&os.ModeSymlink != 0 {
			continue
		}

		item := map[string]interface{}{
			"name":     name,
			"path":     filepath.Join(relativePath, name),
			"fullPath": filepath.Join(fullPath, name),
			"depth":    depth,
			"isDir":    entry.IsDir(),
		}
		result = append(result, item)

		if entry.IsDir() {
			children, _ := buildFileTree(root, filepath.Join(relativePath, name), depth+1)
			result = append(result, children...)
		}
	}
	return result, nil
}
