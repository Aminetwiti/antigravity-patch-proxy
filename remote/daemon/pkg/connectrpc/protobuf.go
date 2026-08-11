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
func BuildStartCascade(workspaceURI string, requestedModel uint64) []byte {
	w := &writer{}
	w.varintField(4, 1)
	w.varintField(5, 1)
	w.stringField(8, workspaceURI)
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

// SubmitToolApproval : champs à confirmer par rétro-ingénierie (Phase 1).
// Placeholder — approuver par callId + décision (1=allow, 2=deny).
func BuildSubmitToolApproval(cascadeID, callID string, decision uint64) []byte {
	w := &writer{}
	w.stringField(1, cascadeID)
	w.stringField(2, callID)
	w.varintField(3, decision)
	return w.b
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


