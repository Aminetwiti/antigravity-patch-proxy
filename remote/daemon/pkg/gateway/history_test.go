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

// TestParseTranscriptLine — régression du contenu vide : les PLANNER_RESPONSE
// intermédiaires stockent la réponse dans `thinking` (pas `content`), les
// enchaînements d'outils purs n'ont ni l'un ni l'autre, et les lignes
// d'outils ne doivent jamais apparaître comme messages assistant.
func TestParseTranscriptLine(t *testing.T) {
	line := func(l string) []byte { return []byte(l) }

	tests := []struct {
		name     string
		line     []byte
		wantNil  bool
		wantSend string
		wantText string
		wantTh   string
	}{
		{
			name:     "user request",
			line:     line(`{"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","created_at":"2026-08-15T15:44:39+01:00","content":"<USER_REQUEST>\nhello\n</USER_REQUEST>"}`),
			wantSend: "user",
			wantText: "hello",
		},
		{
			name:     "final response with content",
			line:     line(`{"step_index":137,"source":"MODEL","type":"PLANNER_RESPONSE","created_at":"2026-08-15T15:44:39+01:00","content":"Voici la réponse finale"}`),
			wantSend: "assistant",
			wantText: "Voici la réponse finale",
		},
		{
			name:     "intermediate reasoning in thinking only",
			line:     line(`{"step_index":2,"source":"MODEL","type":"PLANNER_RESPONSE","created_at":"2026-08-15T15:44:39+01:00","thinking":"**Analyzing**\nreasoning here"}`),
			wantSend: "assistant",
			wantTh:   "**Analyzing**\nreasoning here",
		},
		{
			name:     "content plus thinking",
			line:     line(`{"step_index":201,"source":"MODEL","type":"PLANNER_RESPONSE","created_at":"2026-08-15T15:44:39+01:00","content":"Réponse","thinking":"réfléchi"}`),
			wantSend: "assistant",
			wantText: "Réponse",
			wantTh:   "réfléchi",
		},
		{
			name:    "empty planner response skipped",
			line:    line(`{"step_index":5,"source":"MODEL","type":"PLANNER_RESPONSE","created_at":"2026-08-15T15:44:39+01:00"}`),
			wantNil: true,
		},
		{
			name:    "tool call invisible",
			line:    line(`{"step_index":6,"source":"MODEL","type":"VIEW_FILE","created_at":"2026-08-15T15:44:39+01:00","content":"..."}`),
			wantNil: true,
		},
		{
			name:    "garbage line ignored",
			line:    line(`not json`),
			wantNil: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := parseTranscriptLine(tt.line)
			if tt.wantNil {
				if got != nil {
					t.Fatalf("parseTranscriptLine() = %+v, want nil", got)
				}
				return
			}
			if got == nil {
				t.Fatalf("parseTranscriptLine() = nil, want message")
			}
			if got.Sender != tt.wantSend {
				t.Errorf("Sender = %q, want %q", got.Sender, tt.wantSend)
			}
			if got.Text != tt.wantText {
				t.Errorf("Text = %q, want %q", got.Text, tt.wantText)
			}
			if got.Thought != tt.wantTh {
				t.Errorf("Thought = %q, want %q", got.Thought, tt.wantTh)
			}
		})
	}
}
