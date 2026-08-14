package connectrpc

import (
	"testing"
)

func TestBuildStartCascadeAndDecode(t *testing.T) {
	workspaceURI := "file:///C:/test_project"
	requestedModel := uint64(190)

	buf := BuildStartCascade(workspaceURI, "", "", requestedModel)
	if len(buf) == 0 {
		t.Fatalf("BuildStartCascade ne devrait pas renvoyer un buffer vide")
	}

	fields := DecodeFields(buf)
	if len(fields) == 0 {
		t.Fatalf("DecodeFields ne devrait pas renvoyer une liste de champs vide")
	}

	foundWorkspace := false
	foundModel := false

	for _, f := range fields {
		if f.Num == 8 && string(f.Bytes) == workspaceURI {
			foundWorkspace = true
		}
		if f.Num == 14 && f.Varint == requestedModel {
			foundModel = true
		}
	}

	if !foundWorkspace {
		t.Errorf("Attendu workspaceURI=%s dans le champ #8", workspaceURI)
	}
	if !foundModel {
		t.Errorf("Attendu modelID=%d dans le champ #14", requestedModel)
	}
}

// TestBuildStartCascadeModelUID - quand le mobile fournit un modelUID, le
// champ 15 (requested_model_uid) est encodé à la place de l'enum (14), et
// l'inverse quand l'UID est vide.
func TestBuildStartCascadeModelUID(t *testing.T) {
	t.Run("UID prioritaire", func(t *testing.T) {
		buf := BuildStartCascade("file:///C:/x", "", "gemini-3.1-pro-low", 190)
		fields := DecodeFields(buf)
		foundUID, foundEnum := false, false
		for _, f := range fields {
			if f.Num == 15 && string(f.Bytes) == "gemini-3.1-pro-low" {
				foundUID = true
			}
			if f.Num == 14 {
				foundEnum = true
			}
		}
		if !foundUID {
			t.Error("Attendu requested_model_uid (champ 15) encodé avec le modelUID")
		}
		if foundEnum {
			t.Error("Ne devrait PAS encoder requested_model (14) quand le UID est fourni")
		}
	})

	t.Run("repli enum", func(t *testing.T) {
		buf := BuildStartCascade("file:///C:/x", "", "", 190)
		foundEnum := false
		for _, f := range DecodeFields(buf) {
			if f.Num == 14 && f.Varint == 190 {
				foundEnum = true
			}
		}
		if !foundEnum {
			t.Error("Attendu requested_model (14)=190 en repli sans UID")
		}
	})
}

func TestBuildSendMessage(t *testing.T) {
	cascadeID := "casc-1234-abcd"
	promptText := "Hello Antigravity!"
	apiKey := "test-api-key"
	sessionID := "sess-1"
	modelUID := "gemini-3.0-flash-high"

	buf := BuildSendMessage(cascadeID, promptText, apiKey, sessionID, modelUID, 0)
	fields := DecodeFields(buf)

	if len(fields) < 2 {
		t.Fatalf("Attendu au moins 2 champs dans BuildSendMessage")
	}

	if string(fields[0].Bytes) != cascadeID {
		t.Errorf("Attendu cascadeID=%s dans champ #1, reçu=%s", cascadeID, string(fields[0].Bytes))
	}

	// Le LS 2.8.0 exige cascade_config (champ 5) avec un modèle demandé :
	// format validé 1/15 (plan_model + requested_model ModelOrAlias) —
	// l'ancien layout 5/6 est rejeté (« neither PlanModel nor RequestedModel »).
	foundConfig := false
	for _, f := range fields {
		if f.Num == 5 && len(f.Bytes) > 0 {
			foundConfig = true
			inner := DecodeFields(f.Bytes)
			for _, sub := range inner {
				if sub.Num == 1 { // planner_config (CascadePlannerConfig)
					planner := DecodeFields(sub.Bytes)
					foundPlan := false
					foundReq := false
					for _, p := range planner {
						if p.Num == 1 && p.Varint != 0 {
							foundPlan = true // plan_model
						}
						if p.Num == 15 { // requested_model (ModelOrAlias)
							reqModel := DecodeFields(p.Bytes)
							for _, rm := range reqModel {
								if rm.Num == 2 && rm.Varint == 1 {
									foundReq = true // alias = CASCADE_BASE
								}
							}
						}
					}
					if !foundPlan {
						t.Errorf("cascade_config: plan_model (planner field 1) manquant")
					}
					if !foundReq {
						t.Errorf("cascade_config: requested_model alias CASCADE_BASE (planner field 15) manquant")
					}
				}
			}
		}
	}
	if !foundConfig {
		t.Errorf("cascade_config (champ 5) manquant dans BuildSendMessage")
	}
}

func TestVarintEncoding(t *testing.T) {
	w := &writer{}
	w.varint(300)

	val, n := readVarint(w.b, 0)
	if val != 300 {
		t.Errorf("Attendu varint=300, reçu=%d", val)
	}
	if n != len(w.b) {
		t.Errorf("Attendu octets luss=%d, reçu=%d", len(w.b), n)
	}
}

func TestBuildHandleCascadeUserInteraction_RoundTrip(t *testing.T) {
	cascadeID := "casc-111"
	trajID := "traj-222"
	step := uint32(3)

	oneof := BuildRunCommandInteraction(true, "echo hi", "")
	buf := BuildHandleCascadeUserInteraction(cascadeID, trajID, step, InteractionRunCommand, oneof)

	fields := DecodeFields(buf)
	if len(fields) != 2 || fields[0].Num != 1 || string(fields[0].Bytes) != cascadeID {
		t.Fatalf("wrapper invalide: %+v", fields)
	}
	if fields[1].Num != 2 {
		t.Fatalf("interaction attendue dans le champ #2, reçu #%d", fields[1].Num)
	}

	sub := DecodeFields(fields[1].Bytes)
	var gotTraj string
	var gotStep uint32
	var gotOneof int
	var gotConfirm bool
	for _, f := range sub {
		switch f.Num {
		case 1:
			gotTraj = string(f.Bytes)
		case 2:
			gotStep = uint32(f.Varint)
		case InteractionRunCommand:
			gotOneof = f.Num
			for _, inner := range DecodeFields(f.Bytes) {
				if inner.Num == 1 {
					gotConfirm = inner.Varint == 1
				}
			}
		}
	}
	if gotTraj != trajID || gotStep != step || gotOneof != InteractionRunCommand || !gotConfirm {
		t.Fatalf("round-trip KO: traj=%s step=%d oneof=%d confirm=%v", gotTraj, gotStep, gotOneof, gotConfirm)
	}
}

func TestBuildHandleStreamingCommand(t *testing.T) {
	cmd := "/model gemini-3-pro"
	buf := BuildHandleStreamingCommand(cmd, CommandRequestSourceTerminal)
	fields := DecodeFields(buf)
	if len(fields) != 2 {
		t.Fatalf("Attendu 2 champs (command_text + request_source), reçu %d: %+v", len(fields), fields)
	}
	var gotText string
	var gotSource uint64
	for _, f := range fields {
		switch f.Num {
		case 8:
			gotText = string(f.Bytes)
		case 9:
			gotSource = f.Varint
		}
	}
	if gotText != cmd {
		t.Errorf("Attendu command_text=%q, reçu=%q", cmd, gotText)
	}
	if gotSource != CommandRequestSourceTerminal {
		t.Errorf("Attendu request_source=%d (TERMINAL), reçu=%d", CommandRequestSourceTerminal, gotSource)
	}
}
