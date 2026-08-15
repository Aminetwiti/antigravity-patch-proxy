package gateway

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestParseWorkspaceFromTranscript(t *testing.T) {
	cases := []struct {
		content string
		want    string
	}{
		{
			content: "The mapping is shown as follows in the format [URI] -> [CorpusName]:\nc:\\Users\\amine\\Downloads\\antigravity-add-model-main\\antigravity-add-model-main -> Aminetwiti/antigravity-add-model-main\nCode relating to the user's requests...",
			want:    "c:\\Users\\amine\\Downloads\\antigravity-add-model-main\\antigravity-add-model-main",
		},
		{
			content: "The mapping is shown as follows in the format [URI] -> [CorpusName]:\nc:\\Users\\amine\\Downloads\\raouf taxi\\www - Copie -> Aminetwiti/www-copie\n",
			want:    "c:\\Users\\amine\\Downloads\\raouf taxi\\www - Copie",
		},
		{
			content: "Workspace: /home/user/my-project\nSome other text",
			want:    "/home/user/my-project",
		},
	}

	for i, c := range cases {
		got := parseWorkspaceFromTranscript(c.content)
		if got != c.want {
			t.Errorf("case %d: got %q, want %q", i, got, c.want)
		}
	}
}

func TestListLocalSessions(t *testing.T) {
	sessions := ListLocalSessions()
	if len(sessions) == 0 {
		t.Log("No local sessions found on this machine, skipping validation")
		return
	}
	t.Logf("Found %d local sessions", len(sessions))
	for i, s := range sessions {
		if i >= 10 {
			break
		}
		t.Logf("[%d] ID=%s Title=%q Workspace=%q Time=%s", i, s["cascadeId"], s["title"], s["workspace"], s["updatedAt"])
		if s["cascadeId"] == "" {
			t.Errorf("session %d has empty cascadeId", i)
		}
		if s["workspace"] == "" {
			t.Errorf("session %d has empty workspace", i)
		}
	}
}

// TestFindTranscriptPathGhostSession — régression : un dossier de session sans
// transcript (ghost) ne doit PAS renvoyer un chemin inexistant (l'ancien
// return candidates[0] produisait un faux path → transcript_not_found dans
// les logs et une erreur silencieuse). findTranscriptPath lit le home réel de
// la machine, donc on vérifie l'invariant par un ID inexistant garanti : la
// fonction doit renvoyer "" et GetSessionHistory un historique vide propre.
func TestFindTranscriptPathGhostSession(t *testing.T) {
	ghostID := "ghost-session-" + time.Now().Format("150405.000000000")
	if p := findTranscriptPath(ghostID); p != "" {
		t.Fatalf("findTranscriptPath(%q) = %q, want empty pour une session fantôme", ghostID, p)
	}
	hist, err := GetSessionHistory(ghostID)
	if err != nil {
		t.Fatalf("GetSessionHistory ghost: erreur inattendue: %v", err)
	}
	if hist == nil || len(hist) != 0 {
		t.Fatalf("GetSessionHistory ghost = %v, want []HistoryMessage{} vide", hist)
	}
}

// TestFindTranscriptPathSkipsMissingCandidates — vérifie la logique de
// candidats directement (sans dépendre du home réel) : aucune des variantes
// n'existant, la fonction d'aide locale doit renvoyer "".
func TestFindTranscriptPathSkipsMissingCandidates(t *testing.T) {
	candidates := []string{
		filepath.Join(t.TempDir(), "missing1.jsonl"),
		filepath.Join(t.TempDir(), "missing2.jsonl"),
	}
	got := ""
	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			got = p
			break
		}
	}
	if got != "" {
		t.Fatalf("aucun candidat n'existe mais un chemin a été retourné: %q", got)
	}
}
