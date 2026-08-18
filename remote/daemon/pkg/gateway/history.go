package gateway

import (
	"bufio"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/antigravity/remote-daemon/pkg/connectrpc"
	_ "modernc.org/sqlite"
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
	wsMappingRe     = regexp.MustCompile(`(?i)([a-zA-Z]:(?:\\\\|/|\\)[^"\r\n\t<>]+?)\s*->`)
	wsFileURIRe     = regexp.MustCompile(`file:///[^\s"'\r\n]+`)
	convTitleRe     = regexp.MustCompile(`##\s*Conversation\s+([0-9a-fA-F-]+):\s*([^"\r\n\\]+?)(?:\\[nrt]|\r|\n|"|$)`)
	userObjectiveRe = regexp.MustCompile(`(?i)###\s*USER Objective:\s*([^"\r\n\\]+?)(?:\\[nrt]|\r|\n|"|$)`)
	rawWsMappingRe  = regexp.MustCompile(`(?i)(?:\[|\b)([a-zA-Z]:(?:\\\\|[\\/])[^"\r\n\t<>]+?)(?:\]|\b)\s*->`)
	rawWsToolArgRe  = regexp.MustCompile(`(?i)"(?:filePath|file_path|targetFile|TargetFile|AbsolutePath|DirectoryPath|Cwd)"\s*:\s*"([a-zA-Z]:(?:\\\\|[\\/])[^"\r\n\t<>]+?)"`)
	globalConvTitles = make(map[string]string)
	convTitlesMu     sync.RWMutex

	systemMessageBlockRe   = regexp.MustCompile(`(?s)<SYSTEM_MESSAGE>.*?</SYSTEM_MESSAGE>`)
	systemPromptBlockRe    = regexp.MustCompile(`(?s)<SYSTEM_PROMPT>.*?</SYSTEM_PROMPT>`)
	additionalMetaBlockRe  = regexp.MustCompile(`(?s)<ADDITIONAL_METADATA>.*?</ADDITIONAL_METADATA>`)
	userSettingsBlockRe    = regexp.MustCompile(`(?s)<USER_SETTINGS_CHANGE>.*?</USER_SETTINGS_CHANGE>`)
	systemGeneratedBlockRe = regexp.MustCompile(`(?s)<system_generated>.*?</system_generated>`)
	contextBlockRe         = regexp.MustCompile(`(?s)<context.*?>.*?</context>`)
	bgMessageBlockRe       = regexp.MustCompile(`(?s)\[Message\]\s*timestamp=[^\r\n]+\r?\n+sender=[^\r\n]+\r?\n+priority=[^\r\n]+\r?\n+content=[^\r\n]+`)
	systemNoticeRe         = regexp.MustCompile(`(?s)The following is a <SYSTEM_MESSAGE> not actually sent by the user.*?(?:pay attention to\.|$)`)
)

// stepTypeUser/stepTypeAssistant/stepTypeTitle sont les step_type observés
// dans les conversations Antigravity 2.0 stockées en SQLite (~/.gemini/
// antigravity/conversations/<cascadeID>.db, table `steps`).
const (
	stepTypeUser      = 14 // message utilisateur
	stepTypeAssistant = 15 // réponse du modèle
	stepTypeTitle     = 23 // mise à jour du titre de conversation
)

