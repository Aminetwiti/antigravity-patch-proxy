package discovery

import (
	"bytes"
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"net/http"
	"os/exec"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
)

type LocalHarnessInfo struct {
	PID            int
	ProcessName    string
	CSRFToken      string
	ExtensionCSRF  string
	ExtensionPort  int
	WorkspaceID    string
	SubclientType  string
	ConnectRPCPort int
}

type procEntry struct {
	pid         int
	name        string
	commandLine string
}

func Discover() (*LocalHarnessInfo, error) {
	procs, err := getProcesses()
	if err != nil {
		return nil, err
	}
	if len(procs) == 0 {
		return nil, fmt.Errorf("language_server introuvable — IDE Antigravity ouvert ?")
	}

	// Cibler l'instance hub standalone EN PRIORITÉ : c'est elle qui expose les
	// RPC de session (GetAllCascadeTrajectories, SendUserCascadeMessage…).
	// Les instances IDE (--subclient_type ide) répondent « 200 corps vide »
	// sur ces méthodes → list_sessions renvoyait « aucune frame gRPC-Web
	// dans la réponse (0 octets) » et send_prompt ne streamait rien.
	// Voir PROTOCOL.md §3.2 : « Cibler l'instance hub ».
	var sortedProcs []procEntry
	for _, p := range procs {
		if strings.Contains(p.commandLine, "--subclient_type hub") {
			sortedProcs = append(sortedProcs, p)
		}
	}
	// Ensuite l'instance IDE active du workspace (--workspace_id / --enable_lsp),
	// puis les autres instances IDE — repli si aucun hub standalone ne tourne.
	for _, p := range procs {
		if strings.Contains(p.commandLine, "--subclient_type hub") {
			continue
		}
		if strings.Contains(p.commandLine, "--workspace_id") || strings.Contains(p.commandLine, "--enable_lsp") {
			sortedProcs = append([]procEntry{p}, sortedProcs...)
		} else if strings.Contains(p.commandLine, "--subclient_type ide") {
			sortedProcs = append(sortedProcs, p)
		}
	}
	for _, p := range procs {
		if strings.Contains(p.commandLine, "--subclient_type hub") ||
			strings.Contains(p.commandLine, "--subclient_type ide") ||
			strings.Contains(p.commandLine, "--workspace_id") ||
			strings.Contains(p.commandLine, "--enable_lsp") {
			continue
		}
		sortedProcs = append(sortedProcs, p)
	}
	if len(sortedProcs) == 0 {
		sortedProcs = procs
	}

	for _, pick := range sortedProcs {
		info := &LocalHarnessInfo{
			PID:           pick.pid,
			ProcessName:   pick.name,
			CSRFToken:     extractArg(pick.commandLine, "csrf_token"),
			ExtensionCSRF: extractArg(pick.commandLine, "extension_server_csrf_token"),
			ExtensionPort: atoi(extractArg(pick.commandLine, "extension_server_port")),
			WorkspaceID:   extractArg(pick.commandLine, "workspace_id"),
			SubclientType: extractArg(pick.commandLine, "subclient_type"),
		}
		if info.ExtensionCSRF == "" {
			info.ExtensionCSRF = info.CSRFToken
		}

		candidates := candidatePorts(info, &pick)
		token := info.ExtensionCSRF
		if port := probePorts(candidates, token); port > 0 {
			info.ConnectRPCPort = port
			return info, nil
		}
	}
	return nil, fmt.Errorf("aucun port ne répond au service RPC parmi les %d processus testés", len(sortedProcs))
}

