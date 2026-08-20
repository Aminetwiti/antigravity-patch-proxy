package gateway

import (
	"strings"
	"testing"

	"github.com/gorilla/websocket"
)

func TestSettingsCustomizations_DiscoveredSkillsAndRules(t *testing.T) {
	skills := ListDiscoveredSkills()
	if len(skills) == 0 {
		t.Logf("no skills found on test host (normal in CI)")
	} else {
		t.Logf("found %d skills", len(skills))
		for _, s := range skills {
			if s.Name == "" {
				t.Fatalf("skill without name")
			}
		}
	}

	rules := ListDiscoveredRules()
	t.Logf("found %d rules", len(rules))

	bStatus := GetBrowserStatus()
	if !bStatus.Available || bStatus.Mode == "" {
		t.Fatalf("invalid browser status: %+v", bStatus)
	}
}

func TestWebSocket_AccountSkillsRulesRPC(t *testing.T) {
	ts, _ := newTestServerWithGW(nil)
	defer ts.Close()

	u := "ws" + strings.TrimPrefix(ts.URL, "http") + "/ws"
	conn, _, err := websocket.DefaultDialer.Dial(u, nil)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer conn.Close()

	// 1. get_account_info
	reqAcc := map[string]string{
		"type":      "get_account_info",
		"requestId": "req-acc-1",
	}
	if err := conn.WriteJSON(reqAcc); err != nil {
		t.Fatalf("write: %v", err)
	}
	var respAcc struct {
		Type      string                 `json:"type"`
		RequestID string                 `json:"requestId"`
		Data      map[string]interface{} `json:"data"`
	}
	if err := conn.ReadJSON(&respAcc); err != nil {
		t.Fatalf("read account: %v", err)
	}
	if respAcc.Data["email"] == nil || respAcc.Data["plan"] == nil {
		t.Fatalf("missing email or plan in account info: %+v", respAcc.Data)
	}

	// 2. list_skills
	reqSkills := map[string]string{
		"type":      "list_skills",
		"requestId": "req-skills-1",
	}
	if err := conn.WriteJSON(reqSkills); err != nil {
		t.Fatalf("write skills: %v", err)
	}
	var respSkills struct {
		Type      string                 `json:"type"`
		RequestID string                 `json:"requestId"`
		Data      map[string]interface{} `json:"data"`
	}
	if err := conn.ReadJSON(&respSkills); err != nil {
		t.Fatalf("read skills: %v", err)
	}
	if respSkills.Data["skills"] == nil {
		t.Fatalf("expected skills list in response")
	}

	// 3. get_browser_status
	reqBrowser := map[string]string{
		"type":      "get_browser_status",
		"requestId": "req-browser-1",
	}
	if err := conn.WriteJSON(reqBrowser); err != nil {
		t.Fatalf("write browser: %v", err)
	}
	var respBrowser struct {
		Type      string                 `json:"type"`
		RequestID string                 `json:"requestId"`
		Data      map[string]interface{} `json:"data"`
	}
	if err := conn.ReadJSON(&respBrowser); err != nil {
		t.Fatalf("read browser: %v", err)
	}
	if respBrowser.Data["mode"] == nil {
		t.Fatalf("expected browser status data")
	}
}
