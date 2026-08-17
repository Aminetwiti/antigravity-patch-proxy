package connectrpc

import (
	"testing"
)

func TestParseFrameEvents(t *testing.T) {
	// Frame protobuf contenant "run_command"
	raw := []byte{0x0a, 0x0f, 'r', 'u', 'n', '_', 'c', 'o', 'm', 'm', 'a', 'n', 'd', ' ', 'l', 's'}
	events := ParseFrameEvents(raw, "cascade-123")

	if len(events) == 0 {
		t.Fatalf("Attendu au moins 1 événement, reçu 0")
	}

	if events[0].Kind != EventKindApprovalRequired {
		t.Errorf("Attendu Kind=%s, reçu=%s", EventKindApprovalRequired, events[0].Kind)
	}

	if events[0].Tool != "run_command" {
		t.Errorf("Attendu Tool=run_command, reçu=%s", events[0].Tool)
	}
}

func TestParseFrameStructuredInteraction(t *testing.T) {
	// Construction d'une interaction structurée via BuildHandleCascadeUserInteraction
	payload := BuildRunCommandInteraction(true, "npm test", "")
	rawInteraction := BuildHandleCascadeUserInteraction("cascade-abc", "11112222-3333-4444-5555-666677778888", 42, InteractionRunCommand, payload)
	
	events := ParseFrameEvents(rawInteraction, "cascade-abc")
	if len(events) == 0 {
		t.Fatalf("Attendu au moins 1 événement d'interaction structurée, reçu 0")
	}

	if events[0].Kind != EventKindApprovalRequired {
		t.Errorf("Attendu Kind=%s, reçu=%s", EventKindApprovalRequired, events[0].Kind)
	}
	if events[0].StepIndex != 42 {
		t.Errorf("Attendu StepIndex=42, reçu=%d", events[0].StepIndex)
	}
	if events[0].TrajectoryID != "11112222-3333-4444-5555-666677778888" {
		t.Errorf("Attendu TrajectoryID=11112222-3333-4444-5555-666677778888, reçu=%s", events[0].TrajectoryID)
	}
}

func TestIsPrintable(t *testing.T) {
	if !IsPrintable("Hello World 123!\n") {
		t.Errorf("IsPrintable devrait être true pour du texte imprimable")
	}
	if IsPrintable(string([]byte{0x01, 0x02, 0x03})) {
		t.Errorf("IsPrintable devrait être false pour des octets binaires de contrôle")
	}
}

func TestExtractToolName(t *testing.T) {
	if name := extractToolName("executing run_command now"); name != "run_command" {
		t.Errorf("Attendu run_command, reçu=%s", name)
	}
	if name := extractToolName("modifying write_to_file"); name != "write_to_file" {
		t.Errorf("Attendu write_to_file, reçu=%s", name)
	}
	if name := extractToolName(`{"read_file":"src/main.dart"}`); name != "read_file" {
		t.Errorf("Attendu read_file, reçu=%s", name)
	}
	if name := extractToolName(`{"edit_file":"src/main.dart"}`); name != "edit_file" {
		t.Errorf("Attendu edit_file, reçu=%s", name)
	}
	if name := extractToolName(`{"search_files":"todo"}`); name != "search_files" {
		t.Errorf("Attendu search_files, reçu=%s", name)
	}
	if name := extractToolName("unknown action"); name != "generic_tool" {
		t.Errorf("Attendu generic_tool, reçu=%s", name)
	}
}