// probePorts sonde les ports candidats EN PARALLÈLE (worker pool borné — le
// premier port qui répond gagne). L'ancien balayage séquentiel coûtait jusqu'à
// 20 × timeout HTTP (3 s) = 60 s au pire quand le hub était sur un port haut.
func probePorts(ports []int, csrfToken string) int {
	if len(ports) == 0 {
		return 0
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	result := make(chan int, 1)

	workers := len(ports)
	if workers > 8 {
		workers = 8 // 8 workers suffisent : le goulot est le timeout réseau
	}
	sem := make(chan struct{}, workers)
	var wg sync.WaitGroup
	for _, port := range ports {
		port := port // capture de boucle (Go < 1.22)
		wg.Add(1)
		go func() {
			defer wg.Done()
			select {
			case sem <- struct{}{}:
				defer func() { <-sem }()
			case <-ctx.Done():
				return
			}
			if probeService(port, csrfToken) {
				select {
				case result <- port:
					cancel() // le premier gagnant arrête les autres sondes
				default:
				}
			}
		}()
	}
	go func() { wg.Wait(); close(result) }()

	for port := range result {
		return port
	}
	return 0
}

// candidatePorts : extension_server_port+1..+20 si présent, sinon netstat PID.
func candidatePorts(info *LocalHarnessInfo, p *procEntry) []int {
	var ports []int
	if info.ExtensionPort > 0 {
		for offset := 1; offset <= 20; offset++ {
			ports = append(ports, info.ExtensionPort+offset)
		}
	} else {
		ports = listeningPortsForPID(p.pid)
	}
	return ports
}

// listeningPortsForPID récupère les ports d'écoute du PID via netstat.
func listeningPortsForPID(pid int) []int {
	var out bytes.Buffer
	cmd := exec.Command("netstat", "-ano")
	cmd.Stdout = &out
	if err := cmd.Run(); err != nil {
		return nil
	}
	pidStr := strconv.Itoa(pid)
	var ports []int
	for _, line := range strings.Split(out.String(), "\n") {
		fields := strings.Fields(line)
		if len(fields) < 5 || fields[4] != pidStr {
			continue
		}
		if !strings.Contains(fields[3], "LISTEN") {
			continue
		}
		// format : TCP 127.0.0.1:60656 ... -> extraire le port après le ':'
		addr := fields[1]
		idx := strings.LastIndex(addr, ":")
		if idx < 0 {
			continue
		}
		port, err := strconv.Atoi(addr[idx+1:])
		if err == nil && port > 0 {
			ports = append(ports, port)
		}
	}
	return ports
}

// probeService vérifie que le port expose bien le LanguageServerService.
// 1. Sonde HTTP : frame gRPC-Web Heartbeat (chemin principal).
// 2. Sonde HTTPS : GetUserStatus en JSON — le LS expose parfois des ports
// TLS (certificat auto-signé) que la sonde HTTP rate ; technique reprise de
// Deck/IDE-mobile (quota-service.ts, rejectUnauthorized: false).
func probeService(port int, csrfToken string) bool {
	if probeHTTPHeartbeat(port, csrfToken) {
		return true
	}
	return probeHTTPSGetUserStatus(port, csrfToken)
}

func probeHTTPHeartbeat(port int, csrfToken string) bool {
	url := fmt.Sprintf("http://127.0.0.1:%d/exa.language_server_pb.LanguageServerService/Heartbeat", port)
	body := make([]byte, 5) // frame gRPC-Web vide
	req, err := http.NewRequest("POST", url, bytes.NewReader(body))
	if err != nil {
		return false
	}
	req.Header.Set("Content-Type", "application/grpc-web+proto")
	req.Header.Set("Accept", "application/grpc-web+proto,application/grpc-web-text")
	req.Header.Set("x-codeium-csrf-token", csrfToken)
	req.Header.Set("Connect-Protocol-Version", "1")
	req.Header.Set("X-Grpc-Web", "1")

	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	io.Copy(io.Discard, resp.Body)
	return resp.StatusCode == http.StatusOK
}

func probeHTTPSGetUserStatus(port int, csrfToken string) bool {
	body := []byte(`{"metadata":{"ideName":"antigravity"}}`)
	req, err := http.NewRequest("POST", fmt.Sprintf("https://127.0.0.1:%d/exa.language_server_pb.LanguageServerService/GetUserStatus", port), bytes.NewReader(body))
	if err != nil {
		return false
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Connect-Protocol-Version", "1")
	req.Header.Set("X-Codeium-Csrf-Token", csrfToken)

	// Certificat auto-signé du LS : on accepte tout (le jeton CSRF authentifie).
	client := &http.Client{
		Timeout: 3 * time.Second,
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true}, // #nosec G402 — jeton CSRF requis
		},
	}
	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	return resp.StatusCode == http.StatusOK && bytes.Contains(raw, []byte("user_status"))
}

