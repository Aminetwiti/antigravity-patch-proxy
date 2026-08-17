package connectrpc

import (
	"testing"
)

func TestBuildStartBattleMode(t *testing.T) {
	blob := BuildStartBattleMode("file:///workspace/repo", "Compare implementations", "claude-3-7-sonnet", 312, "gemini-2-5-pro", 246)
	if len(blob) == 0 {
		t.Fatalf("BuildStartBattleMode produced empty bytes")
	}

	fields := DecodeFields(blob)
	if len(fields) < 4 {
		t.Fatalf("Expected at least 4 fields, got %d", len(fields))
	}

	// Field 1 = workspaceURI
	if fields[0].Num != 1 || string(fields[0].Bytes) != "file:///workspace/repo" {
		t.Errorf("Field 1 mismatch: %s", string(fields[0].Bytes))
	}
	// Field 2 = prompt
	if fields[1].Num != 2 || string(fields[1].Bytes) != "Compare implementations" {
		t.Errorf("Field 2 mismatch: %s", string(fields[1].Bytes))
	}
}

func TestBuildGetBattleWorktreeDiff(t *testing.T) {
	blob := BuildGetBattleWorktreeDiff("file:///workspace/repo")
	fields := DecodeFields(blob)
	if len(fields) != 1 || fields[0].Num != 1 || string(fields[0].Bytes) != "file:///workspace/repo" {
		t.Errorf("Field 1 mismatch for GetBattleWorktreeDiff")
	}
}

func TestBuildEliminateBattleModeArm(t *testing.T) {
	blob := BuildEliminateBattleModeArm("arm_b")
	fields := DecodeFields(blob)
	if len(fields) != 1 || fields[0].Num != 1 || string(fields[0].Bytes) != "arm_b" {
		t.Errorf("Field 1 mismatch for EliminateBattleModeArm")
	}
}

func TestBuildEndBattleMode(t *testing.T) {
	blob := BuildEndBattleMode("arm_a", 2) // 2 = SAFE_MERGE
	fields := DecodeFields(blob)
	if len(fields) != 2 {
		t.Fatalf("Expected 2 fields, got %d", len(fields))
	}
	if fields[0].Num != 1 || string(fields[0].Bytes) != "arm_a" {
		t.Errorf("Field 1 mismatch: %s", string(fields[0].Bytes))
	}
	if fields[1].Num != 2 || fields[1].Varint != 2 {
		t.Errorf("Field 2 mismatch: %d", fields[1].Varint)
	}
}

func TestBuildDumpFlightRecorder(t *testing.T) {
	blob := BuildDumpFlightRecorder()
	if len(blob) != 0 {
		t.Errorf("Expected 0 bytes for empty request, got %d", len(blob))
	}
}

func TestBuildMcpLifecycle(t *testing.T) {
	refresh := BuildRefreshMcpServers()
	if len(refresh) != 0 {
		t.Errorf("Expected 0 bytes for RefreshMcpServers, got %d", len(refresh))
	}

	oauth := BuildCompleteMcpOAuth("coolify", "auth-token-xyz")
	fields := DecodeFields(oauth)
	if len(fields) != 2 || string(fields[0].Bytes) != "coolify" || string(fields[1].Bytes) != "auth-token-xyz" {
		t.Errorf("CompleteMcpOAuth fields mismatch")
	}

	disconnect := BuildDisconnectMcpOAuth("coolify")
	fieldsDisc := DecodeFields(disconnect)
	if len(fieldsDisc) != 1 || string(fieldsDisc[0].Bytes) != "coolify" {
		t.Errorf("DisconnectMcpOAuth fields mismatch")
	}
}
