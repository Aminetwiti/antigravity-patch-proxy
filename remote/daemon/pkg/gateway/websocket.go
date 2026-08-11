package gateway

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"

	"github.com/antigravity/remote-daemon/pkg/connectrpc"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

type Server struct {
	RPCClient *connectrpc.Client
	clients   map[*websocket.Conn]bool
	mu        sync.Mutex
}

func NewServer(client *connectrpc.Client) *Server {
	return &Server{
		RPCClient: client,
		clients:   make(map[*websocket.Conn]bool),
	}
}

type IncomingMessage struct {
	Type          string                 `json:"type"`
	RequestID     string                 `json:"requestId"`
	WorkspacePath string                 `json:"workspacePath,omitempty"`
	CascadeID     string                 `json:"cascadeId,omitempty"`
	CallID        string                 `json:"callId,omitempty"`
	Decision      string                 `json:"decision,omitempty"`
	Prompt        string                 `json:"prompt,omitempty"`
	Payload       map[string]interface{} `json:"payload,omitempty"`
}

type OutgoingMessage struct {
	Type      string      `json:"type"`
	RequestID string      `json:"requestId,omitempty"`
	Data      interface{} `json:"data,omitempty"`
	Error     string      `json:"error,omitempty"`
}

func (s *Server) HandleWebSocket(w http.ResponseWriter, r *http.Request) {
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
	switch msg.Type {
	case "create_cascade":
		res, err := s.RPCClient.CreateCascade(msg.WorkspacePath)
		if err != nil {
			conn.WriteJSON(OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: err.Error()})
		} else {
			conn.WriteJSON(OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: res})
		}

	case "list_sessions":
		res, err := s.RPCClient.GetAllCascades()
		if err != nil {
			conn.WriteJSON(OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: err.Error()})
		} else {
			conn.WriteJSON(OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: res})
		}

	case "submit_approval":
		res, err := s.RPCClient.SubmitToolApproval(msg.CascadeID, msg.CallID, msg.Decision)
		if err != nil {
			conn.WriteJSON(OutgoingMessage{Type: "response", RequestID: msg.RequestID, Error: err.Error()})
		} else {
			conn.WriteJSON(OutgoingMessage{Type: "response", RequestID: msg.RequestID, Data: res})
		}

	default:
		conn.WriteJSON(OutgoingMessage{Type: "error", RequestID: msg.RequestID, Error: "Unknown action type: " + msg.Type})
	}
}
