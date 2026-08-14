package gateway

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

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
	cascadesRaw  []byte   // réponse GetAllCascades (nil → défaut)
	// lastApproval : dernier SubmitToolApproval reçu (vérifié par les tests
	// d'approbation : décision utilisateur ou auto-refus d'expiration).
	lastApproval interface{}
	// lastCommand : dernière slash commande routée (vérifié par le test
	// de routing send_command).
	lastCommand string
	// lastCascade : dernier CreateCascade reçu (vérifié par le test de
	// propagation du modèle mobile).
	lastCascade *createCascadeCall
	// lastDelete : dernier DeleteCascade reçu (vérifié par le test P0).
	lastDelete string
	// lastRead / lastWrite : derniers ReadFile / WriteFile reçus (tests P0).
	lastRead  string
	lastWrite *writeFileCall
	// modelsRaw : réponse ListModels (nil → défaut "ok").
	modelsRaw []byte
	// deleteErr : erreur simulée pour DeleteCascade (tests de refus).
	deleteErr error
	// trajectoryRaw / turnDiffRaw : réponses des RPC C9 (nil → défaut).
	trajectoryRaw []byte
	turnDiffRaw   []byte
	// lastTrajectory / lastTurnDiff : derniers appels C9 reçus (vérifiés
	// par zz_p1_trajectory_test.go).
	lastTrajectory *trajectoryCall
	lastTurnDiff   *turnDiffCall
}

// trajectoryCall capture les arguments du dernier GetCascadeTrajectory.
type trajectoryCall struct {
	cascadeID string
	verbosity uint64
}

// turnDiffCall capture les arguments du dernier GetTurnDiff.
type turnDiffCall struct {
	conversationID string
	stepIndex      int64
}

// writeFileCall capture les arguments du dernier WriteFile.
type writeFileCall struct {
	uri       string
	content   []byte
	overwrite bool
}

// createCascadeCall capture les arguments du dernier CreateCascade pour
// vérifier la propagation modelUID/modelEnum du mobile jusqu'au RPC.
type createCascadeCall struct {
	uri       string
	projectID string
	modelUID  string
	modelEnum uint64
}

func (f *fakeRPCClient) Heartbeat() ([]byte, error) {
	return connectrpc.Frame(pbTextFrame("ok")), nil
}

func (f *fakeRPCClient) CreateCascade(uri string, projectID string, modelUID string, modelEnum uint64) ([]byte, error) {
	f.lastCascade = &createCascadeCall{uri: uri, projectID: projectID, modelUID: modelUID, modelEnum: modelEnum}
	return connectrpc.Frame(pbTextFrame("casc-1")), nil
}

func (f *fakeRPCClient) GetAllCascades() ([]byte, error) {
	if f.cascadesRaw != nil {
		return f.cascadesRaw, nil
	}
	return connectrpc.Frame(pbTextFrame("sess")), nil
}

func (f *fakeRPCClient) SendMessage(cascadeID, text string) ([]byte, error) {
	return connectrpc.Frame(pbTextFrame("ok")), nil
}

func (f *fakeRPCClient) SendMessageStream(cascadeID, text string, onFrame func([]byte) error) error {
	return f.streamLoop(onFrame)
}

// SendMessageStreamModel : la sélection modèle du mobile est ignorée par le
// fake (le contrat testé est le streaming) - mêmes deltas que la variante.
func (f *fakeRPCClient) SendMessageStreamModel(cascadeID, text, modelUID string, modelEnum uint64, onFrame func([]byte) error) error {
	return f.streamLoop(onFrame)
}

func (f *fakeRPCClient) streamLoop(onFrame func([]byte) error) error {
	for _, delta := range f.streamDeltas {
		if err := onFrame(f.approvalFrame(delta)); err != nil {
			return err
		}
	}
	return nil
}

