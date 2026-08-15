package gateway

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

// HistoryMessage represents a parsed message to be sent to the mobile app
type HistoryMessage struct {
	ID          string `json:"id"`
	Sender      string `json:"sender"`
	Text        string `json:"text"`
	Thought     string `json:"thought,omitempty"`
	Timestamp   string `json:"timestamp"`
	IsStreaming bool   `json:"isStreaming"`
	IsError     bool   `json:"isError"`
}

var (
	wsMappingRe    = regexp.MustCompile(`(?i)([a-zA-Z]:(?:\\\\|/|\\)[^"\r\n\t<>]+?)\s*->`)
	wsFileURIRe    = regexp.MustCompile(`file:///[^\s"'\r\n]+`)
	convTitleRe    = regexp.MustCompile(`##\s*Conversation\s+([0-9a-fA-F-]+):\s*([^\r\n]+)`)
	rawWsMappingRe = regexp.MustCompile(`(?i)(?:\[|\b)([a-zA-Z]:(?:\\\\|[\\/])[^"\r\n\t<>]+?)(?:\]|\b)\s*->`)
	rawWsToolArgRe = regexp.MustCompile(`(?i)"(?:Cwd|cwd|DirectoryPath|SearchPath|AbsolutePath|TargetFile)":\s*"([a-zA-Z]:(?:\\\\|[\\/])[^"\r\n]+?)"`)
)

// findTranscriptPath searches for transcript.jsonl in antigravity and antigravity-ide brain paths.
func isSessionArchived(home, cascadeID string) bool {
	annoPath := filepath.Join(home, ".gemini", "antigravity", "annotations", cascadeID+".pbtxt")
	data, err := os.ReadFile(annoPath)
	if err != nil {
		return false
	}
	s := string(data)
	return strings.Contains(s, "archived: true") || strings.Contains(s, "archived:true")
}

func findTranscriptPath(cascadeID string) string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	candidates := []string{
		// 1. transcript.jsonl — layout principal (antigravity + IDE)
		filepath.Join(home, ".gemini", "antigravity", "brain", cascadeID, ".system_generated", "logs", "transcript.jsonl"),
		filepath.Join(home, ".gemini", "antigravity-ide", "brain", cascadeID, ".system_generated", "logs", "transcript.jsonl"),
		// 2. transcript_full.jsonl — repli quand seul le transcript complet existe
		filepath.Join(home, ".gemini", "antigravity", "brain", cascadeID, ".system_generated", "logs", "transcript_full.jsonl"),
		filepath.Join(home, ".gemini", "antigravity-ide", "brain", cascadeID, ".system_generated", "logs", "transcript_full.jsonl"),
		// 3. chunks/transcript — layout observé sur cette machine (IDE brain /
		//    AGY brain avec transcript découpé en chunks numérotés)
		filepath.Join(home, ".gemini", "antigravity", "brain", cascadeID, ".system_generated", "logs", "chunks", "transcript", "00000000.jsonl"),
		filepath.Join(home, ".gemini", "antigravity-ide", "brain", cascadeID, ".system_generated", "logs", "chunks", "transcript", "00000000.jsonl"),
	}
	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
}

