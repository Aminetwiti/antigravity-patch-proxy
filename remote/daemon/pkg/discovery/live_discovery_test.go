package discovery

import (
	"fmt"
	"testing"
)

func TestLiveDiscovery(t *testing.T) {
	info, err := Discover()
	if err != nil {
		t.Logf("Discovery failed (maybe IDE not open?): %v", err)
		return
	}
	fmt.Printf("\n=== DISCOVERY SUCCESS ===\n")
	fmt.Printf("PID: %d\n", info.PID)
	fmt.Printf("ProcessName: %s\n", info.ProcessName)
	fmt.Printf("ConnectRPCPort: %d\n", info.ConnectRPCPort)
	fmt.Printf("SubclientType: %s\n", info.SubclientType)
	fmt.Printf("WorkspaceID: %s\n", info.WorkspaceID)
	token := info.ExtensionCSRF
	if token == "" {
		token = info.CSRFToken
	}
	if len(token) > 8 {
		fmt.Printf("CSRF Token: %s... (length %d)\n", token[:8], len(token))
	} else {
		fmt.Printf("CSRF Token: %s\n", token)
	}
	fmt.Printf("=========================\n\n")
}
