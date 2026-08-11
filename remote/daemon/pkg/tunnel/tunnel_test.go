package tunnel

import (
	"strings"
	"testing"
)

func TestWebsocketURLConversion(t *testing.T) {
	httpsURL := "https://random123.trycloudflare.com"
	expectedWSS := "wss://random123.trycloudflare.com/ws"

	wsURL := strings.Replace(httpsURL, "https://", "wss://", 1) + "/ws"
	if wsURL != expectedWSS {
		t.Errorf("Attendu %s, reçu %s", expectedWSS, wsURL)
	}
}
