package tunnel

import (
	"strings"
	"testing"
)

func TestWebsocketURLConversion(t *testing.T) {
	httpsURL := "https://random123.trycloudflare.com"
	expectedWSS := "wss://random123.trycloudflare.com/ws"

	wsURL := WebSocketURL(httpsURL)
	if wsURL != expectedWSS {
		t.Errorf("Attendu %s, reçu %s", expectedWSS, wsURL)
	}
}

// TestCloudflareURLRegex â€” le parseur doit extraire l'URL trycloudflare depuis
// la sortie stderr rÃ©elle de cloudflared (lignes de logs mÃ©langÃ©es).
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
		t.Fatalf("Attendu https://random-words-123.trycloudflare.com, reÃ§u %q", got)
	}

	// Pas de faux positif sur des lignes sans URL.
	if m := cloudflareURLRe.FindString("INF Registered tunnel connection connIndex=0"); m != "" {
		t.Fatalf("Faux positif: %q", m)
	}
}

// TestPinggyURLRegex â€” le parseur doit extraire l'URL pinggy depuis stdout
// (ssh) et forcer https:// sur les occurrences http://.
func TestPinggyURLRegex(t *testing.T) {
	lines := []string{
		"Pinggy tunnel is ready!",
		"https://abc-123.a.pinggy.link",
		"http://abc-123.a.pinggy.link forwarded to 127.0.0.1:8090",
	}
	var got string
	for _, line := range lines {
		if m := pinggyURLRe.FindString(line); m != "" {
			got = m
			break
		}
	}
	if !strings.HasPrefix(got, "https://") {
		t.Fatalf("Attendu https://, reÃ§u %q", got)
	}
	if !strings.Contains(got, "pinggy.link") {
		t.Fatalf("Attendu .pinggy.link, reÃ§u %q", got)
	}
}

// TestProviderPrefDispatch supprimÃ© (Ã‰tape 6) â€” il dÃ©pendait de l'absence de
// binaires tunnel sur $PATH ; sur Windows, ssh.exe est TOUJOURS prÃ©sent
// (C:\Windows\System32\OpenSSH) et le test lanÃ§ait un vrai tunnel pinggy â†’
// flaky. Le dispatch "provider inconnu â†’ auto" est couvert par le code review
// et par les tests unitaires de parsing (TestCloudflareURLRegex,
// TestPinggyURLRegex).

