package tunnel

import (
	"os"
	"os/exec"
	"strings"
	"testing"
)

// FakeBinaries remplace execCommand par des faux binaires qui émulent la
// sortie de cloudflared / ssh / taskkill — aucun binaire réel requis.
// Pattern standard Go : re-exec du binaire de test avec -test.run sur un
// helper, la cible étant passée via GO_FAKE_BIN.
func FakeBinaries(t *testing.T) {
	t.Helper()
	execCommand = func(name string, args ...string) *exec.Cmd {
		cmd := exec.Command(os.Args[0], "-test.run=TestFakeBinariesHelper")
		cmd.Env = append(os.Environ(), "GO_FAKE_BIN="+name)
		return cmd
	}
	// Résolution des binaires : toujours trouvés (nom arbitraire) — aucun
	// vrai cloudflared/ssh requis, et pas de dépendance au $PATH de la CI.
	execLookPath = func(name string) (string, error) { return name, nil }
	t.Cleanup(func() {
		execCommand = exec.Command
		execLookPath = exec.LookPath
	})
}

// TestFakeBinariesHelper s'exécute DANS le process de test (re-exec) et
// émule la sortie du binaire nommé par GO_FAKE_BIN, puis se termine. Les vrais
// cloudflared/ssh resteraient vivants, mais le Manager ne lit que l'URL :
// l'arrêt prématuré du faux n'a aucun impact.
func TestFakeBinariesHelper(t *testing.T) {
	switch os.Getenv("GO_FAKE_BIN") {
	case "cloudflared":
		os.Stderr.WriteString("INF Your quick Tunnel has been created! https://fake-123.trycloudflare.com\n")
	case "ssh":
		os.Stdout.WriteString("https://abc-123.a.pinggy.link ready\n")
	case "taskkill":
		os.Exit(0)
	}
}

// --- tests réels ---

// TestStartCloudflareFakeBinary — le Manager démarre un faux cloudflared et
// extrait l'URL depuis stderr.
func TestStartCloudflareFakeBinary(t *testing.T) {
	FakeBinaries(t)
	m := NewManager("")
	url, err := m.startCloudflare("cloudflared", 8090)
	if err != nil {
		t.Fatalf("startCloudflare: %v", err)
	}
	if !strings.Contains(url, ".trycloudflare.com") {
		t.Fatalf("URL inattendue: %q", url)
	}
	m.Stop()
}

// TestStartPinggyFakeBinary — le Manager démarre un faux ssh et extrait l'URL
// pinggy depuis stdout (avec normalisation https://).
func TestStartPinggyFakeBinary(t *testing.T) {
	FakeBinaries(t)
	m := NewManager("")
	url, err := m.startPinggy("ssh", 8090)
	if err != nil {
		t.Fatalf("startPinggy: %v", err)
	}
	if !strings.HasPrefix(url, "https://") || !strings.Contains(url, ".pinggy.link") {
		t.Fatalf("URL inattendue: %q", url)
	}
	m.Stop()
}

// TestStartAutoTunnelForcedProvider — dispatch par provider forcé, sans
// dépendre de la présence de binaires sur $PATH.
func TestStartAutoTunnelForcedProvider(t *testing.T) {
	FakeBinaries(t)
	m := NewManager("cloudflare")
	url, err := m.StartAutoTunnel(8090)
	if err != nil {
		t.Fatalf("StartAutoTunnel(cloudflare): %v", err)
	}
	if m.Provider != "cloudflare" {
		t.Fatalf("Provider attendu cloudflare, reçu %q", m.Provider)
	}
	if m.PublicURL != url {
		t.Fatalf("PublicURL non posée")
	}
	m.Stop()

	m2 := NewManager("pinggy")
	if _, err := m2.StartAutoTunnel(8090); err != nil {
		t.Fatalf("StartAutoTunnel(pinggy): %v", err)
	}
	if m2.Provider != "pinggy" {
		t.Fatalf("Provider attendu pinggy, reçu %q", m2.Provider)
	}
	if !strings.Contains(m2.PublicURL, ".pinggy.link") {
		t.Fatalf("PublicURL inattendue: %q", m2.PublicURL)
	}
	m2.Stop()
}

// TestStopWindowsKillsProcess — Stop() passe par taskkill sur Windows (faux
// binaire) et ne panique pas.
func TestStopWindowsKillsProcess(t *testing.T) {
	FakeBinaries(t)
	m := NewManager("cloudflare")
	if _, err := m.StartAutoTunnel(8090); err != nil {
		t.Fatalf("StartAutoTunnel: %v", err)
	}
	if m.cmd == nil || m.cmd.Process == nil {
		t.Fatalf("cmd non démarré")
	}
	m.Stop()
}

// TestStartAutoTunnelUnknownProvider — provider inconnu → repli automatique
// sur la chaîne cloudflare→pinggy (comportement voulu en production : le
// daemon démarre quand même). Avec les faux binaires, cloudflare gagne.
func TestStartAutoTunnelUnknownProvider(t *testing.T) {
	FakeBinaries(t)
	m := NewManager("bogus")
	url, err := m.StartAutoTunnel(8090)
	if err != nil {
		t.Fatalf("provider inconnu doit retomber sur l'auto: %v", err)
	}
	if m.Provider != "cloudflare" {
		t.Fatalf("Provider attendu cloudflare (auto fallback), reçu %q", m.Provider)
	}
	if !strings.Contains(url, ".trycloudflare.com") {
		t.Fatalf("URL inattendue: %q", url)
	}
	m.Stop()
}

// TestStopNoProcessNoPanic — Stop() sans tunnel démarré ne panique pas.
func TestStopNoProcessNoPanic(t *testing.T) {
	m := NewManager("")
	m.Stop() // doit être un no-op silencieux
}
