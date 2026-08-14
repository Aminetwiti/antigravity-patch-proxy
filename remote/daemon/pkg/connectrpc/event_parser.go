package connectrpc

import (
	"strings"
	"unicode"
)

type EventKind string

const (
	EventKindText             EventKind = "text"
	EventKindThinking         EventKind = "thinking"
	EventKindStatusChange     EventKind = "status_change"
	EventKindApprovalRequired EventKind = "approval_required"
)

type StreamEvent struct {
	Kind         EventKind `json:"kind"`
	Delta        string    `json:"delta,omitempty"`
	Status       string    `json:"status,omitempty"`
	CascadeID    string    `json:"cascadeId,omitempty"`
	TrajectoryID string    `json:"trajectoryId,omitempty"`
	StepIndex    uint32    `json:"stepIndex,omitempty"`
	CallID       string    `json:"callId,omitempty"`
	Tool         string    `json:"tool,omitempty"`
	Detail       string    `json:"detail,omitempty"`
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
		if strings.Contains(s, "run_command") || strings.Contains(s, "write_to_file") || strings.Contains(s, "ask_question") || strings.Contains(s, "ask_user") {
			ev := StreamEvent{
				Kind:      EventKindApprovalRequired,
				CascadeID: cascadeID,
				Tool:      extractToolName(s),
				Detail:    s,
			}
			// Corrélation (Bloc A) : step_index (varint #2) + trajectory_id (UUID #1)
			// sont indispensables pour répondre via HandleCascadeUserInteraction.
			for _, sub := range DecodeFields(f.Bytes) {
				if sub.WireType == 0 && sub.Num == 2 {
					ev.StepIndex = uint32(sub.Varint)
				}
				if sub.WireType == 2 && sub.Num == 1 && len(sub.Bytes) == 36 {
					ev.TrajectoryID = string(sub.Bytes)
				}
			}
			if ev.TrajectoryID == "" {
				// Fallback : le premier UUID du blob d'approbation.
				ev.TrajectoryID = firstUUID(s)
			}
			events = append(events, ev)
		} else if IsPrintable(s) && len(s) > 1 {
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
	if strings.Contains(s, "ask_question") || strings.Contains(s, "ask_user") {
		return "ask_question"
	}
	if strings.Contains(s, "run_command") {
		return "run_command"
	}
	if strings.Contains(s, "write_to_file") {
		return "write_to_file"
	}
	return "generic_tool"
}

// IsPrintable vérifie qu'une chaîne ne contient que des caractères imprimables
// (ASCII + UTF-8 : accents, CJK, symboles) ou des retours à la ligne.
// Utilisé pour filtrer les octets binaires des flux protobuf.
func IsPrintable(s string) bool {
	for _, r := range s {
		if unicode.IsPrint(r) {
			continue
		}
		if r == '\n' || r == '\t' || r == '\r' {
			continue
		}
		return false
	}
	return true
}

