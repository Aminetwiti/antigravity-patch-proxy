package gateway

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/antigravity/remote-daemon/pkg/connectrpc"
	"github.com/gorilla/websocket"
)

func TestToWorkspaceURI(t *testing.T) {
	cases := map[string]string{
		`C:\Users\test\proj`:         "file:///C:/Users/test/proj",
		`C:/Users/test/proj`:         "file:///C:/Users/test/proj",
		"file:///C:/Users/test/proj": "file:///C:/Users/test/proj",
	}
	for in, want := range cases {
		if got := toWorkspaceURI(in); got != want {
			t.Errorf("toWorkspaceURI(%q) = %q, attendu %q", in, got, want)
		}
	}
}

// TestToOutgoing vérifie la conversion d'une réponse protobuf brute en JSON lisible.
func TestToOutgoing(t *testing.T) {
	// Frame protobuf : champ #1 length-delimited "casc-1" + champ #14 varint 190.
	buf := []byte{0x0a, 0x06, 'c', 'a', 's', 'c', '-', '1', 0x70, 0xbe, 0x01}
	out := toOutgoing(buf).(map[string]interface{})
	fields := out["fields"].([]map[string]interface{})
	if len(fields) != 2 {
		t.Fatalf("Attendu 2 champs, reçu %d", len(fields))
	}
	if fields[0]["text"] != "casc-1" {
		t.Errorf("Attendu text=casc-1, reçu %v", fields[0]["text"])
	}
	// toOutgoing stocke la valeur varint en uint64 ; comparer via la forme texte
	// pour rester insensible au type numérique exact.
	if fmt.Sprint(fields[1]["value"]) != "190" {
		t.Errorf("Attendu value=190, reçu %v", fields[1]["value"])
	}
}

// pbTextFrame construit une frame protobuf length-delimited champ #2 avec du texte.
func pbTextFrame(s string) []byte {
	buf := make([]byte, 2+len(s))
	buf[0] = 0x12
	buf[1] = byte(len(s))
	copy(buf[2:], s)
	return buf
}

// fakeRPCClient est un stub du backend LanguageServer (gRPC-Web).
type fakeRPCClient struct {
	streamDeltas []string // frames émises par SendMessageStream
}

func (f *fakeRPCClient) Heartbeat() ([]byte, error) {
	return connectrpc.Frame(pbTextFrame("ok")), nil
}

func (f *fakeRPCClient) CreateCascade(uri string, model uint64) ([]byte, error) {
	return connectrpc.Frame(pbTextFrame("casc-1")), nil
}

func (f *fakeRPCClient) GetAllCascades() ([]byte, error) {
	return connectrpc.Frame(pbTextFrame("sess")), nil
}

func (f *fakeRPCClient) SendMessage(cascadeID, text string) ([]byte, error) {
	return connectrpc.Frame(pbTextFrame("ok")), nil
}

func (f *fakeRPCClient) SendMessageStream(cascadeID, text string, onFrame func([]byte) error) error {
	for _, delta := range f.streamDeltas {
		if err := onFrame(connectrpc.Frame(pbTextFrame(delta))); err != nil {
			return err
		}
	}
	return nil
}

func (f *fakeRPCClient) SubmitToolApproval(cascadeID, callID string, decision uint64) ([]byte, error) {
	return connectrpc.Frame(pbTextFrame("ok")), nil
}

// --- Tests WebSocket ---

type wsTestClient struct {
	conn *websocket.Conn
}

func dialWS(t *testing.T, url string) *wsTestClient {
	t.Helper()
	conn, _, err := websocket.DefaultDialer.Dial(url, nil)
	if err != nil {
		t.Fatalf("Dial WebSocket échoué: %v", err)
	}
	return &wsTestClient{conn: conn}
}

func (c *wsTestClient) send(t *testing.T, msg map[string]string) {
	t.Helper()
	b, _ := json.Marshal(msg)
	if err := c.conn.WriteMessage(websocket.TextMessage, b); err != nil {
		t.Fatalf("Envoi WebSocket échoué: %v", err)
	}
}

func (c *wsTestClient) recv(t *testing.T) map[string]interface{} {
	t.Helper()
	_, b, err := c.conn.ReadMessage()
	if err != nil {
		t.Fatalf("Réception WebSocket échouée: %v", err)
	}
	var out map[string]interface{}
	if err := json.Unmarshal(b, &out); err != nil {
		t.Fatalf("JSON invalide: %v (%s)", err, string(b))
	}
	return out
}

func newTestServer(client RPCClient) *httptest.Server {
	server := NewServer(client, "")
	mux := http.NewServeMux()
	mux.HandleFunc("/ws", server.HandleWebSocket)
	return httptest.NewServer(mux)
}

// TestWebSocketHeartbeat — cycle heartbeat complet via WebSocket.
func TestWebSocketHeartbeat(t *testing.T) {
	srv := newTestServer(&fakeRPCClient{})
	defer srv.Close()

	client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
	defer client.conn.Close()

	client.send(t, map[string]string{"type": "heartbeat", "requestId": "r1"})
	resp := client.recv(t)
	if resp["type"] != "response" || resp["requestId"] != "r1" {
		t.Fatalf("Réponse inattendue: %v", resp)
	}
	if resp["error"] != nil {
		t.Fatalf("Heartbeat a renvoyé une erreur: %v", resp["error"])
	}
}

