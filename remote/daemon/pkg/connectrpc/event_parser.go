package connectrpc

import (
	"strings"
	"unicode"
)

type EventKind string

const (
	EventKindText             EventKind = "text"
	EventKindThinking         EventKind = "thinking"
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

	// 1. Vérification pour les frames d'interaction directe (HandleCascadeUserInteraction: field 1 = cascadeID, field 2 = interaction {1: trajectoryId, 2: stepIndex, 5..23: payload})
	for _, f := range fields {
		if f.Num == 2 && f.WireType == 2 {
			subFields := DecodeFields(f.Bytes)
			var trajectoryID string
			var stepIndex uint32
			var isInteraction bool
			var detectedTool string
			var detail string

			for _, sub := range subFields {
				if sub.WireType == 0 && sub.Num == 2 {
					stepIndex = uint32(sub.Varint)
				}
				if sub.WireType == 2 && sub.Num == 1 && len(sub.Bytes) == 36 {
					trajectoryID = string(sub.Bytes)
				}
				if sub.Num == InteractionRunCommand || sub.Num == InteractionOpenBrowserURL ||
					sub.Num == InteractionFilePermission || sub.Num == InteractionPermission ||
					sub.Num == InteractionApproval {
					isInteraction = true
					if sub.Num == InteractionRunCommand {
						detectedTool = "run_command"
					} else if sub.Num == InteractionFilePermission {
						detectedTool = "write_to_file"
					}
					if len(sub.Bytes) > 0 {
						detail = string(sub.Bytes)
					}
				}
			}
			if isInteraction {
				return []StreamEvent{{
					Kind:         EventKindApprovalRequired,
					CascadeID:    cascadeID,
					TrajectoryID: trajectoryID,
					StepIndex:    stepIndex,
					Tool:         detectedTool,
					Detail:       detail,
				}}
			}
		}
	}

	for _, f := range fields {
		if f.WireType != 2 || len(f.Bytes) == 0 {
			continue
		}
		s := strings.TrimSpace(string(f.Bytes))
		if s == "" {
			continue
		}

		if IsPrintable(s) && len(s) > 0 {
			trimmed := strings.TrimSpace(s)
			isJSONApproval := strings.HasPrefix(trimmed, "{") && strings.HasSuffix(trimmed, "}") &&
				(strings.Contains(trimmed, `"tool"`) || strings.Contains(trimmed, `"callId"`) || strings.Contains(trimmed, `"requestedInteraction"`) || strings.Contains(trimmed, `"command"`))

			if isJSONApproval {
				events = append(events, StreamEvent{
					Kind:         EventKindApprovalRequired,
					CascadeID:    cascadeID,
					TrajectoryID: firstUUID(s),
					Tool:         extractToolName(s),
					Detail:       s,
				})
			} else if strings.Contains(s, "<thought>") || strings.Contains(s, "Thinking...") {
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
			continue
		}

		// Si f.Bytes n'est pas du texte brut imprimable, c'est un sous-message protobuf binaire
		subFields := DecodeFields(f.Bytes)
		var trajectoryID string
		var stepIndex uint32
		var isInteraction bool
		var detectedTool string

		for _, sub := range subFields {
			if sub.WireType == 0 && sub.Num == 2 {
				stepIndex = uint32(sub.Varint)
			}
			if sub.WireType == 2 && sub.Num == 1 && len(sub.Bytes) == 36 {
				trajectoryID = string(sub.Bytes)
			}
			if sub.Num == InteractionRunCommand || sub.Num == InteractionOpenBrowserURL ||
				sub.Num == InteractionFilePermission || sub.Num == InteractionPermission ||
				sub.Num == InteractionApproval {
				isInteraction = true
				if sub.Num == InteractionRunCommand {
					detectedTool = "run_command"
				} else if sub.Num == InteractionFilePermission {
					detectedTool = "write_to_file"
				}
			}
			if sub.WireType == 2 && sub.Num == 2 && len(sub.Bytes) > 0 {
				nested := DecodeFields(sub.Bytes)
				for _, nf := range nested {
					if nf.WireType == 0 && nf.Num == 2 {
						stepIndex = uint32(nf.Varint)
					}
					if nf.WireType == 2 && nf.Num == 1 && len(nf.Bytes) == 36 {
						trajectoryID = string(nf.Bytes)
					}
					if nf.Num == InteractionRunCommand || nf.Num == InteractionOpenBrowserURL ||
						nf.Num == InteractionFilePermission || nf.Num == InteractionPermission ||
						nf.Num == InteractionApproval {
						isInteraction = true
						if nf.Num == InteractionRunCommand {
							detectedTool = "run_command"
						} else if nf.Num == InteractionFilePermission {
							detectedTool = "write_to_file"
						}
					}
				}
			}
		}

		if isInteraction {
			if detectedTool == "" {
				detectedTool = extractToolName(s)
			}
			events = append(events, StreamEvent{
				Kind:         EventKindApprovalRequired,
				CascadeID:    cascadeID,
				TrajectoryID: trajectoryID,
				StepIndex:    stepIndex,
				Tool:         detectedTool,
				Detail:       s,
			})
		} else {
			for _, sub := range subFields {
				if sub.WireType == 2 && len(sub.Bytes) > 0 && sub.Num != 1 {
					st := strings.TrimSpace(string(sub.Bytes))
					if IsPrintable(st) && len(st) > 0 {
						if strings.Contains(st, "run_command") || strings.Contains(st, "write_to_file") || strings.Contains(st, "read_file") || strings.Contains(st, "edit_file") || strings.Contains(st, "list_files") || strings.Contains(st, "search_files") || strings.Contains(st, "ask_question") || strings.Contains(st, "ask_user") {
							events = append(events, StreamEvent{
								Kind:         EventKindApprovalRequired,
								CascadeID:    cascadeID,
								TrajectoryID: trajectoryID,
								StepIndex:    stepIndex,
								Tool:         extractToolName(st),
								Detail:       st,
							})
						} else if strings.Contains(st, "<thought>") || strings.Contains(st, "Thinking...") {
							events = append(events, StreamEvent{
								Kind:      EventKindThinking,
								Delta:     st,
								CascadeID: cascadeID,
							})
						} else {
							events = append(events, StreamEvent{
								Kind:      EventKindText,
								Delta:     st,
								CascadeID: cascadeID,
							})
						}
					}
				}
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
	// Outils de lecture/recherche : le blob JSON contient la clé de l'outil
	// ("read_file": "path"). Sans clé connue → generic_tool (non auto-accepté).
	for _, k := range []string{"read_file", "edit_file", "list_files", "search_files", "grep", "glob", "fetch"} {
		if strings.Contains(s, k) {
			return k
		}
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
