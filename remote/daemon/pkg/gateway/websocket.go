package gateway

import (
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"log/slog"
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
	CreateCascade(uri string, projectID string, model uint64) ([]byte, error)
	GetAllCascades() ([]byte, error)
	SendMessageStream(cascadeID, text string, onFrame func([]byte) error) error
	SubmitToolApproval(cascadeID, trajectoryID string, stepIndex uint32, oneofField int, oneofPayload []byte) ([]byte, error)
	SetBrowserOpenConversation(cascadeID string) ([]byte, error)
	SendCommand(commandText string) ([]byte, error)
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
	return h == "localhost" || h == "127.0.0.1" || h == "::1"
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
	// writeMu sérialise les écritures : gorilla/websocket n'autorise qu'un
	// seul writer concurrent par connexion, or le broadcast écrit sur toutes.
	writeMu sync.Mutex
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
}

// Stats snapshot de l'état du serveur pour l'endpoint /health (C5).
// Champs JSON stables — le mobile (ou un script) peut les afficher tels quels.
type Stats struct {
	Status       string   `json:"status"`
	Sessions     int      `json:"sessions"`
	Streams      int      `json:"streams"`
	Clients      int      `json:"clients"`
	Uptime       string   `json:"uptime"`
	ActiveCascades []string `json:"activeCascades"`
	LastError    string   `json:"lastError,omitempty"`
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
	}
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

// SetApprovalTimeout configure le délai avant auto-refus d'une approbation
// (0 = désactivé). Appelable avant l'acceptation de connexions.
func (s *Server) SetApprovalTimeout(d time.Duration) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.approvalTimeout = d
}

// maxWSMessageSize borne la taille des messages WebSocket entrants (1 Mo)
// pour empêcher un client de faire un DoS mémoire.
const maxWSMessageSize = 1 << 20

// maxConcurrentStreams : nombre maximum de send_prompt simultanés PAR CLIENT
// (C3). Au-delà, la requête est refusée avec une erreur explicite — un seul
// téléphone ne peut pas saturer le hub.
const maxConcurrentStreams = 2

// pingInterval / pongWait : garde-fous de connexions mortes. Le ping échoue
// si le pair ne répond pas (network parti, app fermée) → read error → le
// client est retiré du broadcast.
const (
	pingInterval = 30 * time.Second
	pongWait     = 60 * time.Second
)

// writeJSON envoie un message à une connexion donnée (writer unique sérialisé).
func (s *Server) writeJSON(conn *websocket.Conn, msg OutgoingMessage) {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	if err := conn.WriteJSON(msg); err != nil {
		logJSON.Warn("write_error", "err", err)
	}
}

// broadcast envoie le même message à TOUS les clients connectés : c'est ce qui
// permet la synchronisation multi-surface (un téléphone voit le stream déclenché
// par le PC ou par un autre téléphone).
func (s *Server) broadcast(msg OutgoingMessage) {
	s.mu.Lock()
	conns := make([]*websocket.Conn, 0, len(s.clients))
	for c := range s.clients {
		conns = append(conns, c)
	}
	s.mu.Unlock()
	for _, c := range conns {
		s.writeJSON(c, msg)
	}
}

