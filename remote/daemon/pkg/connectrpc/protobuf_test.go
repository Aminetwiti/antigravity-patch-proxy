package connectrpc

import (
	"testing"
)

func TestBuildStartCascadeAndDecode(t *testing.T) {
	workspaceURI := "file:///C:/test_project"
	requestedModel := uint64(190)

	buf := BuildStartCascade(workspaceURI, "", requestedModel)
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

func TestBuildSendMessage(t *testing.T) {
	cascadeID := "casc-1234-abcd"
	promptText := "Hello Antigravity!"

	buf := BuildSendMessage(cascadeID, promptText)
	fields := DecodeFields(buf)

	if len(fields) < 2 {
		t.Fatalf("Attendu au moins 2 champs dans BuildSendMessage")
	}

	if string(fields[0].Bytes) != cascadeID {
		t.Errorf("Attendu cascadeID=%s dans champ #1, reçu=%s", cascadeID, string(fields[0].Bytes))
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