func getProcesses() ([]procEntry, error) {
	if runtime.GOOS == "windows" {
		ps := "Get-CimInstance Win32_Process | Where-Object { $_.Name -like '*language_server*' } | Select-Object ProcessId, Name, CommandLine | ConvertTo-Json -Compress"
		cmd := exec.Command("powershell", "-NoProfile", "-Command", ps)
		var out bytes.Buffer
		cmd.Stdout = &out
		if err := cmd.Run(); err != nil {
			return nil, err
		}
		str := strings.TrimSpace(out.String())
		if str == "" {
			return nil, nil
		}
		// ConvertTo-Json -Compress n'échappe pas les backslashes : analyse regex.
		var procs []procEntry
		for _, l := range splitJsonObjects(str) {
			procs = append(procs, procEntry{
				pid:         extractJsonInt(l, "ProcessId"),
				name:        extractJsonString(l, "Name"),
				commandLine: extractJsonString(l, "CommandLine"),
			})
		}
		return procs, nil
	}
	// macOS / Linux
	cmd := exec.Command("sh", "-c", "ps aux | grep -i language_server | grep -v grep")
	var out bytes.Buffer
	cmd.Stdout = &out
	if err := cmd.Run(); err != nil {
		return nil, err
	}
	var procs []procEntry
	for _, line := range strings.Split(strings.TrimSpace(out.String()), "\n") {
		if line == "" {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		pid, _ := strconv.Atoi(fields[1])
		procs = append(procs, procEntry{pid: pid, name: fields[0], commandLine: line})
	}
	return procs, nil
}

func splitJsonObjects(s string) []string {
	trimmed := strings.TrimSpace(s)
	trimmed = strings.TrimPrefix(trimmed, "[")
	trimmed = strings.TrimSuffix(trimmed, "]")
	trimmed = strings.TrimSpace(trimmed)
	if trimmed == "" {
		return nil
	}
	// Objet unique (pas de séparateur d'array)
	if !strings.Contains(trimmed, "},{") {
		return []string{trimmed}
	}
	parts := strings.Split(trimmed, "},{")
	out := make([]string, 0, len(parts))
	for i, p := range parts {
		if !strings.HasPrefix(p, "{") {
			p = "{" + p
		}
		if !strings.HasSuffix(p, "}") {
			p = p + "}"
		}
		if i > 0 {
			p = "{" + p
		}
		out = append(out, p)
	}
	return out
}

func extractJsonString(s, key string) string {
	re := regexp.MustCompile(`"` + key + `"\s*:\s*"((?:[^"\\]|\\.)*)"`)
	m := re.FindStringSubmatch(s)
	if len(m) > 1 {
		return strings.ReplaceAll(m[1], `\"`, `"`)
	}
	return ""
}

func extractJsonInt(s, key string) int {
	re := regexp.MustCompile(`"` + key + `"\s*:\s*(\d+)`)
	m := re.FindStringSubmatch(s)
	if len(m) > 1 {
		v, _ := strconv.Atoi(m[1])
		return v
	}
	return 0
}

func extractArg(cmdLine, name string) string {
	// Format réel observé : "--csrf_token <value>" (espace), parfois "--name=<value>".
	// Parsing par tokens : simple, et évite les pièges de regex (guillemets,
	// '=' dans la valeur, flag sans valeur qui avalerait le flag suivant).
	target := "--" + name
	for _, tok := range strings.Fields(cmdLine) {
		if strings.HasPrefix(tok, target+"=") {
			v := strings.TrimPrefix(tok, target+"=")
			return strings.Trim(v, `"`)
		}
		if tok == target {
			// La valeur est le token suivant — seulement si ce n'est pas un flag.
			rest := strings.Fields(cmdLine)
			for i, t := range rest {
				if t == target && i+1 < len(rest) && !strings.HasPrefix(rest[i+1], "--") {
					return strings.Trim(rest[i+1], `"`)
				}
			}
			return ""
		}
	}
	return ""
}

func atoi(s string) int {
	v, _ := strconv.Atoi(s)
	return v
}

// GetActiveWorkspaces scanne les processus language_server en cours d'exécution
// et extrait la liste unique des chemins de workspaces actifs (--workspace_id).
func GetActiveWorkspaces() []string {
	procs, err := getProcesses()
	if err != nil {
		return nil
	}
	seen := make(map[string]bool)
	var active []string
	for _, p := range procs {
		ws := extractArg(p.commandLine, "workspace_id")
		if ws != "" {
			// Normalisation du chemin (séparateurs, file:///)
			cleanWs := strings.TrimPrefix(ws, "file:///")
			cleanWs = strings.ReplaceAll(cleanWs, `\`, `/`)
			cleanWs = strings.TrimRight(cleanWs, "/")
			if !seen[cleanWs] {
				seen[cleanWs] = true
				active = append(active, cleanWs)
			}
		}
	}
	return active
}
