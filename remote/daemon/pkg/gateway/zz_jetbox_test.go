package gateway

import (
	"strings"
	"sync"
	"testing"

	"github.com/antigravity/remote-daemon/pkg/connectrpc"
)

// fakeJetboxStreamer simule le stream JetboxSubscribeToSummaries : le test
// pousse des frames (updates/deletes) via push, exactement comme le ferait
// la goroutine RunJetboxSubscription. Les frames poussées avant l'installation
// du callback sont mises en file et rejouées (même comportement que le
// snapshot initial du vrai stream, qui peut précéder la connexion WS).
type fakeJetboxStreamer struct {
	mu      sync.Mutex
	onF     func(updates map[string]connectrpc.JetboxSummary, deletes []string)
	closed  chan struct{}
	pending []jetboxFrameCall
}

type jetboxFrameCall struct {
	updates map[string]connectrpc.JetboxSummary
	deletes []string
}

func newFakeJetboxStreamer() *fakeJetboxStreamer {
	return &fakeJetboxStreamer{closed: make(chan struct{})}
}

func (f *fakeJetboxStreamer) RunJetboxSubscription(onSummary func(updates map[string]connectrpc.JetboxSummary, deletes []string)) error {
	f.mu.Lock()
	f.onF = onSummary
	pending := f.pending
	f.pending = nil
	f.mu.Unlock()
	for _, c := range pending {
		onSummary(c.updates, c.deletes)
	}
	// Le vrai stream est long-vivant ; on bloque jusqu'à closeStream.
	<-f.closed
	return nil
}

func (f *fakeJetboxStreamer) closeStream() {
	select {
	case <-f.closed:
	default:
		close(f.closed)
	}
}

func (f *fakeJetboxStreamer) push(updates map[string]connectrpc.JetboxSummary, deletes []string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.onF != nil {
		f.onF(updates, deletes)
		return
	}
	f.pending = append(f.pending, jetboxFrameCall{updates: updates, deletes: deletes})
}

// TestJetboxFeedsListSessions — le stream Jetbox (snapshot initial) alimente
// list_sessions sans AUCUN appel GetAllCascades (~9,5 s) : le backend counting
// ne doit jamais être sollicité une fois la carte chaude.
func TestJetboxFeedsListSessions(t *testing.T) {
	backend := &countingCascadesClient{}
	ts, gw := newTestServerWithGW(backend)
	defer ts.Close()

	jetbox := newFakeJetboxStreamer()
	defer jetbox.closeStream()
	gw.RunJetboxSubscription(jetbox)

	// Snapshot initial du stream : une session.
	jetbox.push(map[string]connectrpc.JetboxSummary{
		"11111111-2222-3333-4444-555555555555": {
			CascadeID: "11111111-2222-3333-4444-555555555555",
			Title:     "session jetbox",
			Workspace: "file:///c:/work",
			ProjectID: "proj-a",
			Status:    "CASCADE_STATUS_READY",
		},
	}, nil)

	client := dialWS(t, "ws"+strings.TrimPrefix(ts.URL, "http")+"/ws")
	defer client.conn.Close()

	client.send(t, map[string]string{"type": "list_sessions", "requestId": "l1"})
	resp := client.recv(t)
	if resp["error"] != nil {
		t.Fatalf("list_sessions: %v", resp["error"])
	}
	data, _ := resp["data"].(map[string]interface{})
	sessions, _ := data["sessions"].([]interface{})
	if len(sessions) != 1 {
		t.Fatalf("attendu 1 session jetbox, reçu %d (%v)", len(sessions), sessions)
	}
	first := sessions[0].(map[string]interface{})
	if first["cascadeId"] != "11111111-2222-3333-4444-555555555555" || first["title"] != "session jetbox" {
		t.Fatalf("session inattendue: %v", first)
	}
	// La source de vérité est le stream : GetAllCascades ne doit JAMAIS
	// avoir été appelé (0 appel = latence 9,5 s éliminée).
	if calls := backend.callCount(); calls != 0 {
		t.Fatalf("GetAllCascades appelé %d fois alors que jetbox est chaud", calls)
	}
}

// TestJetboxSyncBroadcasts — chaque frame du stream (updates/deletes) est
// broadcastée en sessions_updated à tous les clients connectés.
func TestJetboxSyncBroadcasts(t *testing.T) {
	ts, gw := newTestServerWithGW(&fakeRPCClient{})
	defer ts.Close()

	jetbox := newFakeJetboxStreamer()
	defer jetbox.closeStream()
	gw.RunJetboxSubscription(jetbox)

	client := dialWS(t, "ws"+strings.TrimPrefix(ts.URL, "http")+"/ws")
	defer client.conn.Close()

	jetbox.push(map[string]connectrpc.JetboxSummary{
		"casc-1": {CascadeID: "casc-1", Title: "nouvelle session", Status: "CASCADE_STATUS_READY"},
		"casc-2": {CascadeID: "casc-2", Title: "seconde session", Status: "CASCADE_STATUS_READY"},
	}, nil)

	msg := client.recv(t)
	if msg["type"] != "sessions_updated" {
		t.Fatalf("attendu sessions_updated, reçu %v", msg)
	}
	data, _ := msg["data"].(map[string]interface{})
	sessions, _ := data["sessions"].([]interface{})
	if len(sessions) != 2 {
		t.Fatalf("attendu 2 sessions dans le broadcast, reçu %v", data)
	}

	// Suppression : la session supprimée disparaît du broadcast suivant
	// (celle qui reste est conservée).
	jetbox.push(nil, []string{"casc-1"})
	msg = client.recv(t)
	if msg["type"] != "sessions_updated" {
		t.Fatalf("attendu sessions_updated (delete), reçu %v", msg)
	}
	data, _ = msg["data"].(map[string]interface{})
	sessions, _ = data["sessions"].([]interface{})
	if len(sessions) != 1 {
		t.Fatalf("attendu 1 session après delete, reçu %v", data)
	}
	first := sessions[0].(map[string]interface{})
	if first["cascadeId"] != "casc-2" {
		t.Fatalf("session restante inattendue: %v", first)
	}
}
