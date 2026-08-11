package gateway

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"sync"

	"github.com/antigravity/remote-daemon/pkg/connectrpc"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

type Server struct {
	RPCClient *connectrpc.Client
	AuthToken string
	clients   map[*websocket.Conn]bool
	mu        sync.Mutex
}

func NewServer(client *connectrpc.Client, authToken string) *Server {
	return &Server{
		RPCClient: client,
		AuthToken: authToken,
		clients:   make(map[*websocket.Conn]bool),
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
			if s != "" && isPrintable(s) && len(s) < 300 {
				item["text"] = s
			}
		}
		items = append(items, item)
	}
	return map[string]interface{}{"fields": items, "rawBytes": len(raw)}
}

func isPrintable(s string) bool {
	for _, r := range s {
		if r < 0x20 || r > 0x7e {
			if r != '\n' && r != '\t' && r != '\r' {
				return false
			}
		}
	}
	return true
}

func (s *Server) HandleWebSocket(w http.ResponseWriter, r *http.Request) {
	// Vérification de l'authentification si AuthToken est défini
	if s.AuthToken != "" {
		clientToken := r.URL.Query().Get("token")
		if clientToken == "" {
			clientToken = r.Header.Get("Authorization")
			clientToken = strings.TrimPrefix(clientToken, "Bearer ")
		}
		
		if clientToken != s.AuthToken {
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

	for {
		_, message, err := conn.ReadMessage()
		if err != nil {
			log.Printf("[WS] Read error: %v", err)
			break
		}

		var msg IncomingMessage
		if err := json.Unmarshal(message, &msg); err != nil {
			conn.WriteJSON(OutgoingMessage{Type: "error", Error: "Invalid JSON format"})
			continue
		}
		s.handleAction(conn, msg)
	}
}

func (s *Server) handleAction(conn *websocket.Conn, msg IncomingMessage) {
	uri := msg.WorkspaceURI
	if uri == "" {
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
			raw, err = s.RPCClient.CreateCascade(uri, 190)
		}

	case "list_sessions":
		raw, err = s.RPCClient.GetAllCascades()

	case "send_prompt":
		if msg.CascadeID == "" || msg.Prompt == "" {
			err = fmt.Errorf("cascadeId + prompt requis")
			conn.WriteJSON(OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: err.Error()})
			return
		}
		conn.WriteJSON(OutgoingMessage{Type: "stream_start", RequestID: msg.RequestID, Data: map[string]string{"cascadeId": msg.CascadeID}})
		frameIndex := 0
		err = s.RPCClient.SendMessageStream(msg.CascadeID, msg.Prompt, func(frame []byte) error {
			frameIndex++
			events := connectrpc.ParseFrameEvents(frame, msg.CascadeID)
			conn.WriteJSON(OutgoingMessage{
				Type:      "stream_delta",
				RequestID: msg.RequestID,
				Data: map[string]interface{}{
					"frameIndex": frameIndex,
					"events":     events,
					"raw":        toOutgoing(frame),
				},
			})
			return nil
		})
		if err != nil {
			conn.WriteJSON(OutgoingMessage{Type: "stream_end", RequestID: msg.RequestID, Error: err.Error()})
		} else {
			conn.WriteJSON(OutgoingMessage{Type: "stream_end", RequestID: msg.RequestID})
		}
		return

	case "submit_approval":
		decision := uint64(1) // DECISION_ALLOW par défaut
		if strings.EqualFold(msg.Decision, "deny") {
			decision = 2
		}
		raw, err = s.RPCClient.SubmitToolApproval(msg.CascadeID, msg.CallID, decision)

	default:
		conn.WriteJSON(OutgoingMessage{Type: "error", RequestID: msg.RequestID, Error: "Unknown action type: " + msg.Type})
		return
	}

	if err != nil {
		conn.WriteJSON(OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: err.Error()})
		return
	}
	conn.WriteJSON(OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: toOutgoing(raw)})
}
