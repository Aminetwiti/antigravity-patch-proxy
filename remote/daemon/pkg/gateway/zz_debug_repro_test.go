package gateway

import (
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

// TestDebugRepro — mini reproduction de TestWebSocketConcurrentClients avec
// journalisation complète de chaque envoi/réception pour voir si le serveur
// écrit 2 réponses pour 1 message ou si le client lit dans le désordre.
func TestDebugRepro(t *testing.T) {
	backend := &loadRPCClient{}
	srv := newTestServer(backend)
	defer srv.Close()

	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http") + "/ws"
	const clients = 4
	const perClient = 4

	var wg sync.WaitGroup
	var mu sync.Mutex
	logf := func(format string, args ...interface{}) {
		mu.Lock()
		defer mu.Unlock()
		t.Logf(format, args...)
	}

	for c := 0; c < clients; c++ {
		wg.Add(1)
		go func(c int) {
			defer wg.Done()
			conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
			if err != nil {
				logf("client %d: DIAL ERR %v", c, err)
				return
			}
			defer conn.Close()

			for i := 0; i < perClient; i++ {
				rid := fmt.Sprintf("r-%d-%d", c, i)
				if err := conn.WriteJSON(map[string]string{"type": "heartbeat", "requestId": rid}); err != nil {
					logf("client %d msg %d: SEND ERR %v", c, i, err)
					return
				}
				logf("client %d msg %d: SENT %s", c, i, rid)
				conn.SetReadDeadline(time.Now().Add(3 * time.Second))
				var out map[string]interface{}
				if err := conn.ReadJSON(&out); err != nil {
					logf("client %d msg %d: RECV ERR %v", c, i, err)
					return
				}
				logf("client %d msg %d: GOT %v (want %s)", c, i, out["requestId"], rid)
			}
		}(c)
	}
	wg.Wait()
}
