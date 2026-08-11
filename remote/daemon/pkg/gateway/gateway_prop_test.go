package gateway

import (
	"fmt"
	"math/rand"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/antigravity/remote-daemon/pkg/connectrpc"
	"github.com/gorilla/websocket"
)

// ─── Test de robustesse : malformed / types invalides ───

// TestWebSocketMalformedJSON — un JSON invalide ne doit pas couper la connexion,
// mais répondre "error" puis rester utilisable.
func TestWebSocketMalformedJSON(t *testing.T) {
	srv := newTestServer(&fakeRPCClient{})
	defer srv.Close()

	client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
	defer client.conn.Close()

	// Envoie des octets non-JSON.
	if err := client.conn.WriteMessage(websocket.TextMessage, []byte("{not json")); err != nil {
		t.Fatalf("Envoi malformed échoué: %v", err)
	}
	resp := client.recv(t)
	if resp["type"] != "error" {
		t.Fatalf("Attendu un message d'erreur, reçu %v", resp)
	}

	// La connexion doit rester vivante : heartbeat fonctionne encore.
	client.send(t, map[string]string{"type": "heartbeat", "requestId": "r2"})
	if resp := client.recv(t); resp["type"] != "response" {
		t.Fatalf("Heartbeat après malformed a échoué: %v", resp)
	}
}

// TestWebSocketUnknownAction — un type d'action inconnu renvoie une erreur
// mais ne coupe pas la connexion.
func TestWebSocketUnknownAction(t *testing.T) {
	srv := newTestServer(&fakeRPCClient{})
	defer srv.Close()

	client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
	defer client.conn.Close()

	client.send(t, map[string]string{"type": "fly_to_moon", "requestId": "rX"})
	resp := client.recv(t)
	if resp["type"] != "error" || resp["error"] == nil {
		t.Fatalf("Attendu erreur Unknown action, reçu %v", resp)
	}
}

// TestWebSocketCreateCascadeRequiresWorkspace — create_cascade sans workspace
// renvoie une erreur propre.
func TestWebSocketCreateCascadeRequiresWorkspace(t *testing.T) {
	srv := newTestServer(&fakeRPCClient{})
	defer srv.Close()

	client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
	defer client.conn.Close()

	client.send(t, map[string]string{"type": "create_cascade", "requestId": "rC"})
	resp := client.recv(t)
	if resp["error"] == nil {
		t.Fatalf("Attendu une erreur workspace manquant, reçu %v", resp)
	}
}

// ─── Test de concurrence : N clients simultanés ───

type loadRPCClient struct {
	heartbeats atomic.Int64
}

func (l *loadRPCClient) Heartbeat() ([]byte, error) {
	l.heartbeats.Add(1)
	return connectrpc.Frame(pbTextFrame("ok")), nil
}
func (l *loadRPCClient) CreateCascade(uri string, model uint64) ([]byte, error) {
	return connectrpc.Frame(pbTextFrame("casc-1")), nil
}
func (l *loadRPCClient) GetAllCascades() ([]byte, error) {
	return connectrpc.Frame(pbTextFrame("sess")), nil
}
func (l *loadRPCClient) SendMessageStream(cascadeID, text string, onFrame func([]byte) error) error {
	return onFrame(connectrpc.Frame(pbTextFrame("ok")))
}
func (l *loadRPCClient) SubmitToolApproval(cascadeID, callID string, decision uint64) ([]byte, error) {
	return connectrpc.Frame(pbTextFrame("ok")), nil
}

// TestWebSocketConcurrentClients — 20 clients en parallèle, 30 messages chacun :
// aucun message ne doit être perdu ni mélangé (chaque réponse doit porter
// son requestId).
func TestWebSocketConcurrentClients(t *testing.T) {
	if testing.Short() {
		t.Skip("test de charge, sauté en mode -short")
	}
	backend := &loadRPCClient{}
	srv := newTestServer(backend)
	defer srv.Close()

	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http") + "/ws"
	const clients = 20
	const perClient = 30

	var wg sync.WaitGroup
	errCh := make(chan error, clients)
	for c := 0; c < clients; c++ {
		wg.Add(1)
		go func(c int) {
			defer wg.Done()
			conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
			if err != nil {
				errCh <- fmt.Errorf("client %d: dial: %w", c, err)
				return
			}
			defer conn.Close()

			for i := 0; i < perClient; i++ {
				rid := fmt.Sprintf("r-%d-%d", c, i)
				if err := conn.WriteJSON(map[string]string{"type": "heartbeat", "requestId": rid}); err != nil {
					errCh <- fmt.Errorf("client %d msg %d: send: %w", c, i, err)
					return
				}
				var out map[string]interface{}
				if err := conn.ReadJSON(&out); err != nil {
					errCh <- fmt.Errorf("client %d msg %d: recv: %w", c, i, err)
					return
				}
				if out["requestId"] != rid || out["type"] != "response" {
					errCh <- fmt.Errorf("client %d msg %d: réponse croisée! reçu requestId=%v", c, i, out["requestId"])
					return
				}
			}
		}(c)
	}
	wg.Wait()
	close(errCh)
	for err := range errCh {
		t.Error(err)
	}
	if got := backend.heartbeats.Load(); got != clients*perClient {
		t.Fatalf("Attendu %d heartbeats backend, reçu %d", clients*perClient, got)
	}
}