// normalizeWorkspace normalise les chemins et URIs de workspace (décote URL %20, %3A, slashes)
func normalizeWorkspace(uri string) string {
	if uri == "" {
		return ""
	}
	if decoded, err := url.PathUnescape(uri); err == nil {
		uri = decoded
	}
	if decoded, err := url.QueryUnescape(uri); err == nil {
		uri = decoded
	}
	uri = strings.TrimPrefix(uri, "file:///")
	uri = strings.TrimPrefix(uri, "file://")
	uri = strings.ReplaceAll(uri, `\`, `/`)
	uri = strings.TrimRight(uri, "/")
	return uri
}

// isSubagentTitle détecte si un titre ou prompt correspond à un sous-agent interne
func isSubagentTitle(title string) bool {
	lowerTitle := strings.ToLower(strings.TrimSpace(title))
	return strings.HasPrefix(lowerTitle, "you are") ||
		strings.HasPrefix(lowerTitle, "en tant qu'") ||
		strings.HasPrefix(lowerTitle, "tu es ") ||
		strings.HasPrefix(lowerTitle, "system:") ||
		strings.HasPrefix(lowerTitle, "@[") ||
		strings.HasPrefix(lowerTitle, "analyse en profondeur") ||
		strings.HasPrefix(lowerTitle, "# mission") ||
		strings.HasPrefix(lowerTitle, "# role") ||
		strings.HasPrefix(lowerTitle, "# performance") ||
		strings.HasPrefix(lowerTitle, "analyzing stream delta") ||
		strings.HasPrefix(lowerTitle, "subagent") ||
		strings.Contains(lowerTitle, "subagent-") ||
		strings.Contains(lowerTitle, "subagent_")
}

// isSessionArchived vérifie si la session est archivée dans ~/.gemini/antigravity/annotations/<cascadeID>.pbtxt
func isSessionArchived(home, cascadeID string) bool {
	if cascadeID == "" {
		return false
	}
	annoPath := filepath.Join(home, ".gemini", "antigravity", "annotations", cascadeID+".pbtxt")
	data, err := os.ReadFile(annoPath)
	if err != nil {
		return false
	}
	s := strings.ToLower(string(data))
	if strings.Contains(s, "archived: false") || strings.Contains(s, "archived:false") {
		return false
	}
	return strings.Contains(s, "archived: true") || strings.Contains(s, "archived:true")
}

// archiveSessionOnDisk écrit ou met à jour le statut archivé dans annotations/<cascadeID>.pbtxt
func archiveSessionOnDisk(home, cascadeID string, archive bool) error {
	if cascadeID == "" {
		return fmt.Errorf("cascadeId requis")
	}
	annoDir := filepath.Join(home, ".gemini", "antigravity", "annotations")
	_ = os.MkdirAll(annoDir, 0o755)
	annoPath := filepath.Join(annoDir, cascadeID+".pbtxt")

	nowSec := time.Now().Unix()
	nowNano := time.Now().Nanosecond()

	data, err := os.ReadFile(annoPath)
	if err != nil {
		if !archive {
			return nil
		}
		content := fmt.Sprintf("archived:true archival_status_timestamp:{seconds:%d nanos:%d} last_user_view_time:{seconds:%d nanos:%d}\n",
			nowSec, nowNano, nowSec, nowNano)
		return os.WriteFile(annoPath, []byte(content), 0o644)
	}

	s := string(data)
	reArch := regexp.MustCompile(`(?i)archived:\s*(true|false)`)
	s = reArch.ReplaceAllString(s, "")
	s = strings.TrimSpace(s)

	if archive {
		s = fmt.Sprintf("archived:true archival_status_timestamp:{seconds:%d nanos:%d} %s", nowSec, nowNano, s)
	} else {
		s = fmt.Sprintf("archived:false %s", s)
	}
	s = strings.TrimSpace(s) + "\n"
	return os.WriteFile(annoPath, []byte(s), 0o644)
}

// deleteSessionFromDisk supprime les artefacts résiduels d'une session sur disque (.pbtxt, .db, brain/)
func deleteSessionFromDisk(home, cascadeID string) error {
	if cascadeID == "" {
		return nil
	}
	annoPath := filepath.Join(home, ".gemini", "antigravity", "annotations", cascadeID+".pbtxt")
	_ = os.Remove(annoPath)

	dbPath := filepath.Join(home, ".gemini", "antigravity", "conversations", cascadeID+".db")
	_ = os.Remove(dbPath)

	brainDir := filepath.Join(home, ".gemini", "antigravity", "brain", cascadeID)
	_ = os.RemoveAll(brainDir)

	ideBrainDir := filepath.Join(home, ".gemini", "antigravity-ide", "brain", cascadeID)
	_ = os.RemoveAll(ideBrainDir)

	return nil
}

func findTranscriptPath(cascadeID string) string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	candidates := []string{
		// 1. transcript.jsonl ÔÇö layout principal (antigravity + IDE)
		filepath.Join(home, ".gemini", "antigravity", "brain", cascadeID, ".system_generated", "logs", "transcript.jsonl"),
		filepath.Join(home, ".gemini", "antigravity-ide", "brain", cascadeID, ".system_generated", "logs", "transcript.jsonl"),
		// 2. transcript_full.jsonl ÔÇö repli quand seul le transcript complet existe
		filepath.Join(home, ".gemini", "antigravity", "brain", cascadeID, ".system_generated", "logs", "transcript_full.jsonl"),
		filepath.Join(home, ".gemini", "antigravity-ide", "brain", cascadeID, ".system_generated", "logs", "transcript_full.jsonl"),
		// 3. chunks/transcript ÔÇö layout observ├® sur cette machine (IDE brain /
		//    AGY brain avec transcript d├®coup├® en chunks num├®rot├®s)
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

// findBrainDir returns the active brain directory for a cascade ID.
func findBrainDir(cascadeID string) string {
	if cascadeID == "" {
		return ""
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	candidates := []string{
		filepath.Join(home, ".gemini", "antigravity", "brain", cascadeID),
		filepath.Join(home, ".gemini", "antigravity-ide", "brain", cascadeID),
	}
	for _, p := range candidates {
		if fi, err := os.Stat(p); err == nil && fi.IsDir() {
			return p
		}
	}
	return ""
}

// ListSessionArtifacts scans the session brain directory and returns all markdown artifacts.
func ListSessionArtifacts(cascadeID string) []map[string]interface{} {
	var results []map[string]interface{}
	brainDir := findBrainDir(cascadeID)
	if brainDir == "" {
		return results
	}
	entries, err := os.ReadDir(brainDir)
	if err != nil {
		return results
	}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		if strings.HasSuffix(strings.ToLower(name), ".md") {
			fullPath := filepath.Join(brainDir, name)
			info, _ := entry.Info()
			var size int64
			var modTime int64
			if info != nil {
				size = info.Size()
				modTime = info.ModTime().UnixMilli()
			}
			results = append(results, map[string]interface{}{
				"name":    name,
				"path":    filepath.ToSlash(fullPath),
				"size":    size,
				"modTime": modTime,
			})
		}
	}
	return results
}

// ListSessionUploads scans scratch and user_uploaded directories for images, PDFs, media.
func ListSessionUploads(cascadeID string) []map[string]interface{} {
	var results []map[string]interface{}
	brainDir := findBrainDir(cascadeID)
	if brainDir == "" {
		return results
	}
	seen := make(map[string]bool)
	for _, sub := range []string{"scratch", ".user_uploaded", ""} {
		subDir := filepath.Join(brainDir, sub)
		entries, err := os.ReadDir(subDir)
		if err != nil {
			continue
		}
		for _, entry := range entries {
			if entry.IsDir() {
				continue
			}
			name := entry.Name()
			if seen[name] {
				continue
			}
			lower := strings.ToLower(name)
			if strings.HasSuffix(lower, ".png") ||
				strings.HasSuffix(lower, ".jpg") ||
				strings.HasSuffix(lower, ".jpeg") ||
				strings.HasSuffix(lower, ".gif") ||
				strings.HasSuffix(lower, ".webp") ||
				strings.HasSuffix(lower, ".pdf") ||
				strings.HasSuffix(lower, ".mp4") {
				seen[name] = true
				fullPath := filepath.Join(subDir, name)
				info, _ := entry.Info()
				var size int64
				if info != nil {
					size = info.Size()
				}
				results = append(results, map[string]interface{}{
					"name": name,
					"path": filepath.ToSlash(fullPath),
					"size": size,
				})
			}
		}
	}
	return results
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

			// Antigravity 2.0 : v├®rifier si la session est archiv├®e dans ~/.gemini/antigravity/annotations/
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
			if isSubagentTitle(title) {
				continue
			}

			if workspacePath == "" {
				workspacePath = extractWorkspace(root, cascadeID)
			}

			cleanWs := normalizeWorkspace(workspacePath)
			lowerWs := strings.ToLower(cleanWs)

			// Si nous avons des projets officiels Antigravity 2.0, ne garder QUE les sessions
			// rattachées à un projet officiel
			matchedProjectName := ""
			matchedProjectPath := workspacePath
			matchedProjectID := ""
			if len(officialProjs) > 0 {
				for _, p := range officialProjs {
					pPath := strings.ToLower(normalizeWorkspace(p.Path))
					pName := strings.ToLower(p.Name)
					if (pPath != "" && (strings.Contains(lowerWs, pPath) || strings.Contains(pPath, lowerWs))) ||
						(pName != "" && (strings.Contains(lowerWs, pName) || strings.Contains(pName, lowerWs))) {
						matchedProjectName = p.Name
						matchedProjectPath = p.Path
						matchedProjectID = p.ID
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
				"projectId":     matchedProjectID,
				"status":        "idle",
				"updatedAt":     modTime.Format(time.RFC3339),
			}
			items = append(items, sessionItem{data: sMap, updatedAt: modTime})
		}
	}

	// 2ème passe : réassigner les titres officiels découverts globalement dans les résumés
	convTitlesMu.RLock()
	for _, it := range items {
		cid, _ := it.data["cascadeId"].(string)
		if offTitle, ok := globalConvTitles[strings.ToLower(cid)]; ok && offTitle != "" {
			it.data["title"] = offTitle
		}
	}
	convTitlesMu.RUnlock()

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

	// Vérifie si le titre officiel est déjà indexé globalement
	convTitlesMu.RLock()
	if off, ok := globalConvTitles[strings.ToLower(cascadeID)]; ok && off != "" {
		title = off
	}
	convTitlesMu.RUnlock()

	scanner := bufio.NewScanner(f)
	hBuf := AcquireHistoryBuffer()
	defer ReleaseHistoryBuffer(hBuf)
	scanner.Buffer(*hBuf, len(*hBuf))

	lineCount := 0
	hasOfficialTitle := false
	if title != "" && title != cascadeID {
		hasOfficialTitle = true
	}

	for scanner.Scan() {
		lineCount++
		text := scanner.Text()

		// 1. Indexe tous les titres de conversations trouvés dans les conversation_summaries
		if matches := convTitleRe.FindAllStringSubmatch(text, -1); len(matches) > 0 {
			convTitlesMu.Lock()
			for _, m := range matches {
				if len(m) >= 3 && m[1] != "" && m[2] != "" {
					cleanTitle := strings.TrimSpace(m[2])
					cleanTitle = strings.Split(cleanTitle, "\\n")[0]
					cleanTitle = strings.Split(cleanTitle, "\n")[0]
					cleanTitle = strings.Trim(cleanTitle, "\"': \t\r\n")
					if cleanTitle != "" {
						globalConvTitles[strings.ToLower(m[1])] = cleanTitle
						if strings.EqualFold(m[1], cascadeID) {
							title = cleanTitle
							hasOfficialTitle = true
						}
					}
				}
			}
			convTitlesMu.Unlock()
		}

		// 2. Extrait l'objectif utilisateur officiel (### USER Objective:)
		if m := userObjectiveRe.FindStringSubmatch(text); m != nil {
			cand := strings.TrimSpace(m[1])
			cand = strings.Split(cand, "\\n")[0]
			cand = strings.Split(cand, "\n")[0]
			cand = strings.Trim(cand, "\"': \t\r\n")
			if cand != "" && !strings.EqualFold(cand, "None") {
				title = cand
				hasOfficialTitle = true
				convTitlesMu.Lock()
				globalConvTitles[strings.ToLower(cascadeID)] = cand
				convTitlesMu.Unlock()
			}
		}

		if !hasOfficialTitle {
			convTitlesMu.RLock()
			if off, ok := globalConvTitles[strings.ToLower(cascadeID)]; ok && off != "" {
				title = off
				hasOfficialTitle = true
			}
			convTitlesMu.RUnlock()
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
					title = cleanPromptTitle(clean)
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
// continued with tool calls ÔÇö `content` is then absent).
type transcriptEntry struct {
	StepIndex int             `json:"step_index"`
	Source    string          `json:"source"`
	Type      string          `json:"type"`
	CreatedAt string          `json:"created_at"`
	Content   string          `json:"content"`
	Thinking  string          `json:"thinking"`
	Status    string          `json:"status"`
	Error     string          `json:"error"`
	ToolCalls json.RawMessage `json:"tool_calls"`
}

func formatToolCallStep(name string, argsRaw json.RawMessage) string {
	lowerName := strings.ToLower(name)
	if lowerName == "ask_question" || lowerName == "ask_user" {
		return ""
	}
	arg := extractCmdFromArgs(argsRaw)
	if arg == "" && len(argsRaw) > 0 {
		var argMap map[string]interface{}
		if json.Unmarshal(argsRaw, &argMap) == nil {
			for _, k := range []string{"targetFile", "TargetFile", "filePath", "file_path", "path", "AbsolutePath", "DirectoryPath", "query", "Query", "pattern", "command", "CommandLine", "command_line", "description", "toolAction"} {
				if v, ok := argMap[k]; ok {
					if s, okS := v.(string); okS && s != "" {
						arg = s
						break
					}
				}
			}
		}
	}
	if strings.Contains(arg, "/") || strings.Contains(arg, "\\") {
		cleanBase := filepath.Base(arg)
		if cleanBase != "." && cleanBase != "" && cleanBase != "/" && cleanBase != "\\" {
			arg = cleanBase
		}
	}
	if len(arg) > 70 {
		arg = arg[:67] + "…"
	}

	switch {
	case strings.Contains(lowerName, "run_command") || strings.Contains(lowerName, "command") || strings.Contains(lowerName, "terminal") || strings.Contains(lowerName, "bash"):
		if arg != "" {
			return "Ran " + arg
		}
		return "Ran command"
	case strings.Contains(lowerName, "write_to_file") || strings.Contains(lowerName, "replace_file_content") || strings.Contains(lowerName, "edit_file"):
		if arg != "" {
			return "Edited " + arg
		}
		return "Edited file"
	case strings.Contains(lowerName, "view_file") || strings.Contains(lowerName, "read_file"):
		if arg != "" {
			return "Viewed " + arg
		}
		return "Viewed file"
	case strings.Contains(lowerName, "grep") || strings.Contains(lowerName, "search") || strings.Contains(lowerName, "find_by_name") || strings.Contains(lowerName, "list_dir") || strings.Contains(lowerName, "list_files"):
		if arg != "" {
			return "Explored " + arg
		}
		return "Explored 1 file"
	case strings.Contains(lowerName, "invoke_subagent") || strings.Contains(lowerName, "define_subagent") || strings.Contains(lowerName, "subagent"):
		if arg != "" {
			return "Subagent " + arg
		}
		return "Spawned subagent"
	case strings.Contains(lowerName, "send_message"):
		if arg != "" {
			return "Sent to " + arg
		}
		return "Sent message"
	case strings.Contains(lowerName, "generate_image"):
		if arg != "" {
			return "Generated " + arg
		}
		return "Generated image"
	case strings.Contains(lowerName, "schedule"):
		if arg != "" {
			return "Scheduled " + arg
		}
		return "Scheduled task"
	case strings.Contains(lowerName, "browse") || strings.Contains(lowerName, "read_url"):
		if arg != "" {
			return "Browsed " + arg
		}
		return "Browsed web"
	default:
		cleanTool := strings.ReplaceAll(name, "_", " ")
		if arg != "" {
			return fmt.Sprintf("Task %s (%s)", cleanTool, arg)
		}
		return "Task " + cleanTool
	}
}

func formatToolCallsForThought(toolCallsRaw json.RawMessage) string {
	if len(toolCallsRaw) == 0 {
		return ""
	}
	var toolCalls []struct {
		Name      string          `json:"name"`
		Arguments json.RawMessage `json:"args"`
		Function  struct {
			Name      string          `json:"name"`
			Arguments json.RawMessage `json:"arguments"`
		} `json:"function"`
	}
	if err := json.Unmarshal(toolCallsRaw, &toolCalls); err != nil {
		return ""
	}
	var steps []string
	for _, tc := range toolCalls {
		name := tc.Name
		if name == "" {
			name = tc.Function.Name
		}
		args := tc.Arguments
		if len(args) == 0 {
			args = tc.Function.Arguments
		}
		if step := formatToolCallStep(name, args); step != "" {
			steps = append(steps, step)
		}
	}
	return strings.Join(steps, "\n")
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
		cleaned := extractUserRequest(entry.Content)
		if cleaned == "" {
			return nil
		}
		return &HistoryMessage{
			ID:        msgID,
			Sender:    "user",
			Text:      cleaned,
			Timestamp: ts,
		}
	}

	if entry.Type == "TOOL_CALL" || entry.Type == "TOOL_RESULT" || entry.Source == "TOOL" {
		return nil // events d'outils bruts : gérés via PLANNER_RESPONSE ou agrégation
	}

	// Réponse visible du modèle : PLANNER_RESPONSE place la réponse finale
	// dans `content`, et le raisonnement intermédiaire (quand le modèle a
	// enchaîné des appels d'outils) dans `thinking` — `content` est alors
	// absent. Les lignes vides (modèle n'a produit ni texte ni raisonnement,
	// ex. enchaînement d'outils purs) sont ignorées pour ne pas polluer le chat.
	if entry.Type == "PLANNER_RESPONSE" {
		text := cleanAssistantText(entry.Content)
		thought := cleanRawContent(entry.Thinking)
		toolSteps := formatToolCallsForThought(entry.ToolCalls)
		if toolSteps != "" {
			if thought != "" {
				thought = thought + "\n" + toolSteps
			} else {
				thought = toolSteps
			}
		}
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
		if entry.Error != "" && msg.Text == "" {
			msg.IsError = true
			msg.Text = entry.Error
		}
		return msg
	}

	return nil
}

// findHistoryDB locate la base SQLite des conversations (source de v├®rit├®
// Antigravity 2.0) pour une cascade donn├®e.
func findHistoryDB(cascadeID string) string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	candidates := []string{
		filepath.Join(home, ".gemini", "antigravity", "conversations", cascadeID+".db"),
		filepath.Join(home, ".gemini", "antigravity-ide", "conversations", cascadeID+".db"),
	}
	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
}

// findFieldBytes retourne le sous-message (wire type 2) du champ fieldNum,
// ou nil s'il est absent. Impl├®mentation manuelle du protobuf (pas de
// biblioth├¿que ÔÇö r├¿gle AGENTS.md).
func findFieldBytes(buf []byte, fieldNum int) []byte {
	if len(buf) == 0 {
		return nil
	}
	i := 0
	for i < len(buf) {
		key, n := readUvarint(buf, i)
		if n == 0 {
			break
		}
		i = n
		f := int(key >> 3)
		w := int(key & 7)
		if f == 0 {
			break
		}
		if w == 0 {
			_, n = readUvarint(buf, i)
			if n == 0 {
				break
			}
			i = n
		} else if w == 2 {
			ln, n := readUvarint(buf, i)
			if n == 0 || n+int(ln) > len(buf) {
				break
			}
			sub := buf[n : n+int(ln)]
			i = n + int(ln)
			if f == fieldNum {
				return sub
			}
		} else if w == 1 {
			i += 8
		} else if w == 5 {
			i += 4
		} else {
			break
		}
	}
	return nil
}

// readUvarint d├®code un varint protobuf. Retourne (valeur, newOffset) ou
// (0, 0) si le buffer est tronqu├®.
func readUvarint(buf []byte, offset int) (uint64, int) {
	var result uint64
	var shift uint
	for offset < len(buf) {
		b := buf[offset]
		offset++
		result |= uint64(b&0x7f) << shift
		if b&0x80 == 0 {
			return result, offset
		}
		shift += 7
		if shift > 63 {
			return 0, 0
		}
	}
	return 0, 0
}

// collectSubFields r├®cup├¿re toutes les occurrences d'un champ r├®p├®t├® (wire
// type 2) dans un message ÔÇö ex. les pi├¿ces de texte d'un message utilisateur.
func collectSubFields(buf []byte, fieldNum int) [][]byte {
	var out [][]byte
	if len(buf) == 0 {
		return out
	}
	i := 0
	for i < len(buf) {
		key, n := readUvarint(buf, i)
		if n == 0 {
			break
		}
		i = n
		f := int(key >> 3)
		w := int(key & 7)
		if f == 0 {
			break
		}
		if w == 0 {
			_, n = readUvarint(buf, i)
			if n == 0 {
				break
			}
			i = n
		} else if w == 2 {
			ln, n := readUvarint(buf, i)
			if n == 0 || n+int(ln) > len(buf) {
				break
			}
			sub := buf[n : n+int(ln)]
			i = n + int(ln)
			if f == fieldNum {
				out = append(out, sub)
			}
		} else if w == 1 {
			i += 8
		} else if w == 5 {
			i += 4
		} else {
			break
		}
	}
	return out
}

// printableString convertit des octets protobuf en cha├«ne UTF-8 si le contenu
// est lisible (texte visible), sinon renvoie "".
func printableString(b []byte) string {
	if len(b) == 0 {
		return ""
	}
	s := string(b)
	for _, r := range s {
		if r < 0x20 && r != '\n' && r != '\t' && r != '\r' {
			return ""
		}
	}
	return s
}

// userTextFromPayload extrait le texte d'un step_payload de type 14
// (message utilisateur). Layout valid├® sur 500+ conversations :
//   - f19.f3[] : liste de pi├¿ces (chaque pi├¿ce porte le texte dans f3.f1)
//   - f19.f2   : texte brut (avec ├®ventuels attributs @[fichier])
//   - f5       : ancien format (f5.f1.f2 = timestamp, texte dans f5.f2)
//   - repli    : premier sous-message avec du texte lisible
func userTextFromPayload(sp []byte) string {
	if f19 := findFieldBytes(sp, 19); f19 != nil {
		parts := collectSubFields(f19, 3)
		var sb strings.Builder
		for _, p := range parts {
			if t := printableString(findFieldBytes(p, 1)); t != "" {
				sb.WriteString(t)
			}
		}
		if sb.Len() > 0 {
			return sb.String()
		}
		if t := printableString(findFieldBytes(f19, 2)); t != "" {
			return t
		}
	}
	if f5 := findFieldBytes(sp, 5); f5 != nil {
		if t := printableString(findFieldBytes(f5, 2)); t != "" {
			return t
		}
	}
	// Repli : premier champ de type cha├«ne lisible (garde le texte des
	// anciennes versions du sch├®ma).
	return firstPrintable(sp)
}

// assistantTextFromPayload extrait le texte (f1/f8) et le raisonnement (f3)
// d'un step_payload de type 15. Layout valid├® sur la base moderne (763
// enregistrements) :
//   - f20 { f1/f8: texte, f3: raisonnement, f6: botId, f7: toolCalls }
//   - certaines ├®tapes ne portent que f6+f7 (appels d'outils, pas de texte)
//   - anciens formats : f20 { f1: texte } ou texte ailleurs ÔåÆ repli
func assistantTextFromPayload(sp []byte) (text, thought string) {
	for _, f20 := range collectSubFields(sp, 20) {
		f1 := printableString(findFieldBytes(f20, 1))
		f8 := printableString(findFieldBytes(f20, 8))
		f3 := printableString(findFieldBytes(f20, 3))
		// f8 porte le texte complet dans le layout moderne ; f1 est l'├®quivalent
		// historique. On garde le plus long (f8 gagne en cas d'├®galit├®).
		if len(f8) >= len(f1) {
			text = f8
		} else {
			text = f1
		}
		if text != "" {
			if f3 != "" && f3 != text {
				thought = f3
			}
			return text, thought
		}
	}
	if text == "" {
		text = firstPrintable(sp)
	}
	return text, thought
}

// titleFromPayload extrait le titre d'un step_payload de type 23 (f30.f4).
func titleFromPayload(sp []byte) string {
	if f30 := findFieldBytes(sp, 30); f30 != nil {
		if t := printableString(findFieldBytes(f30, 4)); t != "" {
			return t
		}
	}
	return ""
}

// firstPrintable retourne le premier sous-message de niveau 1 lisible
// (heuristique de repli pour les formats inconnus).
func firstPrintable(buf []byte) string {
	if len(buf) == 0 {
		return ""
	}
	i := 0
	for i < len(buf) {
		key, n := readUvarint(buf, i)
		if n == 0 {
			break
		}
		i = n
		f := int(key >> 3)
		w := int(key & 7)
		if f == 0 {
			break
		}
		if w == 0 {
			_, n = readUvarint(buf, i)
			if n == 0 {
				break
			}
			i = n
		} else if w == 2 {
			ln, n := readUvarint(buf, i)
			if n == 0 || n+int(ln) > len(buf) {
				break
			}
			sub := buf[n : n+int(ln)]
			i = n + int(ln)
			if t := printableString(sub); t != "" {
				return t
			}
		} else if w == 1 {
			i += 8
		} else if w == 5 {
			i += 4
		} else {
			break
		}
	}
	return ""
}

// tsFromMetadata convertit le timestamp protobuf (metadata.f1 : {1: secondes,
// 2: nanos}) en horaire HH:MM local. Repli : heure actuelle.
func tsFromMetadata(meta []byte) string {
	var sec int64
	if f1 := findFieldBytes(meta, 1); f1 != nil {
		i := 0
		for i < len(f1) {
			key, n := readUvarint(f1, i)
			if n == 0 {
				break
			}
			i = n
			if f := int(key >> 3); f == 1 && key&7 == 0 {
				if v, n := readUvarint(f1, i); n != 0 {
					sec = int64(v)
				}
				break
			}
			if key&7 == 2 {
				ln, n := readUvarint(f1, i)
				if n == 0 || n+int(ln) > len(f1) {
					break
				}
				i = n + int(ln)
			} else {
				break
			}
		}
	}
	t := time.Unix(sec, 0).Local()
	return fmt.Sprintf("%02d:%02d", t.Hour(), t.Minute())
}

// readSQLiteSteps lit l'historique depuis la table `steps` de la base de
// conversations. Retourne les messages tri├®s par idx, et les titres trouv├®s
// dans les ├®tapes de type 23.
func readSQLiteSteps(dbPath, cascadeID string) ([]HistoryMessage, string, error) {
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return nil, "", err
	}
	defer db.Close()

	rows, err := db.Query("SELECT idx, step_type, status, metadata, step_payload FROM steps ORDER BY idx")
	if err != nil {
		return nil, "", err
	}
	defer rows.Close()

	var messages []HistoryMessage
	title := ""
	for rows.Next() {
		var (
			idx      int
			stepType int
			status   int
			metadata []byte
			payload  []byte
		)
		if err := rows.Scan(&idx, &stepType, &status, &metadata, &payload); err != nil {
			continue
		}

		ts := tsFromMetadata(metadata)
		msgID := fmt.Sprintf("h-%d", idx)

		switch stepType {
		case stepTypeUser:
			text := extractUserRequest(userTextFromPayload(payload))
			if text == "" {
				continue
			}
			messages = append(messages, HistoryMessage{
				ID:        msgID,
				Sender:    "user",
				Text:      text,
				Timestamp: ts,
			})
		case stepTypeAssistant:
			text, thought := assistantTextFromPayload(payload)
			text = cleanAssistantText(text)
			thought = cleanRawContent(thought)
			if text == "" && thought == "" {
				continue
			}
			msg := HistoryMessage{
				ID:        msgID,
				Sender:    "assistant",
				Text:      text,
				Thought:   thought,
				Timestamp: ts,
			}
			if status > 2 && text == "" {
				msg.IsError = true
				if msg.Text == "" {
					msg.Text = "Erreur pendant la génération"
				}
			}
			messages = append(messages, msg)
		case stepTypeTitle:
			if title == "" {
				title = titleFromPayload(payload)
			}
		}
	}
	if err := rows.Err(); err != nil {
		return messages, title, err
	}
	if messages == nil {
		messages = []HistoryMessage{}
	}
	return messages, title, nil
}

// CoalesceHistoryMessages regroupe les étapes consécutives de l'assistant
// appartenant au même tour de réponse en un seul HistoryMessage unifié
// (fusion des pensées et concaténation propre du texte), évitant le
// découpage en bulles isolées sur mobile.
func CoalesceHistoryMessages(raw []HistoryMessage) []HistoryMessage {
	if len(raw) <= 1 {
		return raw
	}
	var out []HistoryMessage
	for _, m := range raw {
		if len(out) == 0 {
			out = append(out, m)
			continue
		}
		prev := &out[len(out)-1]
		if prev.Sender == "assistant" && m.Sender == "assistant" {
			// Fusion des pensées (Thought)
			mThought := strings.TrimSpace(m.Thought)
			if mThought != "" {
				if strings.TrimSpace(prev.Thought) == "" {
					prev.Thought = mThought
				} else if !strings.Contains(prev.Thought, mThought) {
					prev.Thought = strings.TrimSpace(prev.Thought) + "\n\n" + mThought
				}
			}
			// Fusion des textes
			mText := strings.TrimSpace(m.Text)
			if mText != "" {
				if strings.TrimSpace(prev.Text) == "" {
					prev.Text = mText
				} else if !strings.Contains(prev.Text, mText) {
					prev.Text = strings.TrimSpace(prev.Text) + "\n\n" + mText
				}
			}
			if m.IsError && strings.TrimSpace(prev.Text) == "" {
				prev.IsError = true
			}
			if m.Timestamp != "" {
				prev.Timestamp = m.Timestamp
			}
		} else {
			out = append(out, m)
		}
	}
	return out
}

// GetSessionHistory lit l'historique d'une cascade : SQLite d'abord (source
// de vérité Antigravity 2.0, `conversations/<id>.db`), puis repli sur
// transcript.jsonl pour les anciennes sessions. Les deux sources peuvent
// coexister (migration) — on garde celle qui contient le plus de messages.
func GetSessionHistory(cascadeID string) ([]HistoryMessage, error) {
	if dbPath := findHistoryDB(cascadeID); dbPath != "" {
		if messages, _, err := readSQLiteSteps(dbPath, cascadeID); err == nil && len(messages) > 0 {
			logJSON.Debug("history_from_sqlite", "cascade", cascadeID, "messages", len(messages))
			return CoalesceHistoryMessages(messages), nil
		}
	}

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

	// Allow up to 10MB per line to handle very large text blocks in JSONL via sync.Pool
	hBuf := AcquireHistoryBuffer()
	defer ReleaseHistoryBuffer(hBuf)
	scanner.Buffer(*hBuf, len(*hBuf))

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
	return CoalesceHistoryMessages(messages), nil
}

// ExtractHistoryFromTrajectory extrait les messages d'un blob GetCascadeTrajectory.
func ExtractHistoryFromTrajectory(raw []byte) []HistoryMessage {
	var messages []HistoryMessage
	fields := connectrpc.DecodeFields(raw)
	for _, f := range fields {
		if f.Num == 1 && f.WireType == 2 {
			subFields := connectrpc.DecodeFields(f.Bytes)
			for _, sf := range subFields {
				if sf.Num == 3 && sf.WireType == 2 {
					turnFields := connectrpc.DecodeFields(sf.Bytes)
					for _, tf := range turnFields {
						if tf.Num == 1 && tf.WireType == 2 {
							stepFields := connectrpc.DecodeFields(tf.Bytes)
							for _, stf := range stepFields {
								if stf.Num == 19 && stf.WireType == 2 {
									for _, subPrompt := range connectrpc.DecodeFields(stf.Bytes) {
										if (subPrompt.Num == 1 || subPrompt.Num == 2) && subPrompt.WireType == 2 && len(subPrompt.Bytes) > 0 {
											promptText := string(subPrompt.Bytes)
											cleaned := extractUserRequest(promptText)
											if len(cleaned) > 0 && cleaned[0] >= 32 && !strings.HasPrefix(cleaned, "# Conversation History") {
												messages = append(messages, HistoryMessage{
													ID:        fmt.Sprintf("user-%d", len(messages)+1),
													Sender:    "user",
													Text:      cleaned,
													Timestamp: time.Now().Format("15:04"),
												})
												break
											}
										}
									}
								}
								if stf.Num == 2 && stf.WireType == 2 {
									for _, subResp := range connectrpc.DecodeFields(stf.Bytes) {
										if subResp.Num == 3 && subResp.WireType == 2 && len(subResp.Bytes) > 0 {
											respText := string(subResp.Bytes)
											if strings.HasPrefix(respText, "<USER_REQUEST>") || strings.HasPrefix(respText, "# Conversation History") {
												continue
											}
											if len(respText) > 0 {
												messages = append(messages, HistoryMessage{
													ID:        fmt.Sprintf("assistant-%d", len(messages)+1),
													Sender:    "assistant",
													Text:      respText,
													Timestamp: time.Now().Format("15:04"),
												})
											}
										}
									}
								}
							}
						}
					}
				}
			}
		}
	}
	return messages
}

// transcriptCounts regroupe les compteurs d'activit├® extraits d'un transcript.
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
	modFiles := ListSessionModifiedFiles(cascadeID)
	out["files"] = len(modFiles)

	transcriptPath := findTranscriptPath(cascadeID)
	if transcriptPath == "" {
		return out
	}
	f, err := os.Open(transcriptPath)
	if err != nil {
		return out
	}
	defer f.Close()

	seenArtifacts := make(map[string]bool)
	seenUploads := make(map[string]bool)
	seenTasks := make(map[string]bool)

	scanner := bufio.NewScanner(f)
	hBuf := AcquireHistoryBuffer()
	defer ReleaseHistoryBuffer(hBuf)
	scanner.Buffer(*hBuf, len(*hBuf))

	for scanner.Scan() {
		line := scanner.Bytes()
		var entry struct {
			Type      string          `json:"type"`
			Source    string          `json:"source"`
			Content   string          `json:"content"`
			ToolCalls json.RawMessage `json:"tool_calls"`
		}
		if err := json.Unmarshal(line, &entry); err != nil {
			continue
		}

		// Subagents : comptage depuis tool_calls ou entry.Content
		if len(entry.ToolCalls) > 0 {
			var calls []struct {
				Name string `json:"name"`
			}
			if json.Unmarshal(entry.ToolCalls, &calls) == nil {
				for _, c := range calls {
					if c.Name == "invoke_subagent" || c.Name == "define_subagent" {
						out["subagents"]++
					}
				}
			}
		}
		if entry.Type == "TOOL_CALL" {
			var tc struct {
				Name string `json:"name"`
			}
			if json.Unmarshal([]byte(entry.Content), &tc) == nil {
				if tc.Name == "invoke_subagent" || tc.Name == "define_subagent" {
					out["subagents"]++
				}
			}
		}

		// Artefacts / uploads
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

// ListSessionModifiedFiles parcourt le transcript d'une cascade et extrait la liste
// des chemins de fichiers modifiés par l'agent ou l'utilisateur (write_to_file,
// replace_file_content, multi_replace_file_content, edit_file, apply_diff, etc.).
func ListSessionModifiedFiles(cascadeID string) []string {
	var results []string
	transcriptPath := findTranscriptPath(cascadeID)
	if transcriptPath == "" {
		return results
	}
	f, err := os.Open(transcriptPath)
	if err != nil {
		return results
	}
	defer f.Close()

	seen := make(map[string]bool)
	scanner := bufio.NewScanner(f)
	hBuf := AcquireHistoryBuffer()
	defer ReleaseHistoryBuffer(hBuf)
	scanner.Buffer(*hBuf, len(*hBuf))

	isModTool := func(name string) bool {
		switch name {
		case "write_to_file", "replace_file_content", "multi_replace_file_content", "edit_file", "apply_diff", "patch":
			return true
		default:
			return false
		}
	}

	cleanFilePath := func(p string) string {
		p = strings.TrimSpace(p)
		p = strings.Trim(p, "\"'`")
		p = strings.ReplaceAll(p, "\\\\", "/")
		p = strings.ReplaceAll(p, "\\", "/")
		if strings.HasPrefix(p, "file:///") {
			p = p[8:]
		} else if strings.HasPrefix(p, "file://") {
			p = p[7:]
		}
		return strings.TrimSpace(p)
	}

	isIgnoredPath := func(p string) bool {
		if p == "" {
			return true
		}
		pLower := strings.ToLower(p)
		if strings.Contains(pLower, "/brain/") || strings.Contains(pLower, "\\brain\\") || strings.Contains(pLower, "scratch") {
			return true
		}
		return false
	}

	addFile := func(rawPath string) {
		p := cleanFilePath(rawPath)
		if p != "" && !isIgnoredPath(p) && !seen[p] {
			seen[p] = true
			results = append(results, p)
		}
	}

	for scanner.Scan() {
		line := scanner.Bytes()
		var entry struct {
			Type      string          `json:"type"`
			Content   string          `json:"content"`
			ToolCalls json.RawMessage `json:"tool_calls"`
		}
		if err := json.Unmarshal(line, &entry); err != nil {
			continue
		}

		// 1. Parsing depuis tool_calls (format standard Antigravity)
		if len(entry.ToolCalls) > 0 {
			var calls []struct {
				Name      string                 `json:"name"`
				Args      map[string]interface{} `json:"args"`
				Arguments map[string]interface{} `json:"arguments"`
			}
			if json.Unmarshal(entry.ToolCalls, &calls) == nil {
				for _, c := range calls {
					if isModTool(c.Name) {
						m := c.Args
						if len(m) == 0 {
							m = c.Arguments
						}
						for _, k := range []string{"TargetFile", "AbsolutePath", "file_path", "filePath", "path", "file"} {
							if val, ok := m[k].(string); ok && val != "" {
								addFile(val)
								break
							}
						}
					}
				}
			}
		}

		// 2. Parsing depuis entry.Content (si TOOL_CALL direct)
		if entry.Type == "TOOL_CALL" || strings.Contains(entry.Content, "replace_file_content") || strings.Contains(entry.Content, "write_to_file") {
			var tc struct {
				Name      string                 `json:"name"`
				Args      map[string]interface{} `json:"args"`
				Arguments map[string]interface{} `json:"arguments"`
			}
			if json.Unmarshal([]byte(entry.Content), &tc) == nil && isModTool(tc.Name) {
				m := tc.Args
				if len(m) == 0 {
					m = tc.Arguments
				}
				for _, k := range []string{"TargetFile", "AbsolutePath", "file_path", "filePath", "path", "file"} {
					if val, ok := m[k].(string); ok && val != "" {
						addFile(val)
						break
					}
				}
			}
		}
	}
	return results
}