// ListLocalSessions scans local brain directories for conversations when gRPC returns empty.
func ListLocalSessions() []map[string]interface{} {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil
	}

	officialProjs := ListOfficialProjects()
	officialPaths := make([]string, 0, len(officialProjs))
	officialNames := make([]string, 0, len(officialProjs))
	for _, p := range officialProjs {
		if p.Path != "" {
			officialPaths = append(officialPaths, strings.ToLower(p.Path))
		}
		if p.Name != "" {
			officialNames = append(officialNames, strings.ToLower(p.Name))
		}
	}

	roots := []string{
		filepath.Join(home, ".gemini", "antigravity", "brain"),
		filepath.Join(home, ".gemini", "antigravity-ide", "brain"),
	}

	type sessionItem struct {
		data      map[string]interface{}
		updatedAt time.Time
	}

	seen := make(map[string]bool)
	var items []sessionItem

	for _, root := range roots {
		entries, err := os.ReadDir(root)
		if err != nil {
			continue
		}
		for _, e := range entries {
			if !e.IsDir() {
				continue
			}
			cascadeID := e.Name()
			if seen[cascadeID] {
				continue
			}

			// Antigravity 2.0 : vérifier si la session est archivée dans ~/.gemini/antigravity/annotations/
			if isSessionArchived(home, cascadeID) {
				continue
			}

			transcriptPath := findTranscriptPath(cascadeID)
			if transcriptPath == "" {
				continue
			}

			seen[cascadeID] = true
			title, workspacePath, modTime := extractSessionMetadata(transcriptPath, cascadeID)

			// Exclure les subagents et prompts systèmes
			lowerTitle := strings.ToLower(strings.TrimSpace(title))
			if strings.HasPrefix(lowerTitle, "you are") ||
				strings.HasPrefix(lowerTitle, "en tant qu'") ||
				strings.HasPrefix(lowerTitle, "tu es ") ||
				strings.HasPrefix(lowerTitle, "system:") ||
				strings.HasPrefix(lowerTitle, "@[") ||
				strings.HasPrefix(lowerTitle, "analyse en profondeur") ||
				strings.HasPrefix(lowerTitle, "# mission") ||
				strings.HasPrefix(lowerTitle, "# role") ||
				strings.HasPrefix(lowerTitle, "# performance") {
				continue
			}

			if workspacePath == "" {
				workspacePath = extractWorkspace(root, cascadeID)
			}

			cleanWs := strings.ReplaceAll(workspacePath, `\`, `/`)
			cleanWs = strings.TrimRight(cleanWs, "/")
			lowerWs := strings.ToLower(cleanWs)

			// Si nous avons des projets officiels Antigravity 2.0, ne garder QUE les sessions
			// rattachées à un projet officiel
			matchedProjectName := ""
			matchedProjectPath := workspacePath
			if len(officialProjs) > 0 {
				for _, p := range officialProjs {
					pPath := strings.ToLower(p.Path)
					pName := strings.ToLower(p.Name)
					if (pPath != "" && (strings.Contains(lowerWs, pPath) || strings.Contains(pPath, lowerWs))) ||
						(pName != "" && (strings.Contains(lowerWs, pName) || strings.Contains(pName, lowerWs))) {
						matchedProjectName = p.Name
						matchedProjectPath = p.Path
						break
					}
				}
				if matchedProjectName == "" {
					continue
				}
			}

			// Nettoyage du titre si c'est un chemin brut
			if strings.HasPrefix(title, "C:\\") || strings.HasPrefix(title, "c:\\") || strings.HasPrefix(title, "file://") {
				if strings.Contains(cleanWs, "new 2") {
					title = "new 2"
				} else if strings.Contains(cleanWs, "new 3") {
					title = "new 3"
				} else if strings.Contains(cleanWs, "new 4") {
					title = "new 4"
				} else if strings.Contains(cleanWs, "new 5") || strings.Contains(cleanWs, "new5") {
					title = "new5"
				}
			}

			if matchedProjectName == "" {
				matchedProjectName = filepath.Base(cleanWs)
				if matchedProjectName == "" || matchedProjectName == "." || matchedProjectName == "/" || matchedProjectName == "\\" {
					matchedProjectName = "antigravity-workspace"
				}
			}

			sMap := map[string]interface{}{
				"cascadeId":     cascadeID,
				"title":         title,
				"workspace":     matchedProjectName,
				"workspacePath": matchedProjectPath,
				"projectId":     "p1",
				"status":        "idle",
				"updatedAt":     modTime.Format(time.RFC3339),
			}
			items = append(items, sessionItem{data: sMap, updatedAt: modTime})
		}
	}

	// Tri décroissant par date de mise à jour (plus récentes d'abord)
	sort.Slice(items, func(i, j int) bool {
		return items[i].updatedAt.After(items[j].updatedAt)
	})

	// Limite à 6 sessions récentes par projet pour correspondre exactement à l'affichage IDE 2.0
	projectCounts := make(map[string]int)
	sessions := make([]map[string]interface{}, 0, len(items))
	for _, it := range items {
		ws, _ := it.data["workspace"].(string)
		if projectCounts[ws] < 6 {
			sessions = append(sessions, it.data)
			projectCounts[ws]++
		}
	}
	return sessions
}

func extractSessionMetadata(transcriptPath, cascadeID string) (title string, workspacePath string, modTime time.Time) {
	stat, errStat := os.Stat(transcriptPath)
	if errStat != nil {
		return cascadeID, "", time.Now()
	}
	modTime = stat.ModTime()

	f, err := os.Open(transcriptPath)
	if err != nil {
		return cascadeID, "", modTime
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	buf := make([]byte, 0, 64*1024)
	scanner.Buffer(buf, 10*1024*1024)

	lineCount := 0
	for scanner.Scan() {
		lineCount++
		text := scanner.Text()

		// 1. Cherche le titre dans CONVERSATION_HISTORY
		if title == "" {
			if m := convTitleRe.FindStringSubmatch(text); m != nil && strings.EqualFold(m[1], cascadeID) {
				title = strings.TrimSpace(m[2])
			}
		}

		// 2. Cherche le workspace directement sur le texte brut
		if workspacePath == "" {
			if m := rawWsMappingRe.FindStringSubmatch(text); m != nil {
				cand := strings.ReplaceAll(m[1], `\\`, `/`)
				cand = strings.Trim(cand, "[]\"'` \t\r\n")
				if isDirectoryPath(cand) && !strings.Contains(cand, ".gemini") {
					workspacePath = cand
				}
			} else if m := rawWsToolArgRe.FindStringSubmatch(text); m != nil {
				cand := strings.ReplaceAll(m[1], `\\`, `/`)
				cand = strings.Trim(cand, "[]\"'` \t\r\n")
				if !strings.Contains(cand, ".gemini") && isDirectoryPath(cand) {
					if filepath.Ext(cand) != "" {
						cand = filepath.Dir(cand)
					}
					workspacePath = cand
				}
			}
		}

		var entry struct {
			Type      string `json:"type"`
			Content   string `json:"content"`
			ToolCalls []struct {
				Name string                 `json:"name"`
				Args map[string]interface{} `json:"args"`
			} `json:"tool_calls"`
		}

		if json.Unmarshal([]byte(text), &entry) == nil {
			// 2. Workspace depuis user_information / [URI] -> [Corpus]
			if workspacePath == "" && entry.Content != "" {
				if ws := parseWorkspaceFromTranscript(entry.Content); ws != "" {
					workspacePath = ws
				}
			}

			// Workspace depuis ToolCalls (Cwd, DirectoryPath, SearchPath, TargetFile, etc.)
			if workspacePath == "" {
				for _, tc := range entry.ToolCalls {
					for _, k := range []string{"Cwd", "cwd", "DirectoryPath", "SearchPath", "SearchDirectory"} {
						if v, ok := tc.Args[k].(string); ok {
							cand := strings.Trim(v, "[]\"'` \t\r\n")
							if isDirectoryPath(cand) && !strings.Contains(cand, ".gemini") {
								workspacePath = cand
								break
							}
						}
					}
					if workspacePath == "" {
						for _, k := range []string{"TargetFile", "AbsolutePath", "FilePath"} {
							if v, ok := tc.Args[k].(string); ok {
								cand := strings.Trim(v, "[]\"'` \t\r\n")
								if isDirectoryPath(cand) && !strings.Contains(cand, ".gemini") {
									vClean := strings.ReplaceAll(cand, `\`, `/`)
									vDir := filepath.Dir(vClean)
									if vDir != "" && vDir != "." && isDirectoryPath(vDir) {
										workspacePath = vDir
										break
									}
								}
							}
						}
					}
					if workspacePath != "" {
						break
					}
				}
			}

			// 3. Titre depuis USER_INPUT
			if title == "" && entry.Type == "USER_INPUT" && entry.Content != "" {
				clean := extractUserRequest(entry.Content)
				if !strings.HasPrefix(clean, "<identity>") && !strings.HasPrefix(clean, "<user_information>") && clean != "" {
					clean = strings.TrimSpace(clean)
					if len(clean) > 60 {
						clean = clean[:60] + "..."
					}
					title = clean
				}
			}
		}

		if title != "" && workspacePath != "" && lineCount >= 10 {
			break
		}
		if lineCount > 150 {
			break
		}
	}

	if title == "" {
		title = cascadeID
	}
	return title, workspacePath, modTime
}

func extractWorkspace(root, cascadeID string) string {
	metaPath := filepath.Join(root, cascadeID, "metadata.json")
	if data, err := os.ReadFile(metaPath); err == nil {
		var meta struct {
			Workspace     string `json:"workspace"`
			WorkspacePath string `json:"workspace_path"`
			CorpusName    string `json:"corpus_name"`
		}
		if err := json.Unmarshal(data, &meta); err == nil {
			if meta.Workspace != "" {
				return meta.Workspace
			}
			if meta.WorkspacePath != "" {
				return meta.WorkspacePath
			}
			if meta.CorpusName != "" {
				return meta.CorpusName
			}
		}
	}
	if wd, err := os.Getwd(); err == nil {
		return wd
	}
	return "antigravity-workspace"
}

func isDirectoryPath(p string) bool {
	p = strings.TrimSpace(p)
	if len(p) < 3 {
		return false
	}
	if (p[0] >= 'a' && p[0] <= 'z' || p[0] >= 'A' && p[0] <= 'Z') && p[1] == ':' && (p[2] == '\\' || p[2] == '/') {
		return true
	}
	if strings.HasPrefix(p, "/") || strings.HasPrefix(p, "file:///") {
		return true
	}
	return false
}

func parseWorkspaceFromTranscript(content string) string {
	if start := strings.Index(content, "<user_information>"); start != -1 {
		end := strings.Index(content, "</user_information>")
		if end > start {
			block := content[start+len("<user_information>") : end]
			for _, l := range strings.Split(block, "\n") {
				l = strings.TrimSpace(l)
				if idx := strings.Index(l, " -> "); idx > 0 {
					cand := strings.TrimSpace(l[:idx])
					cand = strings.Trim(cand, "[]\"'`")
					if isDirectoryPath(cand) {
						return cand
					}
				}
			}
		}
	}

	lines := strings.Split(content, "\n")
	for _, l := range lines {
		l = strings.TrimSpace(l)
		if idx := strings.Index(l, " -> "); idx > 0 {
			cand := strings.TrimSpace(l[:idx])
			cand = strings.Trim(cand, "[]\"'`")
			if isDirectoryPath(cand) {
				return cand
			}
		}
		if strings.HasPrefix(l, "Workspace:") || strings.HasPrefix(l, "Workspace Path:") {
			parts := strings.SplitN(l, ":", 2)
			if len(parts) == 2 {
				cand := strings.TrimSpace(parts[1])
				cand = strings.Trim(cand, "[]\"'`")
				if isDirectoryPath(cand) {
					return cand
				}
			}
		}
	}
	return ""
}

// transcriptEntry mirrors the JSONL shape written by the Antigravity brain.
// PLANNER_RESPONSE entries store the assistant's visible answer in `content`
// (final messages) OR in `thinking` (intermediate reasoning when the model
// continued with tool calls — `content` is then absent).
type transcriptEntry struct {
	StepIndex int    `json:"step_index"`
	Source    string `json:"source"`
	Type      string `json:"type"`
	CreatedAt string `json:"created_at"`
	Content   string `json:"content"`
	Thinking  string `json:"thinking"`
	Status    string `json:"status"`
	Error     string `json:"error"`
}

// parseTranscriptLine converts one JSONL line into a HistoryMessage, or
// returns nil for lines that should not appear in the mobile chat.
func parseTranscriptLine(line []byte) *HistoryMessage {
	var entry transcriptEntry
	if err := json.Unmarshal(line, &entry); err != nil {
		return nil
	}

	ts := "00:00"
	if t, err := time.Parse(time.RFC3339, entry.CreatedAt); err == nil {
		ts = fmt.Sprintf("%02d:%02d", t.Hour(), t.Minute())
	}
	msgID := fmt.Sprintf("h-%d", entry.StepIndex)

	if entry.Type == "USER_INPUT" {
		return &HistoryMessage{
			ID:        msgID,
			Sender:    "user",
			Text:      extractUserRequest(entry.Content),
			Timestamp: ts,
		}
	}

	if entry.Type == "TOOL_CALL" || entry.Type == "TOOL_RESULT" || entry.Source == "TOOL" {
		return nil // events d'outils : invisibles dans le chat mobile
	}

	// Réponse visible du modèle : PLANNER_RESPONSE place la réponse finale
	// dans `content`, et le raisonnement intermédiaire (quand le modèle a
	// enchaîné des appels d'outils) dans `thinking` — `content` est alors
	// absent. Les lignes vides (modèle n'a produit ni texte ni raisonnement,
	// ex. enchaînement d'outils purs) sont ignorées pour ne pas polluer le chat.
	if entry.Type == "PLANNER_RESPONSE" {
		text := entry.Content
		thought := entry.Thinking
		if text == "" && thought == "" {
			return nil
		}
		msg := &HistoryMessage{
			ID:        msgID,
			Sender:    "assistant",
			Text:      text,
			Thought:   thought,
			Timestamp: ts,
		}
		if entry.Error != "" {
			msg.IsError = true
			if msg.Text == "" {
				msg.Text = entry.Error
			}
		}
		return msg
	}

	return nil
}

// GetSessionHistory reads transcript.jsonl for the cascadeID and converts it to messages.
func GetSessionHistory(cascadeID string) ([]HistoryMessage, error) {
	transcriptPath := findTranscriptPath(cascadeID)
	if transcriptPath == "" {
		return []HistoryMessage{}, nil
	}
	f, err := os.Open(transcriptPath)
	if err != nil {
		// Log but don't fail, maybe the session has no transcript yet
		logJSON.Warn("transcript_not_found", "path", transcriptPath)
		return []HistoryMessage{}, nil
	}
	defer f.Close()

	var messages []HistoryMessage
	scanner := bufio.NewScanner(f)

	// Allow up to 10MB per line to handle very large text blocks in JSONL
	buf := make([]byte, 0, 64*1024)
	scanner.Buffer(buf, 10*1024*1024)

	for scanner.Scan() {
		if msg := parseTranscriptLine(scanner.Bytes()); msg != nil {
			messages = append(messages, *msg)
		}
	}

	if err := scanner.Err(); err != nil {
		logJSON.Error("scan_transcript_error", "err", err)
	}

	if messages == nil {
		messages = []HistoryMessage{}
	}
	return messages, nil
}

// transcriptCounts regroupe les compteurs d'activité extraits d'un transcript.
type transcriptCounts struct {
	subagents int
	files     int
	artifacts int
	uploads   int
	tasks     int
}

// countTranscriptActivity parcourt le transcript.jsonl d'une cascade et
// compte les événements réels (subagents, fichiers modifiés, artefacts,
// uploads, tâches de fond). Chaque type d'événement est dédupliqué par ID
// (les appels d'outils produisent plusieurs lignes pour le même fichier).
// Source unique de vérité pour get_context.
func countTranscriptActivity(cascadeID string) map[string]int {
	out := map[string]int{
		"subagents": 0,
		"files":     0,
		"artifacts": 0,
		"uploads":   0,
		"tasks":     0,
	}
	transcriptPath := findTranscriptPath(cascadeID)
	if transcriptPath == "" {
		return out
	}
	f, err := os.Open(transcriptPath)
	if err != nil {
		return out
	}
	defer f.Close()

	seenFiles := make(map[string]bool)
	seenArtifacts := make(map[string]bool)
	seenUploads := make(map[string]bool)
	seenTasks := make(map[string]bool)

	scanner := bufio.NewScanner(f)
	buf := make([]byte, 0, 64*1024)
	scanner.Buffer(buf, 10*1024*1024)

	for scanner.Scan() {
		var entry struct {
			Type    string `json:"type"`
			Source  string `json:"source"`
			Content string `json:"content"`
		}
		if err := json.Unmarshal(scanner.Bytes(), &entry); err != nil {
			continue
		}

		// Subagents : lignes de type TOOL_CALL dont le nom d'outil est un
		// lancement de sous-agent (invoke_subagent / dispatching-parallel-agents).
		if entry.Type == "TOOL_CALL" {
			var tc struct {
				Name string `json:"name"`
			}
			if json.Unmarshal([]byte(entry.Content), &tc) == nil {
				if tc.Name == "invoke_subagent" || tc.Name == "define_subagent" {
					out["subagents"]++
				}
			}
			continue
		}

		// Artefacts / uploads / fichiers : identifiés par les chemins
		// absolus présents dans le contenu de la ligne.
		for _, p := range filePathsIn(entry.Content) {
			switch {
			case isUploadPath(p):
				if !seenUploads[p] {
					seenUploads[p] = true
					out["uploads"]++
				}
			case strings.Contains(p, "artifact") || (strings.Contains(p, "brain/") || strings.Contains(p, "brain\\")) && strings.Contains(p, ".md"):
				if !seenArtifacts[p] {
					seenArtifacts[p] = true
					out["artifacts"]++
				}
			default:
				if !seenFiles[p] {
					seenFiles[p] = true
					out["files"]++
				}
			}
		}
		if strings.Contains(entry.Content, "background") && strings.Contains(entry.Content, "task") {
			key := entry.Content
			if !seenTasks[key] {
				seenTasks[key] = true
				out["tasks"]++
			}
		}
	}
	return out
}

// SubagentSummary représente un sous-agent découvert dans l'arbre d'exécution (DAG).
type SubagentSummary struct {
	ID          string `json:"id"`
	ParentID    string `json:"parentId"`
	TypeName    string `json:"typeName"`
	Role        string `json:"role"`
	Prompt      string `json:"prompt"`
	State       string `json:"state"` // running, idle, completed, errored
	CreatedAt   int64  `json:"createdAt"`
	LastMessage string `json:"lastMessage,omitempty"`
}

// ExtractSubagents parcourt le transcript d'une cascade et extrait la liste
// ordonnée des sous-agents invoqués (DAG / arborescence).
func ExtractSubagents(cascadeID string) []SubagentSummary {
	var results []SubagentSummary
	transcriptPath := findTranscriptPath(cascadeID)
	if transcriptPath == "" {
		return results
	}
	f, err := os.Open(transcriptPath)
	if err != nil {
		return results
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	buf := make([]byte, 0, 64*1024)
	scanner.Buffer(buf, 10*1024*1024)

	seen := make(map[string]int) // id -> index in results

	for scanner.Scan() {
		line := scanner.Bytes()
		var entry struct {
			Type      string          `json:"type"`
			Source    string          `json:"source"`
			Content   string          `json:"content"`
			ToolCalls json.RawMessage `json:"tool_calls"`
			StepIndex int64           `json:"step_index"`
			Timestamp int64           `json:"timestamp"`
		}
		if err := json.Unmarshal(line, &entry); err != nil {
			continue
		}

		// Détection dans tool_calls JSON array
		if len(entry.ToolCalls) > 0 {
			var calls []struct {
				Name      string                 `json:"name"`
				Arguments map[string]interface{} `json:"arguments"`
			}
			if json.Unmarshal(entry.ToolCalls, &calls) == nil {
				for _, c := range calls {
					if c.Name == "invoke_subagent" {
						if subList, ok := c.Arguments["Subagents"].([]interface{}); ok {
							for _, item := range subList {
								if smap, ok := item.(map[string]interface{}); ok {
									typeName, _ := smap["TypeName"].(string)
									role, _ := smap["Role"].(string)
									prompt, _ := smap["Prompt"].(string)
									subID, _ := smap["ConversationId"].(string)
									if subID == "" {
										subID = fmt.Sprintf("subagent-%s-%d", typeName, len(results)+1)
									}
									if idx, exists := seen[subID]; exists {
										results[idx].State = "running"
									} else {
										seen[subID] = len(results)
										results = append(results, SubagentSummary{
											ID:        subID,
											ParentID:  cascadeID,
											TypeName:  typeName,
											Role:      role,
											Prompt:    prompt,
											State:     "running",
											CreatedAt: entry.Timestamp,
										})
									}
								}
							}
						}
					}
				}
			}
		}

		// Détection dans Content texte si stringifié
		if strings.Contains(entry.Content, "invoke_subagent") || strings.Contains(entry.Content, "manage_subagents") {
			var tc struct {
				Name      string                 `json:"name"`
				Arguments map[string]interface{} `json:"arguments"`
			}
			if json.Unmarshal([]byte(entry.Content), &tc) == nil && tc.Name == "invoke_subagent" {
				if subList, ok := tc.Arguments["Subagents"].([]interface{}); ok {
					for _, item := range subList {
						if smap, ok := item.(map[string]interface{}); ok {
							typeName, _ := smap["TypeName"].(string)
							role, _ := smap["Role"].(string)
							prompt, _ := smap["Prompt"].(string)
							subID, _ := smap["ConversationId"].(string)
							if subID == "" {
								subID = fmt.Sprintf("subagent-%s-%d", typeName, len(results)+1)
							}
							if _, exists := seen[subID]; !exists {
								seen[subID] = len(results)
								results = append(results, SubagentSummary{
									ID:        subID,
									ParentID:  cascadeID,
									TypeName:  typeName,
									Role:      role,
									Prompt:    prompt,
									State:     "completed",
									CreatedAt: entry.Timestamp,
								})
							}
						}
					}
				}
			}
		}
	}
	return results
}


// filePathsIn extrait les chemins absolus (Windows, POSIX et file:///) d'un
// texte — ils identifient fichiers, artefacts et uploads dans les transcripts.
func filePathsIn(s string) []string {
	var out []string
	// Regex POSIX (/c:/…, /home/…, /Users/…) et Windows (C:\…, C:/…).
	re := regexp.MustCompile(`(?:file:///|/)?[A-Za-z]:/(?:[^"\s\\]|\\)+`)
	for _, m := range re.FindAllString(s, -1) {
		clean := strings.TrimRight(m, "\"',.;)")
		if len(clean) > 12 { // ignore les fragments trop courts
			out = append(out, clean)
		}
	}
	return out
}

// isUploadPath détecte un fichier téléversé par le mobile dans scratch/.
func isUploadPath(p string) bool {
	return strings.Contains(p, "scratch") && strings.Contains(p, "upload_")
}

func extractUserRequest(content string) string {
	startTag := "<USER_REQUEST>"
	endTag := "</USER_REQUEST>"

	startIdx := strings.Index(content, startTag)
	if startIdx >= 0 {
		endIdx := strings.Index(content, endTag)
		if endIdx > startIdx {
			return strings.TrimSpace(content[startIdx+len(startTag) : endIdx])
		}
	}
	return strings.TrimSpace(content)
}

// ProjectSummary represents an official Antigravity 2.0 project from ~/.gemini/config/projects/
type ProjectSummary struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	FolderURI string    `json:"folderUri"`
	Path      string    `json:"path"`
	UpdatedAt time.Time `json:"updatedAt"`
}

// ListOfficialProjects reads registered projects from ~/.gemini/config/projects/
func ListOfficialProjects() []ProjectSummary {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil
	}
	projectsDir := filepath.Join(home, ".gemini", "config", "projects")
	entries, err := os.ReadDir(projectsDir)
	if err != nil {
		return nil
	}

	var list []ProjectSummary
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".json") || e.Name() == "outside-of-project.json" {
			continue
		}
		filePath := filepath.Join(projectsDir, e.Name())
		data, err := os.ReadFile(filePath)
		if err != nil {
			continue
		}

		var parsed struct {
			ID               string `json:"id"`
			Name             string `json:"name"`
			UpdatedAt        string `json:"updatedAt"`
			ProjectResources struct {
				Resources []struct {
					GitFolder struct {
						FolderURI string `json:"folderUri"`
					} `json:"gitFolder"`
				} `json:"resources"`
			} `json:"projectResources"`
		}
		if err := json.Unmarshal(data, &parsed); err != nil {
			continue
		}

		folderURI := ""
		if len(parsed.ProjectResources.Resources) > 0 {
			folderURI = parsed.ProjectResources.Resources[0].GitFolder.FolderURI
		}

		// Convert folderUri (file:///c%3A/...) to normalized path
		path := folderURI
		if strings.HasPrefix(path, "file:///") {
			path = strings.TrimPrefix(path, "file:///")
			path = strings.ReplaceAll(path, "%3A", ":")
			path = strings.ReplaceAll(path, "%20", " ")
			path = strings.ReplaceAll(path, `\`, `/`)
			path = strings.TrimRight(path, "/")
		}

		var updatedTime time.Time
		if parsed.UpdatedAt != "" {
			updatedTime, _ = time.Parse(time.RFC3339, parsed.UpdatedAt)
		}

		name := parsed.Name
		if name == "" && path != "" {
			name = filepath.Base(path)
		}
		if name == "" {
			name = parsed.ID
		}

		list = append(list, ProjectSummary{
			ID:        parsed.ID,
			Name:      name,
			FolderURI: folderURI,
			Path:      path,
			UpdatedAt: updatedTime,
		})
	}

	// Tri par date de mise à jour décroissante
	sort.Slice(list, func(i, j int) bool {
		return list[i].UpdatedAt.After(list[j].UpdatedAt)
	})

	return list
}

// GetUniqueWorkspaces returns the list of unique workspace names discovered on the machine.
func GetUniqueWorkspaces() []string {
	projs := ListOfficialProjects()
	if len(projs) > 0 {
		var names []string
		for _, p := range projs {
			names = append(names, p.Name)
			if len(names) >= 8 {
				break
			}
		}
		return names
	}

	sessions := ListLocalSessions()
	seen := make(map[string]bool)
	var list []string
	for _, s := range sessions {
		if ws, ok := s["workspace"].(string); ok && ws != "" && !seen[ws] {
			seen[ws] = true
			list = append(list, ws)
			if len(list) >= 8 {
				break
			}
		}
	}
	return list
}