// approvalFrame construit une frame protobuf identique à celle du vrai
// Language Server pour un événement d'approbation : un champ #1 length-delimited
// contenant les sous-champs de corrélation trajectory_id (#1) + step_index (#2)
// PUIS le blob JSON (run_command, …) (#3). Le parseur (event_parser.go) cherche
// le texte "run_command" et les sous-champs de corrélation DANS LE MÊME champ —
// c'est ainsi qu'il retrouve la cible de HandleCascadeUserInteraction.
func (f *fakeRPCClient) approvalFrame(delta string) []byte {
	blob := &protoWriter{}
	blob.string(1, "123e4567-e89b-12d3-a456-426614174000") // trajectory_id
	blob.varint(2, 1)                                      // step_index
	blob.bytes(3, []byte(delta))                           // blob JSON
	outer := &protoWriter{}
	outer.bytes(1, blob.buf)
	// Le vrai CallStream/splitFrames retire l'en-tête gRPC-Web (5 octets)
	// avant d'invoquer onFrame : le fake doit imiter ce contrat, sinon
	// ParseFrameEvents décode l'en-tête comme des champs fantômes et avale
	// le message (run_command jamais détecté → outcome=done).
	return outer.buf
}

// protoWriter : encodeur protobuf de test calqué sur connectrpc/writer
// (mêmes conventions de clé/varint/length-delimited) — sans dépendance.
type protoWriter struct {
	buf []byte
}

func (w *protoWriter) rawVarint(v uint64) {
	for v >= 0x80 {
		w.buf = append(w.buf, byte(v)|0x80)
		v >>= 7
	}
	w.buf = append(w.buf, byte(v))
}

func (w *protoWriter) key(n, wireType int) {
	w.rawVarint(uint64(n<<3 | wireType))
}

func (w *protoWriter) varint(n int, v uint64) {
	w.key(n, 0)
	w.rawVarint(v)
}

func (w *protoWriter) string(n int, s string) {
	w.bytes(n, []byte(s))
}

func (w *protoWriter) bytes(n int, b []byte) {
	w.key(n, 2)
	w.rawVarint(uint64(len(b)))
	w.buf = append(w.buf, b...)
}

func (f *fakeRPCClient) SubmitToolApproval(cascadeID, trajectoryID string, stepIndex uint32, oneofField int, oneofPayload []byte) ([]byte, error) {
	f.lastApproval = &submitApprovalCall{
		cascadeID:    cascadeID,
		trajectoryID: trajectoryID,
		stepIndex:    stepIndex,
		confirm:      connectrpc.DecodeFields(oneofPayload)[0].Varint == 1,
	}
	return connectrpc.Frame(pbTextFrame("ok")), nil
}

func (f *fakeRPCClient) SetBrowserOpenConversation(cascadeID string) ([]byte, error) {
	return connectrpc.Frame(pbTextFrame("ok")), nil
}

func (f *fakeRPCClient) SendCommand(commandText string) ([]byte, error) {
	f.lastCommand = commandText
	return connectrpc.Frame(pbTextFrame("cmd-ok")), nil
}

func (f *fakeRPCClient) ListModels() ([]byte, error) {
	if f.modelsRaw != nil {
		return f.modelsRaw, nil
	}
	return connectrpc.Frame(pbTextFrame("ok")), nil
}

func (f *fakeRPCClient) DeleteCascade(cascadeID string) ([]byte, error) {
	f.lastDelete = cascadeID
	if f.deleteErr != nil {
		return nil, f.deleteErr
	}
	return connectrpc.Frame(pbTextFrame("deleted")), nil
}

func (f *fakeRPCClient) ReadFile(uri string) ([]byte, error) {
	f.lastRead = uri
	return connectrpc.Frame(pbTextFrame("file-content")), nil
}

func (f *fakeRPCClient) WriteFile(uri string, content []byte, overwrite bool) ([]byte, error) {
	f.lastWrite = &writeFileCall{uri: uri, content: content, overwrite: overwrite}
	return connectrpc.Frame(pbTextFrame("written")), nil
}

func (f *fakeRPCClient) GetCascadeTrajectory(cascadeID string, verbosity uint64) ([]byte, error) {
	f.lastTrajectory = &trajectoryCall{cascadeID: cascadeID, verbosity: verbosity}
	if f.trajectoryRaw != nil {
		return f.trajectoryRaw, nil
	}
	return connectrpc.Frame(pbTextFrame("traj")), nil
}