// SubagentSummary repr├®sente un sous-agent d├®couvert dans l'arbre d'ex├®cution (DAG).
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
// ordonn├®e des sous-agents invoqu├®s (DAG / arborescence).
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
	hBuf := AcquireHistoryBuffer()
	defer ReleaseHistoryBuffer(hBuf)
	scanner.Buffer(*hBuf, len(*hBuf))

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

		// D├®tection dans tool_calls JSON array
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

		// D├®tection dans Content texte si stringifi├®
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
	// Regex POSIX (/c:/…, /home/…, /Users/…) et Windows (C:\…, C:/…, c:\…).
	re := regexp.MustCompile(`(?:file:///)?(?:[A-Za-z]:[/\\]|/)(?:[^"'\s\t\r\n\(\)<>]+)`)
	for _, m := range re.FindAllString(s, -1) {
		clean := strings.TrimRight(m, "\"',.;:)")
		clean = strings.ReplaceAll(clean, "\\\\", "\\")
		if len(clean) > 8 { // ignore les fragments trop courts
			out = append(out, clean)
		}
	}
	return out
}

// isUploadPath d├®tecte un fichier t├®l├®vers├® par le mobile dans scratch/.
func isUploadPath(p string) bool {
	return strings.Contains(p, "scratch") && strings.Contains(p, "upload_")
}

