package discovery

import (
	"testing"
)

func TestExtractArg(t *testing.T) {
	cmdLine := `language_server.exe --subclient_type hub --csrf_token abc123xyz --extension_server_port 50999`

	if token := extractArg(cmdLine, "csrf_token"); token != "abc123xyz" {
		t.Errorf("Attendu token=abc123xyz, reçu=%s", token)
	}

	if subType := extractArg(cmdLine, "subclient_type"); subType != "hub" {
		t.Errorf("Attendu subclient_type=hub, reçu=%s", subType)
	}

	if portStr := extractArg(cmdLine, "extension_server_port"); portStr != "50999" {
		t.Errorf("Attendu port=50999, reçu=%s", portStr)
	}
}

func TestExtractJson(t *testing.T) {
	jsonStr := `{"ProcessId": 12345, "Name": "language_server.exe"}`

	if pid := extractJsonInt(jsonStr, "ProcessId"); pid != 12345 {
		t.Errorf("Attendu ProcessId=12345, reçu=%d", pid)
	}

	if name := extractJsonString(jsonStr, "Name"); name != "language_server.exe" {
		t.Errorf("Attendu Name=language_server.exe, reçu=%s", name)
	}
}