func (f *fakeRPCClient) GetTurnDiff(conversationID string, stepIndex int64) ([]byte, error) {
	f.lastTurnDiff = &turnDiffCall{conversationID: conversationID, stepIndex: stepIndex}
	if f.turnDiffRaw != nil {
		return f.turnDiffRaw, nil
	}
	return connectrpc.Frame(pbTextFrame("diff")), nil
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

// sendRaw envoie un message JSON brut (champs data, nombres, …) sans passer
// par le typage map[string]string de send.
func (c *wsTestClient) sendRaw(t *testing.T, raw string) {
	t.Helper()
	if err := c.conn.WriteMessage(websocket.TextMessage, []byte(raw)); err != nil {
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

// TestWebSocketStreamEndOutcome — le daemon enrichit stream_end d'un
// outcome structuré : "done" en succès, "approval" quand une frame a porté
// une demande d'approbation, "error" quand le backend échoue. Le mobile
// s'en sert pour notifier la fin de tâche (task done / action requise).
func TestWebSocketStreamEndOutcome(t *testing.T) {
	t.Run("success => done", func(t *testing.T) {
		srv := newTestServer(&fakeRPCClient{streamDeltas: []string{"ok"}})
		defer srv.Close()
		client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
		defer client.conn.Close()
		client.send(t, map[string]string{
			"type": "send_prompt", "requestId": "r9",
			"cascadeId": "casc-1", "prompt": "travaille",
		})
		for {
			msg := client.recv(t)
			if msg["type"] != "stream_end" {
				continue
			}
			data, _ := msg["data"].(map[string]interface{})
			if data == nil || data["outcome"] != "done" {
				t.Fatalf("Attendu outcome=done, reçu %v", msg)
			}
			return
		}
	})

	t.Run("approval frame => approval", func(t *testing.T) {
		// La frame porte run_command → ParseFrameEvents émet
		// EventKindApprovalRequired → le gateway classe stream_end "approval".
		srv := newTestServer(&fakeRPCClient{streamDeltas: []string{`{"run_command":"npx jest","step_index":1,"trajectory_id":"123e4567-e89b-12d3-a456-426614174000"}`}})
		defer srv.Close()
		client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
		defer client.conn.Close()
		client.send(t, map[string]string{
			"type": "send_prompt", "requestId": "r9",
			"cascadeId": "casc-1", "prompt": "travaille",
		})
		for {
			msg := client.recv(t)
			if msg["type"] != "stream_end" {
				continue
			}
			data, _ := msg["data"].(map[string]interface{})
			if data == nil || data["outcome"] != "approval" {
				t.Fatalf("Attendu outcome=approval (frame run_command), reçu %v", msg)
			}
			return
		}
	})
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

// TestWebSocketReadLimit — un message > 1 Mo doit être rejeté sans crash :
// le serveur ferme la connexion, le client reçoit une erreur de lecture.
func TestWebSocketReadLimit(t *testing.T) {
	srv := newTestServer(&fakeRPCClient{})
	defer srv.Close()

	client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
	defer client.conn.Close()

	big := strings.Repeat("A", maxWSMessageSize+1024)
	if err := client.conn.WriteMessage(websocket.TextMessage, []byte(big)); err != nil {
		t.Fatalf("envoi du gros message échoué: %v", err)
	}

	// La prochaine lecture doit échouer (connexion fermée par le serveur).
	_, _, err := client.conn.ReadMessage()
	if err == nil {
		t.Fatal("Attendu une erreur de lecture après dépassement du read limit")
	}
}

// TestWebSocketCheckOrigin — un navigateur web avec un Origin arbitraire
// doit être rejeté (CSWSH), tandis qu'un client natif sans Origin passe.
func TestWebSocketCheckOrigin(t *testing.T) {
	srv := newTestServer(&fakeRPCClient{})
	defer srv.Close()
	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http") + "/ws"

	// Origin malveillant → refusé
	_, resp, err := websocket.DefaultDialer.Dial(wsURL, http.Header{"Origin": []string{"https://evil.example.com"}})
	if err == nil {
		resp.Body.Close()
		t.Fatal("Attendu un rejet pour Origin malveillant")
	}

	// Origin localhost → accepté
	conn, _, err := websocket.DefaultDialer.Dial(wsURL, http.Header{"Origin": []string{"http://localhost:3000"}})
	if err != nil {
		t.Fatalf("Origin localhost refusé à tort: %v", err)
	}
	conn.Close()
}

// trajectoryFrame construit une réponse GetAllCascadeTrajectories contenant
// UNE trajectoire structurée (champ 1 : cascade_id UUID de 36 octets + status).
func trajectoryFrame(uuid string) []byte {
	inner := append([]byte{0x0a, 0x24}, []byte(uuid)...) // field 1: cascade_id
	inner = append(inner, 0xb0, 0x01, 0x04)              // field 22: varint 4 (READY)
	outer := append([]byte{0x0a, byte(len(inner))}, inner...)
	return connectrpc.Frame(outer)
}

// TestWebSocketGetContextReal — get_context compte les artefacts réels depuis
// la réponse GetAllCascadeTrajectories (plus de mock en dur).
func TestWebSocketGetContextReal(t *testing.T) {
	// Cascade de test isolée : un ID UUID (36 octets) est requis —
	// trajectoryFrame encode cascade_id avec une longueur fixe de 36 et
	// uuidRe conditionne le parsing structuré. Un ID unique évite aussi de
	// collisionner avec une vraie session utilisateur.
	n := time.Now().UnixNano()
	cascadeID := fmt.Sprintf("%08x-%04x-%04x-%04x-%012x", uint32(n), uint16(n>>32), uint16(n>>48), uint16(n>>16), uint64(n)&0xFFFFFFFFFFFF)
	home, err := os.UserHomeDir()
	if err != nil {
		t.Fatal(err)
	}
	transcriptDir := filepath.Join(home, ".gemini", "antigravity-ide", "brain", cascadeID, ".system_generated", "logs")
	if err := os.MkdirAll(transcriptDir, 0o755); err != nil {
		t.Fatal(err)
	}
	// filePathsIn n'extrait que les chemins C:/… ou file:///C:/… (slashs
	// avant) — filepath.Join produit des backslashes sur Windows, donc on
	// convertit explicitement.
	artifactPath := "file:///" + filepath.ToSlash(filepath.Join(home, ".gemini", "antigravity-ide", "brain", cascadeID, "artifact_1.md"))
	line := fmt.Sprintf(`{"type":"CODE_ACTION","content":"Created file %s with requested content."}`, artifactPath)
	if err := os.WriteFile(filepath.Join(transcriptDir, "transcript.jsonl"), []byte(line+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(filepath.Join(home, ".gemini", "antigravity-ide", "brain", cascadeID))

	srv := newTestServer(&fakeRPCClient{cascadesRaw: trajectoryFrame(cascadeID)})
	defer srv.Close()

	client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
	defer client.conn.Close()

	client.send(t, map[string]string{"type": "get_context", "requestId": "ctx1"})
	resp := client.recv(t)
	if resp["error"] != nil {
		t.Fatalf("get_context a renvoyé une erreur: %v", resp["error"])
	}
	data, ok := resp["data"].(map[string]interface{})
	if !ok {
		t.Fatalf("data manquant ou invalide: %v", resp)
	}
	// 1 trajectoire réelle → artifactsCount = 1 (plus de mock en dur 2).
	if artifacts, ok := data["artifactsCount"].(float64); !ok || artifacts != 1 {
		t.Fatalf("artifactsCount attendu 1, reçu %v", data["artifactsCount"])
	}
	// Les anciens mocks en dur (1/3/2) ne doivent plus apparaître.
	if data["subagentsCount"].(float64) == 1 && data["filesChangedCount"].(float64) == 3 {
		t.Fatalf("statistiques mock en dur encore présentes: %v", data)
	}
}
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

// TestWebSocketApprovalExpiry — Phase 6 : une approbation sans réponse dans
// le délai (approvalTimeout) est auto-refusée côté daemon (deny = sécurité :
// téléphone perdu) puis broadcast approval_expired pour nettoyer les cartes.
func TestWebSocketApprovalExpiry(t *testing.T) {
	t.Run("timeout => auto-deny + approval_expired", func(t *testing.T) {
		backend := &fakeRPCClient{streamDeltas: []string{`{"run_command":"npx jest","step_index":1,"trajectory_id":"123e4567-e89b-12d3-a456-426614174000"}`}}
		server := NewServer(backend, "")
		server.SetApprovalTimeout(80 * time.Millisecond)
		mux := http.NewServeMux()
		mux.HandleFunc("/ws", server.HandleWebSocket)
		srv := httptest.NewServer(mux)
		defer srv.Close()

		client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
		defer client.conn.Close()

		client.send(t, map[string]string{
			"type": "send_prompt", "requestId": "r9",
			"cascadeId": "casc-1", "prompt": "travaille",
		})

		// Consomme stream_start + stream_delta + stream_end(outcome=approval)
		for {
			msg := client.recv(t)
			if msg["type"] == "stream_end" {
				break
			}
		}

		// Le timer expire → auto-refus + broadcast approval_expired (bloquant).
		expired := client.recv(t)
		if expired["type"] != "approval_expired" {
			t.Fatalf("Attendu approval_expired après expiration, reçu %v", expired)
		}
		data, _ := expired["data"].(map[string]interface{})
		if data == nil || data["cascadeId"] != "casc-1" {
			t.Fatalf("approval_expired data invalide: %v", expired)
		}

		// Auto-refus : SubmitToolApproval avec confirm=false (deny).
		got, ok := backend.lastApproval.(*submitApprovalCall)
		if !ok {
			t.Fatalf("Aucun SubmitToolApproval d'auto-refus enregistré")
		}
		if got.confirm {
			t.Fatalf("Auto-refus attendu avec confirm=false, reçu confirm=%v", got.confirm)
		}
		if got.cascadeID != "casc-1" || got.stepIndex != 1 || got.trajectoryID != "123e4567-e89b-12d3-a456-426614174000" {
			t.Fatalf("Auto-refus cible erronée: %+v", got)
		}
	})

	t.Run("submit before timeout => no expiry", func(t *testing.T) {
		backend := &fakeRPCClient{streamDeltas: []string{`{"run_command":"npx jest","step_index":1,"trajectory_id":"123e4567-e89b-12d3-a456-426614174000"}`}}
		server := NewServer(backend, "")
		server.SetApprovalTimeout(150 * time.Millisecond)
		mux := http.NewServeMux()
		mux.HandleFunc("/ws", server.HandleWebSocket)
		srv := httptest.NewServer(mux)
		defer srv.Close()

		client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
		defer client.conn.Close()

		client.send(t, map[string]string{
			"type": "send_prompt", "requestId": "r9",
			"cascadeId": "casc-1", "prompt": "travaille",
		})
		for {
			msg := client.recv(t)
			if msg["type"] == "stream_end" {
				break
			}
		}

		// L'utilisateur répond avant le timeout → pas d'expiration.
		// NOTE: envoi en JSON brut — le helper `send` (map[string]string)
		// sérialiserait stepIndex en chaîne, que le serveur rejette
		// (int64 strict, validation à la frontière de confiance) → le test
		// attendrait un "response" qui ne viendrait jamais.
		if err := client.conn.WriteMessage(websocket.TextMessage, []byte(`{"type":"submit_approval","requestId":"r10","cascadeId":"casc-1","trajectoryId":"123e4567-e89b-12d3-a456-426614174000","stepIndex":1,"approvalType":"run_command","decision":"allow","command":"npx jest"}`)); err != nil {
			t.Fatalf("envoi submit_approval: %v", err)
		}
		// réponse unary
		for {
			msg := client.recv(t)
			if msg["type"] == "response" {
				break
			}
		}

		// Attendre au-delà du timeout : aucun approval_expired ne doit arriver.
		time.Sleep(200 * time.Millisecond)
		client.conn.SetReadDeadline(time.Now().Add(150 * time.Millisecond))
		_, _, err := client.conn.ReadMessage()
		if err == nil {
			t.Fatal("Message inattendu reçu après submit (approval_expired ?)")
		}
	})
}

type submitApprovalCall struct {
	cascadeID    string
	trajectoryID string
	stepIndex    uint32
	confirm      bool
}

// TestWebSocketSendCommand — route une slash commande vers le backend.
func TestWebSocketSendCommand(t *testing.T) {
	backend := &fakeRPCClient{}
	srv := newTestServer(backend)
	defer srv.Close()
	client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
	defer client.conn.Close()

	client.send(t, map[string]string{"type": "send_command", "requestId": "r1", "command": "/model gemini-3-pro"})
	msg := client.recv(t)
	if msg["type"] != "response" || msg["requestId"] != "r1" {
		t.Fatalf("Réponse inattendue: %v", msg)
	}
	if backend.lastCommand != "/model gemini-3-pro" {
		t.Fatalf("Commande non routée: %q", backend.lastCommand)
	}
}

// TestWebSocketSendCommandMissingArg — send_command sans command → erreur.
func TestWebSocketSendCommandMissingArg(t *testing.T) {
	srv := newTestServer(&fakeRPCClient{})
	defer srv.Close()
	client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
	defer client.conn.Close()

	client.send(t, map[string]string{"type": "send_command", "requestId": "r2"})
	msg := client.recv(t)
	if msg["type"] != "response" || msg["error"] == "" {
		t.Fatalf("Attendu une erreur command manquante, reçu %v", msg)
	}
}

// ─── Tests P0 : list_models / delete_cascade / read_file / write_file ───

// TestWebSocketListModels — list_models parse GetAvailableModelsResponse et
// renvoie une liste structurée (pas un dump binaire).
func TestWebSocketListModels(t *testing.T) {
	// Réponse réaliste construite avec le writer de test.
	details := &protoWriter{}
	details.string(1, "Claude 3.7 Sonnet")
	details.varint(2, 1) // supports_images
	details.varint(3, 1) // supports_thinking
	details.varint(6, 1) // recommended
	entry := &protoWriter{}
	entry.string(1, "claude-3-7-sonnet")
	entry.bytes(2, details.buf)
	fetch := &protoWriter{}
	fetch.bytes(1, entry.buf)
	outer := &protoWriter{}
	outer.bytes(1, fetch.buf)

	backend := &fakeRPCClient{modelsRaw: connectrpc.Frame(outer.buf)}
	srv := newTestServer(backend)
	defer srv.Close()
	client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
	defer client.conn.Close()

	client.send(t, map[string]string{"type": "list_models", "requestId": "rM"})
	msg := client.recv(t)
	if msg["type"] != "response" || msg["requestId"] != "rM" {
		t.Fatalf("Réponse inattendue: %v", msg)
	}
	data, ok := msg["data"].(map[string]interface{})
	if !ok {
		t.Fatalf("data manquant: %v", msg)
	}
	models, ok := data["models"].([]interface{})
	if !ok || len(models) != 1 {
		t.Fatalf("attendu 1 modèle, reçu %v", data)
	}
	first, ok := models[0].(map[string]interface{})
	if !ok || first["modelId"] != "claude-3-7-sonnet" || first["displayName"] != "Claude 3.7 Sonnet" {
		t.Fatalf("modèle mal décodé: %v", models[0])
	}
	if first["supportsThinking"] != true || first["recommended"] != true {
		t.Fatalf("flags mal décodés: %v", first)
	}
}

// TestWebSocketDeleteCascade — confirmation requise, purge d'état après succès.
func TestWebSocketDeleteCascade(t *testing.T) {
	backend := &fakeRPCClient{}
	srv := newTestServer(backend)
	defer srv.Close()
	client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
	defer client.conn.Close()

	// 1. Sans confirm → refus (aucun appel RPC).
	client.send(t, map[string]string{"type": "delete_cascade", "requestId": "rD1", "cascadeId": "casc-9"})
	msg := client.recv(t)
	if msg["type"] != "response" || msg["error"] == "" {
		t.Fatalf("Attendu refus confirmation, reçu %v", msg)
	}
	if backend.lastDelete != "" {
		t.Fatalf("DeleteCascade ne devrait pas être appelé sans confirmation")
	}

	// 2. Avec confirm → RPC appelé + réponse OK.
	client.send(t, map[string]string{"type": "delete_cascade", "requestId": "rD2", "cascadeId": "casc-9", "confirm": "true"})
	msg = client.recv(t)
	if msg["type"] != "response" || msg["requestId"] != "rD2" || msg["error"] != nil {
		t.Fatalf("Réponse inattendue: %v", msg)
	}
	if backend.lastDelete != "casc-9" {
		t.Fatalf("DeleteCascade appelé avec %q, attendu casc-9", backend.lastDelete)
	}
}

// TestWebSocketDeleteCascadePurgesState — après succès, le buffer StepRecovery
// et l'approbation en attente sont purgés (pas de fantôme sur get_pending_approval).
func TestWebSocketDeleteCascadePurgesState(t *testing.T) {
	backend := &fakeRPCClient{}
	srv := NewServer(backend, "")

	// Simule un stream en cours + approbation posée.
	srv.MarkCascadeActive("casc-9")
	srv.streamBuffer.RecordEvent("casc-9", OutgoingMessage{Type: "delta", Data: "old"})
	srv.MarkApprovalPending("casc-9", connectrpc.StreamEvent{CallID: "c1", TrajectoryID: "t1", StepIndex: 1, Tool: "run_command"})
	srv.markSessionApproval("casc-9", "run_command")

	srv.purgeCascadeState("casc-9")

	// GetEventsSince sur cascade purgée → (nil, 0) : aucun événement résiduel.
	evts, seq := srv.streamBuffer.GetEventsSince("casc-9", 0)
	if len(evts) != 0 || seq != 0 {
		t.Fatalf("buffer non purgé: %d événements, seq=%d", len(evts), seq)
	}
	if srv.hasPendingApproval("casc-9") {
		t.Fatal("approbation devrait être purgée")
	}
	if srv.hasSessionApproval("casc-9", "run_command") {
		t.Fatal("sessionApproval devrait être purgée")
	}
	srv.mu.Lock()
	active := srv.activeCascades["casc-9"]
	srv.mu.Unlock()
	if active {
		t.Fatal("activeCascades devrait être purgé")
	}
}

// TestWebSocketReadFile — read_file route vers ReadFile avec URI normalisée.
func TestWebSocketReadFile(t *testing.T) {
	backend := &fakeRPCClient{}
	srv := newTestServer(backend)
	defer srv.Close()
	client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
	defer client.conn.Close()

	client.send(t, map[string]string{"type": "read_file", "requestId": "rR", "filePath": `C:\Users\test\proj\main.go`})
	msg := client.recv(t)
	if msg["type"] != "response" || msg["error"] != nil {
		t.Fatalf("Réponse inattendue: %v", msg)
	}
	if backend.lastRead != "file:///C:/Users/test/proj/main.go" {
		t.Fatalf("ReadFile appelé avec %q", backend.lastRead)
	}
}

// TestWebSocketReadFileMissingPath — read_file sans filePath → erreur.
func TestWebSocketReadFileMissingPath(t *testing.T) {
	srv := newTestServer(&fakeRPCClient{})
	defer srv.Close()
	client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
	defer client.conn.Close()

	client.send(t, map[string]string{"type": "read_file", "requestId": "rR2"})
	msg := client.recv(t)
	if msg["type"] != "response" || msg["error"] == nil {
		t.Fatalf("Attendu erreur filePath manquant, reçu %v", msg)
	}
}

// TestWebSocketWriteFile — write_file décode base64 et route vers WriteFile.
func TestWebSocketWriteFile(t *testing.T) {
	backend := &fakeRPCClient{}
	srv := newTestServer(backend)
	defer srv.Close()
	client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
	defer client.conn.Close()

	content := base64.StdEncoding.EncodeToString([]byte("package main\n"))
	payload := map[string]interface{}{
		"type":      "write_file",
		"requestId": "rW",
		"filePath":  `C:\Users\test\proj\main.go`,
		"content":   content,
		"overwrite": true,
	}
	b, _ := json.Marshal(payload)
	if err := client.conn.WriteMessage(websocket.TextMessage, b); err != nil {
		t.Fatalf("envoi write_file: %v", err)
	}
	msg := client.recv(t)
	if msg["type"] != "response" || msg["error"] != nil {
		t.Fatalf("Réponse inattendue: %v", msg)
	}
	if backend.lastWrite == nil {
		t.Fatal("WriteFile non appelé")
	}
	if backend.lastWrite.uri != "file:///C:/Users/test/proj/main.go" {
		t.Fatalf("WriteFile uri = %q", backend.lastWrite.uri)
	}
	if string(backend.lastWrite.content) != "package main\n" {
		t.Fatalf("WriteFile content = %q", backend.lastWrite.content)
	}
	if !backend.lastWrite.overwrite {
		t.Fatal("WriteFile overwrite devrait être true")
	}
}

// TestWebSocketWriteFileInvalidBase64 — content non-base64 → erreur, pas d'appel RPC.
func TestWebSocketWriteFileInvalidBase64(t *testing.T) {
	backend := &fakeRPCClient{}
	srv := newTestServer(backend)
	defer srv.Close()
	client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
	defer client.conn.Close()

	client.send(t, map[string]string{"type": "write_file", "requestId": "rW2", "filePath": "C:/x/y.go", "content": "%%%not-base64%%%"})
	msg := client.recv(t)
	if msg["type"] != "response" || msg["error"] == "" {
		t.Fatalf("Attendu erreur base64, reçu %v", msg)
	}
}

// TestWebSocketSetApprovalTimeout — chaîne Settings mobile → daemon :
// le message WS "set_approval_timeout" met à jour approvalTimeout ET
// la réponse confirme la valeur. La mise à jour est ensuite visible via
// l'expiration d'une approbation (auto-refus après le nouveau délai).
func TestWebSocketSetApprovalTimeout(t *testing.T) {
	t.Run("minutes valides => réponse + timer mis à jour", func(t *testing.T) {
		backend := &fakeRPCClient{streamDeltas: []string{`{"run_command":"npx jest","step_index":1,"trajectory_id":"123e4567-e89b-12d3-a456-426614174000"}`}}
		srv := newTestServer(backend)
		defer srv.Close()
		client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
		defer client.conn.Close()

		// Mise à jour du délai (30 min, format JSON nombre flottant).
		client.sendRaw(t, `{"type":"set_approval_timeout","requestId":"t1","data":{"minutes":30}}`)
		msg := client.recv(t)
		if msg["type"] != "response" || msg["requestId"] != "t1" {
			t.Fatalf("Réponse inattendue: %v", msg)
		}
		data, _ := msg["data"].(map[string]interface{})
		if data == nil || data["approvalTimeoutMinutes"] != float64(30) {
			t.Fatalf("Réponse sans confirmation du délai: %v", msg)
		}

		// Le délai est réellement appliqué : une approbation reçue ensuite
		// expire après 80 ms (au lieu des 5 min par défaut).
		client.send(t, map[string]string{"type": "send_prompt", "requestId": "r9", "cascadeId": "casc-1", "prompt": "travaille"})
		for {
			m := client.recv(t)
			if m["type"] == "stream_end" {
				break
			}
		}
		expired := client.recv(t)
		if expired["type"] != "approval_expired" {
			t.Fatalf("Attendu approval_expired après expiration rapide, reçu %v", expired)
		}
	})

	t.Run("minutes invalides => erreur", func(t *testing.T) {
		srv := newTestServer(&fakeRPCClient{})
		defer srv.Close()
		client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
		defer client.conn.Close()

		client.sendRaw(t, `{"type":"set_approval_timeout","requestId":"t2","data":{"minutes":-5}}`)
		msg := client.recv(t)
		if msg["type"] != "response" || msg["error"] == "" {
			t.Fatalf("Attendu une erreur minutes invalides, reçu %v", msg)
		}
	})
}
