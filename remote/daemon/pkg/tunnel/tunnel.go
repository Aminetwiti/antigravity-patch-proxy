package tunnel

import (
	"bufio"
	"fmt"
	"log"
	"os/exec"
	"regexp"
	"strings"
	"sync"
	"time"
)

// Regexes d'extraction d'URL (package-level pour testabilité sans binaire réel).
var (
	cloudflareURLRe = regexp.MustCompile(`https://[a-zA-Z0-9-]+\.trycloudflare\.com`)
	// https?://[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*\.pinggy\.link — couvre aussi
	// "a.pinggy.link" (sous-domaine à label unique) et le préfixe ssh://.
	pinggyURLRe     = regexp.MustCompile(`(?:https?|ssh)://[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*\.pinggy\.link`)
)

type Manager struct {
	Provider     string `json:"provider"`
	ProviderPref string `json:"-"`
	PublicURL    string `json:"publicUrl"`
	cmd          *exec.Cmd
	mu           sync.Mutex
	stopChan     chan struct{}
}

func NewManager(providerPref string) *Manager {
	return &Manager{
		ProviderPref: providerPref,
		stopChan:     make(chan struct{}),
	}
}

// StartAutoTunnel tente de lancer Cloudflare Quick Tunnel ou Pinggy SSH Tunnel.
func (m *Manager) StartAutoTunnel(localPort int) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	// Si un provider est forcé
	if m.ProviderPref == "cloudflare" {
		return m.tryCloudflare(localPort)
	} else if m.ProviderPref == "pinggy" {
		return m.tryPinggy(localPort)
	} else if m.ProviderPref != "" {
		log.Printf("⚠️ Fournisseur de tunnel inconnu: %s. Essai automatique...", m.ProviderPref)
	}

	// 1. Essayer Cloudflare Quick Tunnel (cloudflared)
	if url, err := m.tryCloudflare(localPort); err == nil {
		return url, nil
	}

	// 2. Essayer Pinggy SSH Tunnel (ssh)
	if url, err := m.tryPinggy(localPort); err == nil {
		return url, nil
	}

	return "", fmt.Errorf("aucun fournisseur de tunnel disponible (cloudflared ou ssh introuvable sur $PATH)")
}

func (m *Manager) tryCloudflare(localPort int) (string, error) {
	path, err := exec.LookPath("cloudflared")
	if err != nil {
		return "", fmt.Errorf("cloudflared introuvable")
	}
	log.Printf("[Tunnel] Lancement de Cloudflare Quick Tunnel (%s)...", path)
	url, err := m.startCloudflare(path, localPort)
	if err == nil {
		m.Provider = "cloudflare"
		m.PublicURL = url
		m.printBanner(url)
		return url, nil
	}
	log.Printf("[Tunnel] Échec Cloudflare: %v", err)
	return "", err
}

func (m *Manager) tryPinggy(localPort int) (string, error) {
	path, err := exec.LookPath("ssh")
	if err != nil {
		return "", fmt.Errorf("ssh introuvable")
	}
	log.Printf("[Tunnel] Lancement de Pinggy SSH Tunnel (%s)...", path)
	url, err := m.startPinggy(path, localPort)
	if err == nil {
		m.Provider = "pinggy"
		m.PublicURL = url
		m.printBanner(url)
		return url, nil
	}
	log.Printf("[Tunnel] Échec Pinggy SSH: %v", err)
	return "", err
}

func (m *Manager) startCloudflare(binPath string, localPort int) (string, error) {
	targetURL := fmt.Sprintf("http://127.0.0.1:%d", localPort)
	cmd := exec.Command(binPath, "tunnel", "--url", targetURL)
	m.cmd = cmd

	stderr, err := cmd.StderrPipe()
	if err != nil {
		return "", err
	}

	if err := cmd.Start(); err != nil {
		return "", err
	}

	urlChan := make(chan string, 1)
	re := cloudflareURLRe

	go func() {
		scanner := bufio.NewScanner(stderr)
		for scanner.Scan() {
			line := scanner.Text()
			if match := re.FindString(line); match != "" {
				select {
				case urlChan <- match:
				default:
				}
			}
		}
	}()

	select {
	case url := <-urlChan:
		return url, nil
	case <-time.After(15 * time.Second):
		cmd.Process.Kill()
		return "", fmt.Errorf("timeout d'attente de l'URL Cloudflare")
	}
}

func (m *Manager) startPinggy(binPath string, localPort int) (string, error) {
	args := []string{
		"-o", "StrictHostKeyChecking=no",
		"-o", "ServerAliveInterval=30",
		"-R", fmt.Sprintf("0:127.0.0.1:%d", localPort),
		"a.pinggy.io",
	}
	cmd := exec.Command(binPath, args...)
	m.cmd = cmd

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return "", err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return "", err
	}

	if err := cmd.Start(); err != nil {
		return "", err
	}

	urlChan := make(chan string, 1)
	re := pinggyURLRe

	scanFunc := func(scanner *bufio.Scanner) {
		for scanner.Scan() {
			line := scanner.Text()
			if match := re.FindString(line); match != "" {
				// Assurez-vous d'avoir https
				match = strings.Replace(match, "http://", "https://", 1)
				select {
				case urlChan <- match:
				default:
				}
			}
		}
	}

	go scanFunc(bufio.NewScanner(stdout))
	go scanFunc(bufio.NewScanner(stderr))

	select {
	case url := <-urlChan:
		return url, nil
	case <-time.After(15 * time.Second):
		cmd.Process.Kill()
		return "", fmt.Errorf("timeout d'attente de l'URL Pinggy")
	}
}

func (m *Manager) printBanner(publicURL string) {
	wsURL := strings.Replace(publicURL, "https://", "wss://", 1) + "/ws"
	fmt.Println("\n========================================================")
	fmt.Println("🌐 TUNNEL DISTANT 4G/5G ET ACCÈS HORS DOMICILE ACTIF !")
	fmt.Printf("   Fournisseur : %s\n", strings.ToUpper(m.Provider))
	fmt.Printf("   URL Web     : %s\n", publicURL)
	fmt.Printf("   URL WebSocket mobile : %s\n", wsURL)
	fmt.Println("========================================================")
	PrintQRCode(wsURL)
}

func (m *Manager) Stop() {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.cmd != nil && m.cmd.Process != nil {
		m.cmd.Process.Kill()
	}
}

