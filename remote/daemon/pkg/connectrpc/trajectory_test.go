package connectrpc

import (
	"os"
	"testing"
)

// TestParseTrajectoriesRealCapture valide l'extraction sur la capture réelle
// du hub (fixture testdata/hub_trajectories.bin, 58 Ko, ~40 sessions).
func TestParseTrajectoriesRealCapture(t *testing.T) {
	raw, err := os.ReadFile("testdata/hub_trajectories.bin")
	if err != nil {
		t.Skipf("fixture absente: %v", err)
	}

	summaries := ParseTrajectories(raw)
	if len(summaries) < 10 {
		t.Fatalf("attendu >=10 trajectoires, reçu %d", len(summaries))
	}

	// Chaque entrée doit avoir un UUID ; le titre n'est pas garanti pour
	// toutes les sessions (parser heuristique), mais une majorité doit en avoir.
	seen := map[string]bool{}
	withTitle := 0
	for _, s := range summaries {
		if len(s.CascadeID) != 36 {
			t.Errorf("cascadeId invalide: %q", s.CascadeID)
		}
		if seen[s.CascadeID] {
			t.Errorf("cascadeId dupliqué: %s", s.CascadeID)
		}
		seen[s.CascadeID] = true
		if s.Title != "" && s.Title != "Cascade Session" {
			withTitle++
		}
		if s.Status == "" {
			t.Errorf("statut manquant pour %s", s.CascadeID)
		}
	}
	if withTitle < len(summaries)/2 {
		t.Errorf("trop peu de titres extraits: %d/%d", withTitle, len(summaries))
	}

	// Vérification ciblée sur des entrées connues de la capture réelle.
	byID := map[string]string{}
	for _, s := range summaries {
		byID[s.CascadeID] = s.Title
	}
	if got := byID["f07b7ea8-bf8b-4df6-8189-08ce3d132fec"]; got != "Hello from remote CLI. This is Marche 1 validation." {
		t.Errorf("titre attendu pour f07b7ea8, reçu %q", got)
	}
	if got := byID["a8a9e473-c952-41f9-a1d2-504d5f7f0ada"]; got != "Accessing Local File Directory" {
		t.Errorf("titre attendu pour a8a9e473, reçu %q", got)
	}
}

func TestParseTrajectoriesStructuredMessage(t *testing.T) {
	// Réplique d'une entrée structurée observée (format réel de la capture) :
	//   GetAllCascadeTrajectoriesResponse {
	//     1: repeated CascadeTrajectorySummary   ← chaque entrée est un
	//        sous-message contenant #1 cascade_id, #2 titre, #22 statut
	//   }
	summary := &writer{}
	summary.stringField(1, "2947da31-5b79-4741-9bb5-34ddbae3de18")
	summary.stringField(2, "Greeting In Python")
	summary.varintField(5, 1)
	summary.varintField(22, 4)

	w := &writer{}
	w.bytesField(1, summary.b)

	// Frame gRPC-Web autour du message
	msg := w.b
	framed := make([]byte, 5+len(msg))
	framed[0] = 0
	framed[1] = byte(len(msg) >> 24)
	framed[2] = byte(len(msg) >> 16)
	framed[3] = byte(len(msg) >> 8)
	framed[4] = byte(len(msg))
	copy(framed[5:], msg)

	summaries := ParseTrajectories(framed)
	if len(summaries) != 1 {
		t.Fatalf("attendu 1 trajectoire, reçu %d", len(summaries))
	}
	s := summaries[0]
	if s.CascadeID != "2947da31-5b79-4741-9bb5-34ddbae3de18" {
		t.Errorf("cascadeId: %s", s.CascadeID)
	}
	if s.Title != "Greeting In Python" {
		t.Errorf("titre: %q", s.Title)
	}
	if s.Status != "CASCADE_STATUS_READY" {
		t.Errorf("statut: %q", s.Status)
	}
}

func TestParseTrajectoriesRawBlob(t *testing.T) {
	// Forme blob texte : " $<uuid> <titre>\x00<workspace>…"
	blob := " $f07b7ea8-bf8b-4df6-8189-08ce3d132fec \x00\x00\x00 Hello from remote CLI. This is Marche 1 validation. file:///C:/test/project"
	msg := &writer{}
	msg.bytesField(1, []byte(blob))
	msg.varintField(2, 1)

	summaries := ParseTrajectories(msg.b)
	if len(summaries) != 1 {
		t.Fatalf("attendu 1 trajectoire, reçu %d", len(summaries))
	}
	s := summaries[0]
	if s.CascadeID != "f07b7ea8-bf8b-4df6-8189-08ce3d132fec" {
		t.Errorf("cascadeId: %s", s.CascadeID)
	}
	if s.Title == "" || s.Title == "Cascade Session" {
		t.Errorf("titre: %q", s.Title)
	}
	if s.Workspace != "file:///C:/test/project" {
		t.Errorf("workspace: %q", s.Workspace)
	}
}
