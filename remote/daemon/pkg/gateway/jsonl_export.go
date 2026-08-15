package gateway

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// jsonlExportDir : dossier d'export des transcripts JSONL (variable pour tests).
var jsonlExportDir = func() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return "."
	}
	return filepath.Join(home, ".gemini", "antigravity-remote", "exports")
}()

// ExportSessionJSONL convertit un transcript local en JSONL format Claude Code
// (interopérabilité : les outils de replay Claude Code consomment ce format).
// Retourne le chemin du fichier écrit.
func ExportSessionJSONL(cascadeID string) (string, error) {
	src := findTranscriptPath(cascadeID)
	if src == "" {
		return "", fmt.Errorf("aucun transcript trouvé pour %s", cascadeID)
	}
	raw, err := os.ReadFile(src)
	if err != nil {
		return "", err
	}
	lines, err := convertTranscriptToJSONL(raw)
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(jsonlExportDir, 0755); err != nil {
		return "", err
	}
	out := filepath.Join(jsonlExportDir, cascadeID+".jsonl")
	if err := os.WriteFile(out, []byte(lines), 0644); err != nil {
		return "", err
	}
	return out, nil
}

// convertTranscriptToJSONL transforme les lignes JSON brutes du transcript en
// lignes JSONL structurées : {"index":N,"step":{...}} puis un marqueur
// final {"type":"done"} (contrat du format Claude Code).
func convertTranscriptToJSONL(raw []byte) (string, error) {
	var out strings.Builder
	index := 0
	for _, line := range strings.Split(string(raw), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		var step map[string]interface{}
		if err := json.Unmarshal([]byte(line), &step); err != nil {
			continue // ligne invalide — on saute, on ne casse pas l'export
		}
		entry := map[string]interface{}{"index": index, "step": step}
		b, err := json.Marshal(entry)
		if err != nil {
			continue
		}
		out.Write(b)
		out.WriteByte('\n')
		index++
	}
	done := map[string]interface{}{"type": "done", "session_id": "", "exit_code": 0}
	b, _ := json.Marshal(done)
	out.Write(b)
	out.WriteByte('\n')
	return out.String(), nil
}
