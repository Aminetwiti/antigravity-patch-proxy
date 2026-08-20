package gateway

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

// AccountInfo représente les détails du compte Antigravity Desktop / Google AI.
type AccountInfo struct {
	Email           string                 `json:"email"`
	Plan            string                 `json:"plan"`
	PlanDisplayName string                 `json:"planDisplayName"`
	Telemetry       bool                   `json:"telemetryEnabled"`
	MarketingEmails bool                   `json:"marketingEmails"`
	Quotas          map[string]interface{} `json:"quotas,omitempty"`
}

// DiscoveredSkill représente un skill Antigravity (builtin ou custom).
type DiscoveredSkill struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	Path        string `json:"path"`
	Category    string `json:"category"` // "builtin" | "custom"
	Enabled     bool   `json:"enabled"`
}

// DiscoveredRule représente une règle globale ou workspace.
type DiscoveredRule struct {
	Name    string `json:"name"`
	Path    string `json:"path"`
	Scope   string `json:"scope"` // "global" | "workspace"
	Content string `json:"content"`
}

// BrowserStatus représente l'état du navigateur headless / CDP.
type BrowserStatus struct {
	Available        bool     `json:"available"`
	Mode             string   `json:"mode"`
	Paired           bool     `json:"paired"`
	AutoCapture      bool     `json:"autoCapture"`
	ScreenshotsCount int      `json:"screenshotsCount"`
	RecentCaptures   []string `json:"recentCaptures"`
}

var (
	accountMu               sync.RWMutex
	accountTelemetryEnabled = true
	accountMarketingEmails  = false
)

// GetAccountInfo retourne les informations de compte avec quotas temps réel.
func (s *Server) GetAccountInfo() AccountInfo {
	accountMu.RLock()
	tel := accountTelemetryEnabled
	mkt := accountMarketingEmails
	accountMu.RUnlock()

	info := AccountInfo{
		Email:           "lesjardindelavie@gmail.com",
		Plan:            "Google AI Pro",
		PlanDisplayName: "Google AI Pro Plan",
		Telemetry:       tel,
		MarketingEmails: mkt,
	}

	if s.RPCClient != nil {
		if raw, err := s.RPCClient.RetrieveUserQuotaSummary(); err == nil && len(raw) > 0 {
			if qData, ok := s.buildQuotaData(raw); ok {
				info.Quotas = qData
			}
		}
	}

	return info
}

// SetAccountPreferences enregistre les préférences de télémétrie / marketing.
func SetAccountPreferences(telemetry, marketing bool) {
	accountMu.Lock()
	defer accountMu.Unlock()
	accountTelemetryEnabled = telemetry
	accountMarketingEmails = marketing
}

// ListDiscoveredSkills recherche les skills dans ~/.gemini/antigravity/builtin/skills et ~/.gemini/config/skills.
func ListDiscoveredSkills() []DiscoveredSkill {
	home, err := os.UserHomeDir()
	if err != nil {
		return []DiscoveredSkill{}
	}

	var skills []DiscoveredSkill
	seen := make(map[string]bool)

	dirs := []struct {
		path     string
		category string
	}{
		{filepath.Join(home, ".gemini", "antigravity", "builtin", "skills"), "builtin"},
		{filepath.Join(home, ".gemini", "config", "skills"), "custom"},
	}

	for _, d := range dirs {
		entries, err := os.ReadDir(d.path)
		if err != nil {
			continue
		}
		for _, e := range entries {
			if !e.IsDir() {
				continue
			}
			skillDir := filepath.Join(d.path, e.Name())
			skillFile := filepath.Join(skillDir, "SKILL.md")
			if _, err := os.Stat(skillFile); err == nil {
				name, desc := parseSkillMD(skillFile, e.Name())
				if !seen[name] {
					seen[name] = true
					skills = append(skills, DiscoveredSkill{
						Name:        name,
						Description: desc,
						Path:        skillFile,
						Category:    d.category,
						Enabled:     true,
					})
				}
			}
		}
	}

	return skills
}

// parseSkillMD extrait le frontmatter (name / description) de SKILL.md.
func parseSkillMD(path, fallbackName string) (string, string) {
	f, err := os.Open(path)
	if err != nil {
		return fallbackName, ""
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	inFrontmatter := false
	name := fallbackName
	desc := ""

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "---" {
			if !inFrontmatter {
				inFrontmatter = true
				continue
			} else {
				break
			}
		}
		if inFrontmatter {
			if strings.HasPrefix(line, "name:") {
				name = strings.TrimSpace(strings.TrimPrefix(line, "name:"))
				name = strings.Trim(name, `"'`)
			} else if strings.HasPrefix(line, "description:") {
				desc = strings.TrimSpace(strings.TrimPrefix(line, "description:"))
				desc = strings.Trim(desc, `"'`)
			}
		}
	}

	return name, desc
}

// ListDiscoveredRules lit les règles globales dans ~/.gemini/antigravity/rules.
func ListDiscoveredRules() []DiscoveredRule {
	home, err := os.UserHomeDir()
	if err != nil {
		return []DiscoveredRule{}
	}

	var rules []DiscoveredRule
	rulesDir := filepath.Join(home, ".gemini", "antigravity", "rules")
	entries, err := os.ReadDir(rulesDir)
	if err == nil {
		for _, e := range entries {
			if e.IsDir() {
				continue
			}
			p := filepath.Join(rulesDir, e.Name())
			data, err := os.ReadFile(p)
			if err == nil {
				rules = append(rules, DiscoveredRule{
					Name:    e.Name(),
					Path:    p,
					Scope:   "global",
					Content: string(data),
				})
			}
		}
	}

	return rules
}

// GetBrowserStatus retourne l'état du navigateur headless CDP.
func GetBrowserStatus() BrowserStatus {
	return BrowserStatus{
		Available:        true,
		Mode:             "headless_cdp",
		Paired:           false,
		AutoCapture:      true,
		ScreenshotsCount: 0,
		RecentCaptures:   []string{},
	}
}
