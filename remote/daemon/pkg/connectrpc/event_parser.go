package connectrpc

import (
	"strings"
)

type EventKind string

const (
	EventKindText             EventKind = "text"
	EventKindThinking         EventKind = "thinking"
	EventKindStatusChange     EventKind = "status_change"
	EventKindApprovalRequired EventKind = "approval_required"
)

type StreamEvent struct {
	Kind      EventKind `json:"kind"`
	Delta     string    `json:"delta,omitempty"`
	Status    string    `json:"status,omitempty"`
	CascadeID string    `json:"cascadeId,omitempty"`
	CallID    string    `json:"callId,omitempty"`
	Tool      string    `json:"tool,omitempty"`
	Detail    string    `json:"detail,omitempty"`
}

// ParseFrameEvents analyse une frame protobuf gRPC-Web et extrait les événements lisibles.
func ParseFrameEvents(raw []byte, cascadeID string) []StreamEvent {
	var events []StreamEvent
	fields := DecodeFields(raw)

	for _, f := range fields {
		if f.WireType != 2 || len(f.Bytes) == 0 {
			continue
		}
		s := strings.TrimSpace(string(f.Bytes))
		if s == "" {
			continue
		}

		// Détection empirique des blocs d'approbation ou de texte
		if strings.Contains(s, "run_command") || strings.Contains(s, "write_to_file") {
			events = append(events, StreamEvent{
				Kind:      EventKindApprovalRequired,
				CascadeID: cascadeID,
				Tool:      extractToolName(s),
				Detail:    s,
			})
		} else if isPrintable(s) && len(s) > 1 {
			if strings.Contains(s, "<thought>") || strings.Contains(s, "Thinking...") {
				events = append(events, StreamEvent{
					Kind:      EventKindThinking,
					Delta:     s,
					CascadeID: cascadeID,
				})
			} else {
				events = append(events, StreamEvent{
					Kind:      EventKindText,
					Delta:     s,
					CascadeID: cascadeID,
				})
			}
		}
	}

	return events
}

func extractToolName(s string) string {
	if strings.Contains(s, "run_command") {
		return "run_command"
	}
	if strings.Contains(s, "write_to_file") {
		return "write_to_file"
	}
	return "generic_tool"
}

func isPrintable(s string) bool {
	for _, r := range s {
		if r < 0x20 || r > 0x7e {
			if r != '\n' && r != '\t' && r != '\r' {
				return false
			}
		}
	}
	return true
}

