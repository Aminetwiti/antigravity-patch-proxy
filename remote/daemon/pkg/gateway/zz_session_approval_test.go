package gateway

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/antigravity/remote-daemon/pkg/connectrpc"
	"github.com/gorilla/websocket"
)

// fakeApprovalRPC étend fakeRPCClient pour compter les soumissions
// SubmitToolApproval (auto-approbation B3).
type fakeApprovalRPC struct {
	fakeRPCClient
	submitted int
	lastTool  string
}

func (f *fakeApprovalRPC) SubmitToolApproval(cascadeID, trajectoryID string, stepIndex uint32, oneofField int, oneofPayload []byte) ([]byte, error) {
	f.submitted++
	return connectrpc.Frame(pbTextFrame("ok")), nil
}

// approvalEventFrame construit une frame protobuf dont ParseFrameEvents
// extrait un événement EventKindApprovalRequired. Le blob contient le texte
// « run_command » (détection du parseur) ET un UUID de 36 octets (corrélation
// trajectoryId pour l'auto-approbation SubmitToolApproval).
func approvalEventFrame(tool string) []byte {
	blob := tool + " 123e4567-e89b-12d3-a456-426614174000"
	buf := make([]byte, 2+len(blob))
	buf[0] = 0x0a // champ #1 length-delimited (test event_parser)
	buf[1] = byte(len(blob))
	copy(buf[2:], blob)
	return connectrpc.Frame(buf)
}

// TestSessionApprovalAutoApproves vérifie le comportement B3 :
// après un « scope=session » (toujours autoriser), une demande
// d'approbation du même type est auto-approuvée sans passer par le client.
func TestSessionApprovalAutoApproves(t *testing.T) {
	fake := &fakeApprovalRPC{}
	// Même format que TestWebSocketStreamEndOutcome : le fake enveloppe la
	// frame dans pbTextFrame, et ParseFrameEvents y détecte run_command + UUID.
	fake.streamDeltas = []string{`{"run_command":"npx jest","step_index":1,"trajectory_id":"123e4567-e89b-12d3-a456-426614174000"}`}
	srv := newTestServer(fake)
	defer srv.Close()

	client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
	defer client.conn.Close()

	// 1. L'utilisateur choisit « toujours autoriser run_command pour la session ».
	if err := client.conn.WriteMessage(websocket.TextMessage, []byte(`{"type":"submit_approval","requestId":"a1","cascadeId":"casc-1","callId":"call-1","trajectoryId":"123e4567-e89b-12d3-a456-426614174000","stepIndex":0,"approvalType":"run_command","decision":"allow","scope":"session"}`)); err != nil {
		t.Fatalf("envoi submit_approval: %v", err)
	}
	// Traiter le message : drainer la réponse éventuelle.
	client.conn.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
	drain(t, client.conn)

	// 2. Un nouveau prompt émet une demande d'approbation run_command :
	//    elle doit être auto-approuvée (submitted == 1) et le stream doit
	//    se terminer en « done » (aucune approbation laissée en attente).
	// Laisser le daemon traiter submit_approval (marquage session) avant le
	// second prompt : la dispatch WebSocket est asynchrone côté serveur.
	time.Sleep(200 * time.Millisecond)

	if err := client.conn.WriteMessage(websocket.TextMessage, []byte(`{"type":"send_prompt","requestId":"r2","cascadeId":"casc-1","prompt":"fais qqch"}`)); err != nil {
		t.Fatalf("envoi send_prompt: %v", err)
	}

	var last map[string]interface{}
	client.conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	for {
		_, b, err := client.conn.ReadMessage()
		if err != nil {
			t.Fatalf("lecture stream: %v", err)
		}
		var m map[string]interface{}
		if err := json.Unmarshal(b, &m); err != nil {
			continue
		}
		last = m
		if m["type"] == "stream_end" {
			break
		}
	}
	outcome, _ := last["data"].(map[string]interface{})["outcome"].(string)
	if outcome != "done" {
		t.Fatalf("outcome = %q, attendu \"done\" (auto-approbation)", outcome)
	}
	if fake.submitted != 1 {
		t.Fatalf("SubmitToolApproval appelé %d fois, attendu 1 (auto-approbation)", fake.submitted)
	}
}

// TestSessionApprovalOnceNeedsClient vérifie qu'un scope « once » ne
// déclenche PAS d'auto-approbation : la demande reste visible du client.
func TestSessionApprovalOnceNeedsClient(t *testing.T) {
	fake := &fakeApprovalRPC{}
	fake.streamDeltas = []string{`{"run_command":"npx jest","step_index":1,"trajectory_id":"123e4567-e89b-12d3-a456-426614174000"}`}
	srv := newTestServer(fake)
	defer srv.Close()

	client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
	defer client.conn.Close()

	if err := client.conn.WriteMessage(websocket.TextMessage, []byte(`{"type":"send_prompt","requestId":"r1","cascadeId":"casc-2","prompt":"fais qqch"}`)); err != nil {
		t.Fatalf("envoi send_prompt: %v", err)
	}

	var sawApproval bool
	for {
		_, b, err := client.conn.ReadMessage()
		if err != nil {
			t.Fatalf("lecture stream: %v", err)
		}
		var m map[string]interface{}
		if err := json.Unmarshal(b, &m); err != nil {
			continue
		}
		if m["type"] == "stream_delta" {
			if d, ok := m["data"].(map[string]interface{}); ok {
				if evs, ok := d["events"].([]interface{}); ok && len(evs) > 0 {
					sawApproval = true
				}
			}
		}
		if m["type"] == "stream_end" {
			break
		}
	}
	if fake.submitted != 0 {
		t.Fatalf("SubmitToolApproval appelé %d fois, attendu 0 (scope once)", fake.submitted)
	}
	if !sawApproval {
		t.Fatal("aucun événement d'approbation diffusé au client (scope once)")
	}
}

func drain(t *testing.T, conn *websocket.Conn) {
	t.Helper()
	conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	for {
		_, _, err := conn.ReadMessage()
		if err != nil {
			break
		}
	}
	// Ne pas laisser la deadline active : les lectures suivantes du test
	// (stream_end du prompt) bloqueraient sinon pendant 2 s puis timeout.
	conn.SetReadDeadline(time.Time{})
}
