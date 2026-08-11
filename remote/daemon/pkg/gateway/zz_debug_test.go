package gateway

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

// TestDebugApprovalFlow — debug temporaire : imprime tout ce que le client
// reçoit après submit_approval puis send_prompt.
func TestDebugApprovalFlow(t *testing.T) {
	fake := &fakeApprovalRPC{}
	fake.streamDeltas = []string{`{"run_command":"npx jest","step_index":1,"trajectory_id":"123e4567-e89b-12d3-a456-426614174000"}`}
	srv := newTestServer(fake)
	defer srv.Close()

	client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
	defer client.conn.Close()

	// 1. submit_approval scope=session
	if err := client.conn.WriteMessage(websocket.TextMessage, []byte(`{"type":"submit_approval","requestId":"a1","cascadeId":"casc-1","callId":"call-1","trajectoryId":"123e4567-e89b-12d3-a456-426614174000","stepIndex":0,"approvalType":"run_command","decision":"allow","scope":"session"}`)); err != nil {
		t.Fatalf("write submit_approval: %v", err)
	}
	got := readAllFull(client.conn, 1*time.Second)
	t.Logf("après submit_approval: %s", got)

	// 2. heartbeat pour vérifier que la connexion est encore vivante
	if err := client.conn.WriteMessage(websocket.TextMessage, []byte(`{"type":"heartbeat","requestId":"hb"}`)); err != nil {
		t.Fatalf("write heartbeat: %v", err)
	}
	got2 := readAllFull(client.conn, 1*time.Second)
	t.Logf("après heartbeat: %s", got2)

	// 3. send_prompt
	if err := client.conn.WriteMessage(websocket.TextMessage, []byte(`{"type":"send_prompt","requestId":"r2","cascadeId":"casc-1","prompt":"fais qqch"}`)); err != nil {
		t.Fatalf("write send_prompt: %v", err)
	}
	got3 := readAllFull(client.conn, 2*time.Second)
	t.Logf("après send_prompt: %s", got3)
	t.Logf("submitted=%d", fake.submitted)
}

func readAllFull(conn *websocket.Conn, d time.Duration) string {
	conn.SetReadDeadline(time.Now().Add(d))
	defer conn.SetReadDeadline(time.Time{})
	var out []string
	for {
		_, b, err := conn.ReadMessage()
		if err != nil {
			if out == nil {
				out = append(out, "ERR:"+err.Error())
			}
			break
		}
		var m map[string]interface{}
		if json.Unmarshal(b, &m) == nil {
			out = append(out, m["type"].(string))
		} else {
			out = append(out, "NON-JSON:"+string(b))
		}
	}
	return strings.Join(out, ", ")
}
