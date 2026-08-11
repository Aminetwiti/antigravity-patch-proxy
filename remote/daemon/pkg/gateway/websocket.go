package gateway

import (
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
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

// RPCClient est l'ensemble des méthodes du backend LanguageServer utilisées
// par le gateway (interface minimale pour permettre les tests avec un faux).
type RPCClient interface {
	Heartbeat() ([]byte, error)
	CreateCascade(uri string, projectID string, model uint64) ([]byte, error)
	GetAllCascades() ([]byte, error)
	SendMessageStream(cascadeID, text string, onFrame func([]byte) error) error
	SubmitToolApproval(cascadeID, callID string, decision uint64) ([]byte, error)
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

type Server struct {
	RPCClient RPCClient
	AuthToken string
	clients   map[*websocket.Conn]bool
	mu        sync.Mutex
	// writeMu sérialise les écritures : gorilla/websocket n'autorise qu'un
	// seul writer concurrent par connexion, or le broadcast écrit sur toutes.
	writeMu sync.Mutex
}

func NewServer(client RPCClient, authToken string) *Server {
	return &Server{
		RPCClient: client,
		AuthToken: authToken,
		clients:   make(map[*websocket.Conn]bool),
	}
}

// maxWSMessageSize borne la taille des messages WebSocket entrants (1 Mo)
// pour empêcher un client de faire un DoS mémoire.
const maxWSMessageSize = 1 << 20

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
		log.Printf("[WS] Write error: %v", err)
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
	Decision      string `json:"decision,omitempty"`
	Prompt        string `json:"prompt,omitempty"`
	FilePath      string `json:"filePath,omitempty"`
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
			log.Printf("[WS] Tentative de connexion rejetée : token invalide")
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[WS] Upgrade error: %v", err)
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
		s.mu.Unlock()
		conn.Close()
	}()

	s.mu.Lock()
	s.clients[conn] = true
	s.mu.Unlock()

	log.Println("[WS] Mobile Client Connected")

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
			log.Printf("[WS] Read error: %v", err)
			break
		}

		var msg IncomingMessage
		if err := json.Unmarshal(message, &msg); err != nil {
			s.writeJSON(conn, OutgoingMessage{Type: "error", Error: "Invalid JSON format"})
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
				log.Printf("[WS] Création de cascade rattachée au projet: %s", projectID)
			} else {
				log.Printf("[WS] Création de cascade orpheline (aucun projet trouvé)")
			}

			raw, err = s.RPCClient.CreateCascade(uri, projectID, 190)
		}

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
		s.broadcast(OutgoingMessage{Type: "stream_start", RequestID: msg.RequestID, Data: map[string]string{"cascadeId": msg.CascadeID}})
		frameIndex := 0
		err = s.RPCClient.SendMessageStream(msg.CascadeID, msg.Prompt, func(frame []byte) error {
			frameIndex++
			events := connectrpc.ParseFrameEvents(frame, msg.CascadeID)
			data := map[string]interface{}{
				"frameIndex": frameIndex,
				"events":     events,
				"raw":        toOutgoing(frame),
			}
			// Étape 3 : si l'utilisateur est actif sur le PC hôte, l'approbation
			// est déjà visible à l'écran → pas de notification sur le téléphone.
			if hostActiveSince(10 * time.Second) {
				data["hostActive"] = true
			}
			s.broadcast(OutgoingMessage{
				Type:      "stream_delta",
				RequestID: msg.RequestID,
				Data:      data,
			})
			return nil
		})
		if err != nil {
			s.broadcast(OutgoingMessage{Type: "stream_end", RequestID: msg.RequestID, Error: err.Error()})
		} else {
			s.broadcast(OutgoingMessage{Type: "stream_end", RequestID: msg.RequestID})
		}
		return

	case "submit_approval":
		decision := uint64(1) // DECISION_ALLOW par défaut
		if strings.EqualFold(msg.Decision, "deny") {
			decision = 2
		}
		raw, err = s.RPCClient.SubmitToolApproval(msg.CascadeID, msg.CallID, decision)

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
