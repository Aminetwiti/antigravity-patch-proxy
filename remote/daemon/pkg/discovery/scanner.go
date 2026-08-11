package discovery

import (
	"bytes"
	"fmt"
	"io"
	"net"
	"net/http"
	"os/exec"
	"regexp"
	"runtime"
	"strconv"
	"strings"
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

	// L'instance qui expose le service RPC est le hub standalone
	// (--subclient_type hub, --api_server_url http://localhost:50999).
	// Les instances IDE (--subclient_type ide) répondent 404 sur ce service.
	var pick *procEntry
	for i := range procs {
		if strings.Contains(procs[i].commandLine, "--subclient_type hub") {
			pick = &procs[i]
			break
		}
	}
	if pick == nil {
		pick = &procs[0]
	}

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

	// Trouver les ports à tester
	candidates := candidatePorts(info, pick)
	if len(candidates) == 0 {
		return nil, fmt.Errorf("aucun port candidat pour PID %d", pick.pid)
	}

	// Prober chaque port avec Heartbeat (seul critère fiable)
	token := info.ExtensionCSRF
	for _, port := range candidates {
		if probeService(port, token) {
			info.ConnectRPCPort = port
			return info, nil
		}
	}
	return nil, fmt.Errorf("aucun port ne répond au service RPC (testé %d candidats)", len(candidates))
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
func probeService(port int, csrfToken string) bool {
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

func checkTCPPort(port int) bool {
	conn, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), 200*time.Millisecond)
	if err != nil {
		return false
	}
	conn.Close()
	return true
}

func atoi(s string) int {
	v, _ := strconv.Atoi(s)
	return v
}