func cleanRawContent(s string) string {
	if s == "" {
		return ""
	}
	s = systemMessageBlockRe.ReplaceAllString(s, "")
	s = systemPromptBlockRe.ReplaceAllString(s, "")
	s = additionalMetaBlockRe.ReplaceAllString(s, "")
	s = userSettingsBlockRe.ReplaceAllString(s, "")
	s = systemGeneratedBlockRe.ReplaceAllString(s, "")
	s = contextBlockRe.ReplaceAllString(s, "")
	s = bgMessageBlockRe.ReplaceAllString(s, "")
	s = systemNoticeRe.ReplaceAllString(s, "")
	return strings.TrimSpace(s)
}

func cleanAssistantText(s string) string {
	s = cleanRawContent(s)
	if s == "" {
		return ""
	}
	trimmed := strings.TrimSpace(s)
	if strings.HasPrefix(trimmed, "<SYSTEM_MESSAGE>") ||
		strings.HasPrefix(trimmed, "<system_message>") ||
		strings.HasPrefix(trimmed, "[Message] timestamp=") {
		return ""
	}
	return trimmed
}

func extractUserRequest(content string) string {
	startTag := "<USER_REQUEST>"
	endTag := "</USER_REQUEST>"

	startIdx := strings.Index(content, startTag)
	if startIdx >= 0 {
		endIdx := strings.Index(content, endTag)
		if endIdx > startIdx {
			return cleanRawContent(content[startIdx+len(startTag) : endIdx])
		}
	}

	trimmed := strings.TrimSpace(content)
	if strings.HasPrefix(trimmed, "<SYSTEM_MESSAGE>") ||
		strings.HasPrefix(trimmed, "<system_message>") ||
		strings.HasPrefix(trimmed, "<identity>") ||
		strings.HasPrefix(trimmed, "<user_information>") ||
		strings.HasPrefix(trimmed, "<skills>") ||
		strings.HasPrefix(trimmed, "<subagents>") ||
		strings.HasPrefix(trimmed, "<messaging>") ||
		strings.HasPrefix(trimmed, "<artifacts>") ||
		strings.HasPrefix(trimmed, "<slash_commands>") ||
		strings.HasPrefix(trimmed, "<planning_mode>") ||
		strings.HasPrefix(trimmed, "<guidelines>") ||
		strings.HasPrefix(trimmed, "<communication_style>") ||
		strings.HasPrefix(trimmed, "<conversation_transcript>") ||
		strings.HasPrefix(trimmed, "[Message] timestamp=") {
		return ""
	}

	return cleanRawContent(trimmed)
}