type IncomingMessage struct {
	Type          string `json:"type"`
	RequestID     string `json:"requestId"`
	WorkspaceURI  string `json:"workspaceUri"`
	WorkspacePath string `json:"workspacePath,omitempty"`
	CascadeID     string `json:"cascadeId,omitempty"`
	CallID        string `json:"callId,omitempty"`
	TrajectoryID  string `json:"trajectoryID,omitempty"`
	StepIndex     int64  `json:"stepIndex,omitempty"`
	ApprovalType  string `json:"approvalType,omitempty"`
	Decision      string `json:"decision,omitempty"`
	Scope         string `json:"scope,omitempty"`
	Prompt        string `json:"prompt,omitempty"`
	FilePath      string `json:"filePath,omitempty"`
	StreamCount   int    `json:"streamCount,omitempty"`
	Command       string `json:"command,omitempty"`
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
// sessions structurées (cascadeId, titre, workspace, statut, updatedAt).
// Le parsing protobuf vit côté Go (connectrpc.ParseTrajectories) — le mobile
// reçoit du JSON propre au lieu d'un dump de champs binaires.
func sessionsOut(raw []byte) interface{} {
	summaries := connectrpc.ParseTrajectories(raw)
	if len(summaries) == 0 {
		return map[string]interface{}{"rawBytes": len(raw)}
	}
	items := make([]map[string]interface{}, 0, len(summaries))
	for _, s := range summaries {
		items = append(items, map[string]interface{}{
			"cascadeId": s.CascadeID,
			"title":     s.Title,
			"workspace": s.Workspace,
			"projectId": s.ProjectID,
			"status":    s.Status,
			"updatedAt": s.UpdatedAt,
		})
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
		logJSON.Info("client_disconnected", "remote", conn.RemoteAddr().String(), "clients", clients)
		conn.Close()
	}()

	s.mu.Lock()
	s.clients[conn] = true
	s.mu.Unlock()

	logJSON.Info("client_connected", "remote", conn.RemoteAddr().String())

	// Goroutine de ping : si le pair est mort, l'écriture échoue et la
	// prochaine lecture échoue aussi → le client est purgé du broadcast.
	go func() {
		ticker := time.NewTicker(pingInterval)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				if err := conn.WriteControl(websocket.PingMessage, nil, time.Now().Add(10*time.Second)); err != nil {
					conn.Close()
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

	switch msg.Type {
	case "heartbeat":
		raw, err = s.RPCClient.Heartbeat()

	case "create_cascade":
		if uri == "" {
			err = fmt.Errorf("workspaceUri requis")
		} else {
			var projectID string
			if rawList, errList := s.RPCClient.GetAllCascades(); errList == nil {
				summaries := connectrpc.ParseTrajectories(rawList)
				for _, sum := range summaries {
					if sum.ProjectID != "" && strings.EqualFold(sum.Workspace, uri) {
						projectID = sum.ProjectID
						break
					}
				}
			}

			if projectID != "" {
				logJSON.Info("cascade_created", "projectId", projectID)
			} else {
				logJSON.Info("cascade_created_orphan")
			}

			raw, err = s.RPCClient.CreateCascade(uri, projectID, 190)
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
		raw, err = s.RPCClient.GetAllCascades()
		if err != nil {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: err.Error()})
			return
		}
		s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: sessionsOut(raw)})
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
		s.clientInFlight[conn]++
		s.mu.Unlock()

		s.MarkCascadeActive(msg.CascadeID)
		defer func() {
			s.ClearCascadeActive(msg.CascadeID)
			s.mu.Lock()
			s.clientInFlight[conn]--
			s.mu.Unlock()
		}()
		s.broadcast(OutgoingMessage{Type: "stream_start", RequestID: msg.RequestID, Data: map[string]string{"cascadeId": msg.CascadeID}})
		logJSON.Info("stream_start", "requestId", msg.RequestID, "cascadeId", msg.CascadeID)

		// 1. Force l'IDE à afficher la conversation avant de lancer le prompt
		if _, errSet := s.RPCClient.SetBrowserOpenConversation(msg.CascadeID); errSet != nil {
			logJSON.Warn("open_conversation_failed", "cascadeId", msg.CascadeID, "err", errSet)
		}

		frameIndex := 0
		err = s.RPCClient.SendMessageStream(msg.CascadeID, msg.Prompt, func(frame []byte) error {
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
						s.broadcast(OutgoingMessage{
							Type: "approval_pending",
							Data: s.pendingApprovalInfo(msg.CascadeID),
						})
					}
				}
			}
			data := map[string]interface{}{
				"frameIndex": frameIndex,
				"events":     events,
				"raw":        toOutgoing(frame),
			}
			s.broadcast(OutgoingMessage{
				Type:      "stream_delta",
				RequestID: msg.RequestID,
				Data:      data,
			})
			return nil
		})

		// 3. Force l'IDE à ouvrir cette nouvelle session
		if _, errSet := s.RPCClient.SetBrowserOpenConversation(msg.CascadeID); errSet != nil {
			logJSON.Warn("open_conversation_failed", "cascadeId", msg.CascadeID, "err", errSet)
		}

		endData := map[string]interface{}{"cascadeId": msg.CascadeID}
		switch {
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
		tree, errList := buildFileTree(msg.WorkspacePath, "", 0)
		if errList != nil {
			err = errList
			break
		}
		s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: map[string]interface{}{"files": tree}})
		return

	case "read_file":
		if msg.WorkspacePath == "" || msg.FilePath == "" {
			err = fmt.Errorf("workspacePath + filePath requis")
			break
		}
		// Confinement : le fichier doit être sous la racine workspace.
		abs, errRes := resolvePath(msg.WorkspacePath, msg.FilePath)
		if errRes != nil {
			err = errRes
			break
		}
		content, errRead := os.ReadFile(abs)
		if errRead != nil {
			err = errRead
			break
		}
		s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: map[string]interface{}{"content": string(content)}})
		return

	case "get_context":
		raw, err = s.RPCClient.GetAllCascades()
		if err != nil {
			s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: err.Error()})
			return
		}
		summaries := connectrpc.ParseTrajectories(raw)
		stats := map[string]int{
			"subagentsCount":       0,
			"filesChangedCount":    0,
			"artifactsCount":       len(summaries),
			"uploadsCount":         0,
			"backgroundTasksCount": 0,
		}
		s.writeJSON(conn, OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: stats})
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