// TestWebSocketSendPromptStream — test d'intégration du flux complet :
// stream_start → stream_delta (2 frames) → stream_end.
func TestWebSocketSendPromptStream(t *testing.T) {
	srv := newTestServer(&fakeRPCClient{streamDeltas: []string{"hello", " world"}})
	defer srv.Close()

	client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
	defer client.conn.Close()

	client.send(t, map[string]string{
		"type": "send_prompt", "requestId": "r9",
		"cascadeId": "casc-1", "prompt": "écris du code",
	})

	// 1. stream_start
	start := client.recv(t)
	if start["type"] != "stream_start" || start["requestId"] != "r9" {
		t.Fatalf("Attendu stream_start, reçu %v", start)
	}

	// 2. deux stream_delta
	gotDeltas := 0
	for gotDeltas < 2 {
		msg := client.recv(t)
		if msg["type"] == "stream_delta" {
			gotDeltas++
		} else if msg["type"] == "stream_end" {
			t.Fatalf("stream_end prématuré, deltas reçus: %d", gotDeltas)
		}
	}
	if gotDeltas != 2 {
		t.Fatalf("Attendu 2 stream_delta, reçu %d", gotDeltas)
	}

	// 3. stream_end
	end := client.recv(t)
	if end["type"] != "stream_end" || end["error"] != nil {
		t.Fatalf("Attendu stream_end sans erreur, reçu %v", end)
	}
}

// TestWebSocketSendPromptMissingFields — validation des champs requis.
func TestWebSocketSendPromptMissingFields(t *testing.T) {
	srv := newTestServer(&fakeRPCClient{})
	defer srv.Close()

	client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
	defer client.conn.Close()

	client.send(t, map[string]string{"type": "send_prompt", "requestId": "r2", "cascadeId": "casc-1"})
	resp := client.recv(t)
	if resp["error"] == nil {
		t.Fatalf("Attendu une erreur pour prompt manquant, reçu %v", resp)
	}
}

// TestWebSocketAuth — rejet des connexions sans token quand AuthToken est défini.
func TestWebSocketAuth(t *testing.T) {
	server := NewServer(&fakeRPCClient{}, "secret123")
	mux := http.NewServeMux()
	mux.HandleFunc("/ws", server.HandleWebSocket)
	srv := httptest.NewServer(mux)
	defer srv.Close()

	// Sans token → 401
	_, resp, err := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(srv.URL, "http")+"/ws", nil)
	if err == nil {
		resp.Body.Close()
		t.Fatal("Attendu une erreur de connexion sans token")
	}
	if resp != nil && resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("Attendu 401, reçu %d", resp.StatusCode)
	}

	// Avec token en query → connexion réussie
	conn, _, err := websocket.DefaultDialer.Dial(
		"ws"+strings.TrimPrefix(srv.URL, "http")+"/ws?token=secret123", nil)
	if err != nil {
		t.Fatalf("Connexion avec token valide échouée: %v", err)
	}
	conn.Close()
}

// TestWebSocketStreamBroadcastMultiClient — la synchronisation multi-surface :
// un stream déclenché par un client doit être diffusé à TOUS les clients
// connectés (équivalent Claude Code "work from 2 surfaces at once").
func TestWebSocketStreamBroadcastMultiClient(t *testing.T) {
	srv := newTestServer(&fakeRPCClient{streamDeltas: []string{"hello", " world"}})
	defer srv.Close()

	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http") + "/ws"
	emitter := dialWS(t, wsURL)
	defer emitter.conn.Close()
	observer := dialWS(t, wsURL)
	defer observer.conn.Close()

	// Le prompt est envoyé depuis le premier client seulement.
	emitter.send(t, map[string]string{
		"type": "send_prompt", "requestId": "r9",
		"cascadeId": "casc-1", "prompt": "écris du code",
	})

	for _, c := range []*wsTestClient{emitter, observer} {
		// 1. stream_start
		start := c.recv(t)
		if start["type"] != "stream_start" || start["requestId"] != "r9" {
			t.Fatalf("Attendu stream_start, reçu %v", start)
		}

		// 2. deux stream_delta
		gotDeltas := 0
		for gotDeltas < 2 {
			msg := c.recv(t)
			if msg["type"] == "stream_delta" {
				gotDeltas++
			} else if msg["type"] == "stream_end" {
				t.Fatalf("stream_end prématuré, deltas reçus: %d", gotDeltas)
			}
		}
		if gotDeltas != 2 {
			t.Fatalf("Attendu 2 stream_delta, reçu %d", gotDeltas)
		}

		// 3. stream_end
		end := c.recv(t)
		if end["type"] != "stream_end" || end["error"] != nil {
			t.Fatalf("Attendu stream_end sans erreur, reçu %v", end)
		}
	}
}