func cleanPromptTitle(s string) string {
	s = strings.TrimSpace(s)
	s = strings.ReplaceAll(s, "\r\n", " ")
	s = strings.ReplaceAll(s, "\n", " ")
	// Remplacer les longs chemins absolus Windows par leur dossier de base
	pathRe := regexp.MustCompile(`[a-zA-Z]:\\[^ \t\r\n]+`)
	s = pathRe.ReplaceAllStringFunc(s, func(p string) string {
		base := filepath.Base(p)
		if base != "" && base != "." && base != "/" && base != "\\" {
			return base
		}
		return p
	})
	if len(s) > 60 {
		return s[:60] + "..."
	}
	return s
}

// ProjectSummary represents an official Antigravity 2.0 project from ~/.gemini/config/projects/
type ProjectSummary struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	FolderURI string    `json:"folderUri"`
	Path      string    `json:"path"`
	UpdatedAt time.Time `json:"updatedAt"`
}

var (
	projectsCacheMu  sync.RWMutex
	cachedProjects   []ProjectSummary
	projectsCachedAt time.Time
	projectsCacheTTL = 5 * time.Second
)

// InvalidateProjectsCache force le rechargement immédiat du registre de projets.
func InvalidateProjectsCache() {
	projectsCacheMu.Lock()
	cachedProjects = nil
	projectsCacheMu.Unlock()
}

