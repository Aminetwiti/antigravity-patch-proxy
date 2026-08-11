package connectrpc

import (
	"fmt"
)

// Encodage protobuf manuel — pas de bibliothèque (règle AGENTS.md).
// Wire format : varint fields (key = (fieldNum << 3) | wireType).
// wireType 0 = varint, 2 = length-delimited.

type writer struct {
	b []byte
}

func (w *writer) varint(v uint64) {
	for v >= 0x80 {
		w.b = append(w.b, byte(v)|0x80)
		v >>= 7
	}
	w.b = append(w.b, byte(v))
}

func (w *writer) key(fieldNum, wireType int) {
	w.varint(uint64(fieldNum<<3 | wireType))
}

func (w *writer) varintField(fieldNum int, v uint64) {
	w.key(fieldNum, 0)
	w.varint(v)
}

func (w *writer) stringField(fieldNum int, s string) {
	w.key(fieldNum, 2)
	w.varint(uint64(len(s)))
	w.b = append(w.b, s...)
}

func (w *writer) bytesField(fieldNum int, data []byte) {
	w.key(fieldNum, 2)
	w.varint(uint64(len(data)))
	w.b = append(w.b, data...)
}

// StartCascadeRequest : field 4 source=1, 5 trajectory_type=1,
// 8 workspace_uris (string), 14 requested_model (varint).
// BuildStartCascade génère un message StartCascadeRequest brut.
func BuildStartCascade(workspaceURI, projectID string, requestedModel uint64) []byte {
	w := &writer{}
	w.varintField(4, 1)
	w.varintField(5, 1)
	if projectID != "" {
		envW := &writer{}
		envW.stringField(1, projectID)
		envW.bytesField(4, []byte{}) // defaultProjectEnvironment
		w.bytesField(17, envW.b)
	} else {
		w.stringField(8, workspaceURI)
	}
	w.varintField(14, requestedModel)
	return w.b
}

// SendUserCascadeMessageRequest : field 1 cascade_id, field 2 items[]
// où chaque item est TextOrScopeItem{ 1: chunk.text }.
func BuildSendMessage(cascadeID, text string) []byte {
	item := &writer{}
	item.stringField(1, text)

	w := &writer{}
	w.stringField(1, cascadeID)
	w.bytesField(2, item.b)
	return w.b
}

// Champs oneof de CascadeUserInteraction (vérifiés dans cortex_pb.ts).
const (
	InteractionRunCommand     = 5  // CascadeRunCommandInteraction
	InteractionOpenBrowserURL = 6  // CascadeOpenBrowserUrlInteraction
	InteractionFilePermission = 19 // FilePermissionInteraction
	InteractionPermission     = 21 // PermissionInteraction
	InteractionApproval       = 23 // ApprovalInteraction
)

// BuildRunCommandInteraction : {1: confirm, 2: proposed, 3: submitted}.
func BuildRunCommandInteraction(confirm bool, proposed, submitted string) []byte {
	w := &writer{}
	w.varintField(1, boolToUint64(confirm))
	w.stringField(2, proposed)
	if submitted != "" {
		w.stringField(3, submitted)
	}
	return w.b
}

// BuildPermissionInteraction : {1: allow, 2: scope} (le scope 2 = CONVERSATION).
func BuildPermissionInteraction(allow bool, scope uint64) []byte {
	w := &writer{}
	w.varintField(1, boolToUint64(allow))
	w.varintField(2, scope)
	return w.b
}

// BuildFilePermissionInteraction : {1: allow, 2: scope, 3: absolute_path_uri}.
func BuildFilePermissionInteraction(allow bool, scope uint64, pathURI string) []byte {
	w := &writer{}
	w.varintField(1, boolToUint64(allow))
	w.varintField(2, scope)
	w.stringField(3, pathURI)
	return w.b
}

// BuildApprovalInteraction : {1: confirm} — fallback générique.
func BuildApprovalInteraction(confirm bool) []byte {
	w := &writer{}
	w.varintField(1, boolToUint64(confirm))
	return w.b
}

// BuildHandleCascadeUserInteraction construit le payload de
// HandleCascadeUserInteractionRequest : {1: cascade_id, 2: interaction}
// où interaction = {1: trajectory_id, 2: step_index, <oneofField>: oneofPayload}.
func BuildHandleCascadeUserInteraction(cascadeID, trajectoryID string, stepIndex uint32, oneofField int, oneofPayload []byte) []byte {
	interaction := &writer{}
	interaction.stringField(1, trajectoryID)
	interaction.varintField(2, uint64(stepIndex))
	interaction.bytesField(oneofField, oneofPayload)

	w := &writer{}
	w.stringField(1, cascadeID)
	w.bytesField(2, interaction.b)
	return w.b
}

func boolToUint64(b bool) uint64 {
	if b {
		return 1
	}
	return 0
}

// DecodeFields extrait les champs de premier niveau d'un message protobuf.
func DecodeFields(buf []byte) []Field {
	var fields []Field
	offset := 0
	for offset < len(buf) {
		key, n := readVarint(buf, offset)
		offset = n
		fieldNum := int(key >> 3)
		wireType := int(key & 7)
		switch wireType {
		case 0:
			v, n := readVarint(buf, offset)
			fields = append(fields, Field{Num: fieldNum, WireType: wireType, Varint: v})
			offset = n
		case 2:
			length, n := readVarint(buf, offset)
			offset = n
			if offset+int(length) > len(buf) {
				fields = append(fields, Field{Num: fieldNum, WireType: wireType, Bytes: buf[offset:]})
				offset = len(buf)
			} else {
				fields = append(fields, Field{Num: fieldNum, WireType: wireType, Bytes: buf[offset : offset+int(length)]})
				offset += int(length)
			}
		default:
			fields = append(fields, Field{Num: fieldNum, WireType: wireType, Bytes: buf[offset:]})
			offset = len(buf)
		}
	}
	return fields
}

type Field struct {
	Num      int
	WireType int
	Varint   uint64
	Bytes    []byte
}

func (f Field) String() string {
	if f.WireType == 0 {
		return fmt.Sprintf("#%d:%d=%d", f.Num, f.WireType, f.Varint)
	}
	return fmt.Sprintf("#%d:%d=%dB", f.Num, f.WireType, len(f.Bytes))
}

func readVarint(buf []byte, offset int) (uint64, int) {
	var result uint64
	var shift uint
	for offset < len(buf) {
		b := buf[offset]
		result |= uint64(b&0x7f) << shift
		offset++
		if b&0x80 == 0 {
			break
		}
		shift += 7
		if shift > 63 {
			break
		}
	}
	return result, offset
}


