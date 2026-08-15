package gateway

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gorilla/websocket"
)

// Trace les messages reçus par un client pendant la connexion : liste des
// types dans l'ordre — pour comprendre pourquoi recv() peut sauter un message.
func TestScratchTraceMessages(t *testing.T) {
	backend := &fakeRPCClient{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		server := NewServer(backend, "")
		server.HandleWebSocket(w, r)
	}))
	defer srv.Close()

	conn, _, err := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(srv.URL, "http")+"/ws", nil)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer conn.Close()

	// heartbeat + list_sessions + delete_cascade, puis on lit tout.
	msgs := []string{
		`{"type":"heartbeat","requestId":"t0"}`,
		`{"type":"list_sessions","requestId":"t1"}`,
		`{"type":"delete_cascade","requestId":"t2","cascadeId":"casc-9","confirm":true}`,
	}
	for _, m := range msgs {
		if err := conn.WriteMessage(websocket.TextMessage, []byte(m)); err != nil {
			t.Fatalf("send %s: %v", m, err)
		}
	}
	got := []string{}
	for i := 0; i < 8; i++ {
		_, b, err := conn.ReadMessage()
		if err != nil {
			t.Logf("read %d: err=%v", i, err)
			break
		}
		got = append(got, string(b))
		t.Logf("MSG[%d]: %s", i, string(b))
	}
	t.Logf("TOTAL received: %d", len(got))
}