// ListOfficialProjects reads registered projects from ~/.gemini/config/projects/
func ListOfficialProjects() []ProjectSummary {
	projectsCacheMu.RLock()
	if cachedProjects != nil && time.Since(projectsCachedAt) < projectsCacheTTL {
		res := make([]ProjectSummary, len(cachedProjects))
		copy(res, cachedProjects)
		projectsCacheMu.RUnlock()
		return res
	}
	projectsCacheMu.RUnlock()

	projectsCacheMu.Lock()
	defer projectsCacheMu.Unlock()
	if cachedProjects != nil && time.Since(projectsCachedAt) < projectsCacheTTL {
		res := make([]ProjectSummary, len(cachedProjects))
		copy(res, cachedProjects)
		return res
	}

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
		path := normalizeWorkspace(folderURI)
		if path == "" && parsed.Name != "" && (strings.Contains(parsed.Name, `\`) || strings.Contains(parsed.Name, "/")) {
			path = normalizeWorkspace(parsed.Name)
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

	cachedProjects = list
	projectsCachedAt = time.Now()

	res := make([]ProjectSummary, len(list))
	copy(res, list)
	return res
}

// projectIDFromRegistry résout le projectID d'un workspace à partir du
// registre local ~/.gemini/config/projects/*.json, sans aucun appel LS
// (O(1), utilisé par create_cascade quand le cache sessions est froid).
func projectIDFromRegistry(uri string) string {
	if uri == "" {
		return ""
	}
	normUri := strings.ToLower(normalizeWorkspace(uri))
	for _, p := range ListOfficialProjects() {
		pNormPath := strings.ToLower(normalizeWorkspace(p.Path))
		pNormUri := strings.ToLower(normalizeWorkspace(p.FolderURI))
		if strings.EqualFold(p.FolderURI, uri) ||
			(pNormUri != "" && pNormUri == normUri) ||
			(pNormPath != "" && pNormPath == normUri) ||
			strings.EqualFold(p.Name, uri) {
			return p.ID
		}
	}
	return ""
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

// listWorkspaces construit le sélecteur de workspace (G4) : le registre
// officiel ~/.gemini/config/projects uniquement pour rester synchronisé avec Antigravity.
// Si aucun projet officiel n'est configuré, fallback sur un scan borné du home.
func listWorkspaces() []map[string]interface{} {
	seen := make(map[string]bool)
	var out []map[string]interface{}
	add := func(name, path, source string) {
		norm := filepath.ToSlash(strings.TrimRight(path, "/\\"))
		lowerKey := strings.ToLower(norm)
		if name == "" || norm == "" || seen[lowerKey] {
			return
		}
		seen[lowerKey] = true
		rel := ""
		if home, err := os.UserHomeDir(); err == nil {
			if r, err := filepath.Rel(home, norm); err == nil && !strings.HasPrefix(r, "..") {
				rel = filepath.ToSlash(r)
			}
		}
		out = append(out, map[string]interface{}{
			"name":         name,
			"path":         norm,
			"relativePath": rel,
			"source":       source,
		})
	}

	for _, p := range ListOfficialProjects() {
		add(p.Name, p.Path, "registry")
	}

	// Uniquement en fallback si aucun projet officiel n'est configuré
	if len(out) == 0 {
		if home, err := os.UserHomeDir(); err == nil {
			if entries, err := os.ReadDir(home); err == nil {
				skip := map[string]bool{
					"AppData": true, "Library": true, "Applications": true,
					"Desktop": true, "Documents": true, "Downloads": true,
					"Pictures": true, "Music": true, "Videos": true, "Public": true,
					".git": true, ".gemini": true, "node_modules": true,
				}
				for _, e := range entries {
					if !e.IsDir() || strings.HasPrefix(e.Name(), ".") || skip[e.Name()] {
						continue
					}
					add(e.Name(), filepath.Join(home, e.Name()), "home")
				}
			}
		}
	}
	return out
}

// GetMostRecentSession retourne la session la plus récemment mise à jour sur le PC.
func GetMostRecentSession() (map[string]interface{}, error) {
	sessions := ListLocalSessions()
	if len(sessions) == 0 {
		return nil, fmt.Errorf("aucune session active trouvée")
	}
	return sessions[0], nil
}