// ─── Test de robustesse : payloads aléatoires (proto random walk) ───

// toOutgoing ne doit jamais paniquer, quelle que soit l'entrée binaire.
func TestToOutgoingNeverPanics(t *testing.T) {
	r := rand.New(rand.NewSource(42))
	for i := 0; i < 2000; i++ {
		raw := make([]byte, r.Intn(128))
		r.Read(raw)
		func() {
			defer func() {
				if p := recover(); p != nil {
					t.Fatalf("toOutgoing a paniqué sur %v: %v", raw, p)
				}
			}()
			_ = toOutgoing(raw)
		}()
	}
}

// TestWorkspaceURIRoundTrip — un chemin Windows → URI → même chemin.
func TestWorkspaceURIRoundTrip(t *testing.T) {
	uri := toWorkspaceURI(`C:\Users\amine\Downloads\projet`)
	if uri != "file:///C:/Users/amine/Downloads/projet" {
		t.Fatalf("URI inattendue: %s", uri)
	}
}

// ─── Test de charge : débit maximal du gateway WebSocket ───

// BenchmarkGatewayHeartbeat mesure le débit d'un cycle heartbeat complet
// (aller-retour WebSocket + décodage protobuf côté serveur).
func BenchmarkGatewayHeartbeat(b *testing.B) {
	backend := &loadRPCClient{}
	srv := newTestServer(backend)
	defer srv.Close()

	conn, _, err := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(srv.URL, "http")+"/ws", nil)
	if err != nil {
		b.Fatalf("dial: %v", err)
	}
	defer conn.Close()

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		rid := fmt.Sprintf("r-%d", i)
		if err := conn.WriteJSON(map[string]string{"type": "heartbeat", "requestId": rid}); err != nil {
			b.Fatal(err)
		}
		var out map[string]interface{}
		if err := conn.ReadJSON(&out); err != nil {
			b.Fatal(err)
		}
		if out["requestId"] != rid {
			b.Fatalf("réponse croisée: %v", out["requestId"])
		}
	}
}

// TestWebSocketStreamBackpressure — quand onFrame renvoie une erreur,
// le gateway doit propager stream_end avec erreur et terminer proprement.
type failingStreamClient struct{}

func (f *failingStreamClient) Heartbeat() ([]byte, error) { return connectrpc.Frame(pbTextFrame("ok")), nil }
func (f *failingStreamClient) CreateCascade(uri string, model uint64) ([]byte, error) {
	return connectrpc.Frame(pbTextFrame("casc")), nil
}
func (f *failingStreamClient) GetAllCascades() ([]byte, error) { return connectrpc.Frame(pbTextFrame("s")), nil }
func (f *failingStreamClient) SendMessageStream(cascadeID, text string, onFrame func([]byte) error) error {
	_ = onFrame(connectrpc.Frame(pbTextFrame("hello")))
	return fmt.Errorf("stream interrompu par le backend")
}
func (f *failingStreamClient) SubmitToolApproval(cascadeID, callID string, decision uint64) ([]byte, error) {
	return connectrpc.Frame(pbTextFrame("ok")), nil
}

func TestWebSocketStreamBackendError(t *testing.T) {
	srv := newTestServer(&failingStreamClient{})
	defer srv.Close()

	client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
	defer client.conn.Close()

	client.send(t, map[string]string{
		"type": "send_prompt", "requestId": "rE",
		"cascadeId": "casc-1", "prompt": "provoque une erreur",
	})

	// stream_start puis stream_end avec erreur (le delta peut arriver avant).
	gotStart, gotEnd := false, false
	deadline := time.Now().Add(5 * time.Second)
	for !gotEnd && time.Now().Before(deadline) {
		msg := client.recv(t)
		switch msg["type"] {
		case "stream_start":
			gotStart = true
		case "stream_delta":
			// OK, toléré
		case "stream_end":
			if msg["error"] == nil {
				t.Fatalf("Attendu stream_end avec erreur, reçu %v", msg)
			}
			gotEnd = true
		}
	}
	if !gotStart || !gotEnd {
		t.Fatalf("Flux incomplet: start=%v end=%v", gotStart, gotEnd)
	}
}
