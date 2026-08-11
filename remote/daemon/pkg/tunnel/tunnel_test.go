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

// TestCloudflareURLRegex — le parseur doit extraire l'URL trycloudflare depuis
// la sortie stderr réelle de cloudflared (lignes de logs mélangées).
func TestCloudflareURLRegex(t *testing.T) {
	lines := []string{
		"INF Registered tunnel connection connIndex=0",
		"INF +--------------------------------------------------------------------------------------------+",
		"INF |  Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):  |",
		"INF |  https://random-words-123.trycloudflare.com                                                |",
		"INF +--------------------------------------------------------------------------------------------+",
	}
	var got string
	for _, line := range lines {
		if m := cloudflareURLRe.FindString(line); m != "" {
			got = m
			break
		}
	}
	if got != "https://random-words-123.trycloudflare.com" {
		t.Fatalf("Attendu https://random-words-123.trycloudflare.com, reçu %q", got)
	}

	// Pas de faux positif sur des lignes sans URL.
	if m := cloudflareURLRe.FindString("INF Registered tunnel connection connIndex=0"); m != "" {
		t.Fatalf("Faux positif: %q", m)
	}
}

// TestPinggyURLRegex — le parseur doit extraire l'URL pinggy depuis stdout
// (ssh) et forcer https:// sur les occurrences http://.
func TestPinggyURLRegex(t *testing.T) {
	lines := []string{
		"Pinggy tunnel is ready!",
		"https://abc-123.a.pinggy.link",
		"http://abc-123.a.pinggy.link forwarded to 127.0.0.1:8089",
	}
	var got string
	for _, line := range lines {
		if m := pinggyURLRe.FindString(line); m != "" {
			got = m
			break
		}
	}
	if !strings.HasPrefix(got, "https://") {
		t.Fatalf("Attendu https://, reçu %q", got)
	}
	if !strings.Contains(got, "pinggy.link") {
		t.Fatalf("Attendu .pinggy.link, reçu %q", got)
	}
}

// TestProviderPrefDispatch — un provider forcé inconnu retombe sur l'auto
// (erreur \"aucun fournisseur\" sans binaire réel, pas de panique).
func TestProviderPrefDispatch(t *testing.T) {
	m := NewManager("unknown-provider")
	_, err := m.StartAutoTunnel(8089)
	if err == nil {
		t.Fatal("Attendu une erreur (aucun tunnel disponible dans l'environnement de test)")
	}
	if !strings.Contains(err.Error(), "aucun fournisseur") {
		t.Fatalf("Erreur inattendue: %v", err)
	}
}
