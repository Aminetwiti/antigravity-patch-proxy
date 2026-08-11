package connectrpc

import (
	"encoding/binary"
	"fmt"
	"os"
	"testing"
)

func TestDebugTrajectoryParsing(t *testing.T) {
	raw, err := os.ReadFile("testdata/hub_trajectories.bin")
	if err != nil {
		t.Skipf("fixture absente: %v", err)
	}
	payload := raw
	for len(payload) >= 5 {
		length := int(binary.BigEndian.Uint32(payload[1:5]))
		if length <= 0 || 5+length > len(payload) {
			break
		}
		if payload[0]&0x80 == 0 {
			payload = payload[5 : 5+length]
			break
		}
		payload = payload[5+length:]
	}
	fields := DecodeFields(payload)
	t.Logf("top-level fields: %d", len(fields))
	for i, f := range fields {
		if i > 3 {
			break
		}
		t.Logf("field[%d]: %s", i, f.String())
	}
	// Décode le premier summary manuellement
	if len(fields) > 0 && fields[0].WireType == 2 {
		sub := DecodeFields(fields[0].Bytes)
		t.Logf("summary fields: %d", len(sub))
		for i, f := range sub {
			if i > 8 {
				break
			}
			t.Logf("  sub[%d]: %s printable=%v", i, f.String(), IsPrintable(string(f.Bytes)))
		}
		// findTitle sur le champ 2
		for _, f := range sub {
			if f.Num == 2 && f.WireType == 2 {
				t.Logf("  findTitle(champ2 %d octets) = %q", len(f.Bytes), findTitle(f.Bytes))
				t.Logf("  isTitleLike(texte direct) = %v", isTitleLike([]byte("Hello from remote CLI. This is Marche 1 validation.")))
				break
			}
		}
	}
	summaries := ParseTrajectories(raw)
	t.Logf("totales: %d, avec titre non vide: %d", len(summaries), countTitles(summaries))
	for _, s := range summaries[:3] {
		t.Logf("  %s | %q | %s", s.CascadeID, s.Title, s.Workspace)
	}
}

func countTitles(ss []TrajectorySummary) int {
	n := 0
	for _, s := range ss {
		if s.Title != "" && s.Title != "Cascade Session" {
			n++
		}
	}
	return n
}

func TestDebugStructuredMessage(t *testing.T) {
	w := &writer{}
	w.stringField(1, "2947da31-5b79-4741-9bb5-34ddbae3de18")
	w.stringField(2, "Greeting In Python")
	w.varintField(5, 1)
	w.varintField(22, 4)

	fields := DecodeFields(w.b)
	t.Logf("champs décodés: %d", len(fields))
	for i, f := range fields {
		t.Logf("  [%d] %s", i, f.String())
	}
	t.Logf("isStructuredTrajectory = %v", isStructuredTrajectory(fields))
	blob := fields[0].Bytes
	t.Logf("trajectoryFromBlob(%d octets) = %+v", len(blob), trajectoryFromBlob(blob))
	fmt.Sprint()

	// Version enveloppée (comme la capture réelle) : entrée dans repeated #1.
	wrapped := &writer{}
	wrapped.bytesField(1, w.b)
	fieldsW := DecodeFields(wrapped.b)
	t.Logf("wrapped fields: %d", len(fieldsW))
	blobW := fieldsW[0].Bytes
	t.Logf("blobW = %d octets, isStructured=%v", len(blobW), isStructuredTrajectory(DecodeFields(blobW)))
	inner := DecodeFields(blobW)
	for i, f := range inner {
		t.Logf("  inner[%d] %s", i, f.String())
	}
	t.Logf("trajectoryFromBlob(wrapped) = %+v", trajectoryFromBlob(blobW))
}
