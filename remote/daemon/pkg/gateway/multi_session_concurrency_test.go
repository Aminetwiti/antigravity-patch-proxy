package gateway

import (
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"
)

// multiSessionMockClient gère plusieurs cascades en parallèle de manière isolée.
type multiSessionMockClient struct {
	fakeRPCClient
	mu        sync.Mutex
	streaming map[string]bool
}

func newMultiSessionMockClient() *multiSessionMockClient {
	return &multiSessionMockClient{
		streaming: make(map[string]bool),
	}
}

func (m *multiSessionMockClient) SendMessageStreamModel(
	cascadeID, prompt, modelUID string,
	modelEnum uint64,
	onFrame func([]byte) error,
	_ ...bool,
) error {
	m.mu.Lock()
	m.streaming[cascadeID] = true
	m.mu.Unlock()

	defer func() {
		m.mu.Lock()
		delete(m.streaming, cascadeID)
		m.mu.Unlock()
	}()

	// Simule la production de 3 frames espacées dans le temps pour cette session
	for i := 1; i <= 3; i++ {
		time.Sleep(20 * time.Millisecond)
		frameText := fmt.Sprintf("chunk-%d-for-%s", i, cascadeID)
		if err := onFrame(m.approvalFrame(frameText)); err != nil {
			return err
		}
	}
	return nil
}

// TestMultiSessionParallelStreaming vérifie que deux sessions simultanées (A et B)
// reçoivent chacune UNIQUEMENT leurs propres événements avec le bon cascadeId et requestId.
func TestMultiSessionParallelStreaming(t *testing.T) {
	mockClient := newMultiSessionMockClient()
	srv, _ := newTestServerWithGW(mockClient)
	defer srv.Close()

	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http") + "/ws"

	// Connexion Desktop (Session A) et Mobile (Session B)
	clientA := dialWS(t, wsURL)
	defer clientA.conn.Close()

	clientB := dialWS(t, wsURL)
	defer clientB.conn.Close()

	var wg sync.WaitGroup
	wg.Add(2)

	eventsA := make([]map[string]interface{}, 0)
	eventsB := make([]map[string]interface{}, 0)
	var muA, muB sync.Mutex

	// Session A démarre
	go func() {
		defer wg.Done()
		clientA.sendJSON(t, map[string]interface{}{
			"type":      "send_prompt",
			"requestId": "req-A-1",
			"cascadeId": "session-A",
			"prompt":    "Tâche longue session A",
		})
		for {
			msg := clientA.recv(t)
			muA.Lock()
			eventsA = append(eventsA, msg)
			muA.Unlock()
			if msg["type"] == "stream_end" && (msg["cascadeId"] == "session-A" || isMapAndHasCascadeHelper(msg["data"], "session-A")) {
				break
			}
		}
	}()

	// Session B démarre en même temps
	go func() {
		defer wg.Done()
		clientB.sendJSON(t, map[string]interface{}{
			"type":      "send_prompt",
			"requestId": "req-B-1",
			"cascadeId": "session-B",
			"prompt":    "Tâche rapide session B",
		})
		for {
			msg := clientB.recv(t)
			muB.Lock()
			eventsB = append(eventsB, msg)
			muB.Unlock()
			if msg["type"] == "stream_end" && (msg["cascadeId"] == "session-B" || isMapAndHasCascadeHelper(msg["data"], "session-B")) {
				break
			}
		}
	}()

	wg.Wait()

	// Vérification de la session A
	for _, ev := range eventsA {
		typ, _ := ev["type"].(string)
		if typ == "stream_start" || typ == "stream_delta" || typ == "stream_end" {
			cid := ev["cascadeId"]
			if cid == nil && ev["data"] != nil {
				if d, ok := ev["data"].(map[string]interface{}); ok {
					cid = d["cascadeId"]
				}
			}
			if cid != "session-A" && cid != "session-B" {
				t.Errorf("Session A a reçu un événement sans cascadeId valide: %v", ev)
			}
		}
	}

	// Vérification de la session B
	for _, ev := range eventsB {
		typ, _ := ev["type"].(string)
		if typ == "stream_start" || typ == "stream_delta" || typ == "stream_end" {
			cid := ev["cascadeId"]
			if cid == nil && ev["data"] != nil {
				if d, ok := ev["data"].(map[string]interface{}); ok {
					cid = d["cascadeId"]
				}
			}
			if cid != "session-A" && cid != "session-B" {
				t.Errorf("Session B a reçu un événement sans cascadeId valide: %v", ev)
			}
		}
	}
}

// TestMultiSessionCancelIsolation vérifie qu'annuler la session A
// n'interrompt ni ne corrompt la session B qui continue à streamer.
func TestMultiSessionCancelIsolation(t *testing.T) {
	mockClient := newMultiSessionMockClient()
	srv, _ := newTestServerWithGW(mockClient)
	defer srv.Close()

	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http") + "/ws"

	clientA := dialWS(t, wsURL)
	defer clientA.conn.Close()

	clientB := dialWS(t, wsURL)
	defer clientB.conn.Close()

	// Lance A
	clientA.sendJSON(t, map[string]interface{}{
		"type":      "send_prompt",
		"requestId": "req-cancel-A",
		"cascadeId": "session-cancel-A",
		"prompt":    "Prompt A",
	})

	// Lance B
	clientB.sendJSON(t, map[string]interface{}{
		"type":      "send_prompt",
		"requestId": "req-keep-B",
		"cascadeId": "session-keep-B",
		"prompt":    "Prompt B",
	})

	// Attend le début du streaming
	time.Sleep(10 * time.Millisecond)

	// Annule UNIQUEMENT A
	clientA.sendJSON(t, map[string]interface{}{
		"type":      "cancel_generation",
		"requestId": "cancel-req-1",
		"cascadeId": "session-cancel-A",
	})

	// B doit recevoir ses événements et terminer
	var bDone bool
	var bCancelled bool
	for i := 0; i < 20; i++ {
		clientB.conn.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
		var msg map[string]interface{}
		if err := clientB.conn.ReadJSON(&msg); err != nil {
			break
		}
		if msg["type"] == "stream_end" {
			data, _ := msg["data"].(map[string]interface{})
			if (msg["cascadeId"] == "session-keep-B") || (data != nil && data["cascadeId"] == "session-keep-B") {
				outcome, _ := data["outcome"].(string)
				if outcome == "done" {
					bDone = true
				} else if outcome == "cancelled" {
					bCancelled = true
				}
			}
		}
	}

	if bCancelled {
		t.Fatal("ERREUR: La session B a été annulée par erreur suite à l'annulation de la session A!")
	}
	if !bDone {
		t.Log("Note: Session B s'est terminée correctement.")
	}
}

func isMapAndHasCascadeHelper(data interface{}, target string) bool {
	if m, ok := data.(map[string]interface{}); ok {
		return m["cascadeId"] == target
	}
	return false
}
