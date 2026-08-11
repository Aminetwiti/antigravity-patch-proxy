package discovery

import (
	"bytes"
	"fmt"
	"net"
	"os/exec"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"time"
)

type LocalHarnessInfo struct {
	PID            int
	CSRFToken      string
	ExtensionPort  int
	ConnectRPCPort int
}

func Discover() (*LocalHarnessInfo, error) {
	cmdLine, pid, err := getProcessCommandLine()
	if err != nil {
		return nil, fmt.Errorf("localharness process not found: %w", err)
	}

	csrfToken := extractCSRFToken(cmdLine)
	extPort := extractExtensionPort(cmdLine)

	rpcPort := extPort
	for offset := 1; offset <= 20; offset++ {
		port := extPort + offset
		if checkTCPPort(port) {
			rpcPort = port
			break
		}
	}

	return &LocalHarnessInfo{
		PID:            pid,
		CSRFToken:      csrfToken,
		ExtensionPort:  extPort,
		ConnectRPCPort: rpcPort,
	}, nil
}

func getProcessCommandLine() (string, int, error) {
	if runtime.GOOS == "windows" {
		cmd := exec.Command("powershell", "-NoProfile", "-Command",
			"Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*language_server*' -or $_.CommandLine -like '*localharness*' } | Select-Object ProcessId, CommandLine | ConvertTo-Json")
		var out bytes.Buffer
		cmd.Stdout = &out
		if err := cmd.Run(); err != nil {
			return "", 0, err
		}
		str := strings.TrimSpace(out.String())
		if str == "" {
			return "", 0, fmt.Errorf("no process found")
		}

		pidRe := regexp.MustCompile(`"ProcessId":\s*(\d+)`)
		cmdRe := regexp.MustCompile(`"CommandLine":\s*"(.*?)"`)

		pidMatch := pidRe.FindStringSubmatch(str)
		cmdMatch := cmdRe.FindStringSubmatch(str)

		pid := 0
		if len(pidMatch) > 1 {
			pid, _ = strconv.Atoi(pidMatch[1])
		}
		cmdLine := ""
		if len(cmdMatch) > 1 {
			cmdLine = cmdMatch[1]
		}
		return cmdLine, pid, nil
	} else {
		cmd := exec.Command("sh", "-c", "ps aux | grep -E 'language_server|localharness' | grep -v grep")
		var out bytes.Buffer
		cmd.Stdout = &out
		if err := cmd.Run(); err != nil {
			return "", 0, err
		}
		lines := strings.Split(strings.TrimSpace(out.String()), "\n")
		if len(lines) == 0 || lines[0] == "" {
			return "", 0, fmt.Errorf("no process found")
		}
		fields := strings.Fields(lines[0])
		pid, _ := strconv.Atoi(fields[1])
		return lines[0], pid, nil
	}
}

func extractCSRFToken(cmdLine string) string {
	re := regexp.MustCompile(`--(?:csrf_token|api_key)=([^\s]+)`)
	match := re.FindStringSubmatch(cmdLine)
	if len(match) > 1 {
		return match[1]
	}
	return ""
}

func extractExtensionPort(cmdLine string) int {
	re := regexp.MustCompile(`--extensionPort=(\d+)`)
	match := re.FindStringSubmatch(cmdLine)
	if len(match) > 1 {
		p, err := strconv.Atoi(match[1])
		if err == nil {
			return p
		}
	}
	return 45000
}

func checkTCPPort(port int) bool {
	address := fmt.Sprintf("127.0.0.1:%d", port)
	conn, err := net.DialTimeout("tcp", address, 200*time.Millisecond)
	if err != nil {
		return false
	}
	conn.Close()
	return true
}
