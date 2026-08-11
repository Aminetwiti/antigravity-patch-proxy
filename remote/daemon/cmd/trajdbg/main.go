// trajdbg : débug one-off pour l'analyse des trajectoires réelles.
package main

import (
	"encoding/binary"
	"fmt"
	"os"
	"strings"

	"github.com/antigravity/remote-daemon/pkg/connectrpc"
)

func main() {
	raw, _ := os.ReadFile("pkg/connectrpc/testdata/hub_trajectories.bin")
	payload := raw
	var msgs [][]byte
	for len(payload) >= 5 {
		length := int(binary.BigEndian.Uint32(payload[1:5]))
		if length <= 0 || 5+length > len(payload) {
			break
		}
		if payload[0]&0x80 == 0 {
			msgs = append(msgs, payload[5:5+length])
		}
		payload = payload[5+length:]
	}
	count := 0
	for _, msg := range msgs {
		for _, f := range connectrpc.DecodeFields(msg) {
			if f.Num != 1 || f.WireType != 2 {
				continue
			}
			blob := f.Bytes
			id := firstUUID(string(blob))
			if id == "" {
				continue
			}
			count++
			if count <= 6 {
				fmt.Printf("=== %s (len=%d) ===\n", id, len(blob))
				hexdump(blob, 200)
			}
			title := titleFromBlob(blob)
			fmt.Printf("%s | title=%q\n", id, title)
		}
	}
}

func hexdump(b []byte, max int) {
	if len(b) > max {
		b = b[:max]
	}
	for i := 0; i < len(b); i += 16 {
		end := i + 16
		if end > len(b) {
			end = len(b)
		}
		hexPart := ""
		for j := i; j < end; j++ {
			hexPart += fmt.Sprintf("%02x ", b[j])
		}
		asciiPart := ""
		for j := i; j < end; j++ {
			c := b[j]
			if c >= 0x20 && c < 0x7f {
				asciiPart += string(c)
			} else {
				asciiPart += "·"
			}
		}
		fmt.Printf("%04x  %-48s %s\n", i, hexPart, asciiPart)
	}
}

func firstUUID(s string) string {
	for i := 0; i+36 <= len(s); i++ {
		if isUUID(s[i : i+36]) {
			return s[i : i+36]
		}
	}
	return ""
}

func isUUID(s string) bool {
	if len(s) != 36 {
		return false
	}
	for i := 0; i < 36; i++ {
		c := s[i]
		if i == 8 || i == 13 || i == 18 || i == 23 {
			if c != '-' {
				return false
			}
			continue
		}
		if !strings.ContainsRune("0123456789abcdefABCDEF", rune(c)) {
			return false
		}
	}
	return true
}

func titleFromBlob(blob []byte) string {
	text := strings.TrimSpace(string(blob))
	// strip " $uuid" prefix
	t := text
	if i := strings.Index(t, "$"); i >= 0 {
		t = t[i+1:]
	}
	if m := uuidIndex(t); m >= 0 {
		t = t[m+36:]
	}
	t = strings.TrimLeft(t, " \t\n\xb7\x00\x01\x02")
	if i := strings.IndexByte(t, '\n'); i >= 0 {
		t = t[:i]
	}
	// candidate : runes imprimables
	var best string
	cur := ""
	for _, r := range t {
		if (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == ' ' || r == '.' || r == '_' || r == '-' || r == '\'' || r == ',' || r == ':' || r == '/' || (r >= 0xC0 && r <= 0xFF) {
			cur += string(r)
		} else {
			if len(cur) > len(best) {
				best = cur
			}
			cur = ""
		}
	}
	if len(cur) > len(best) {
		best = cur
	}
	best = strings.TrimSpace(best)
	if len(best) > 60 {
		best = best[:60]
	}
	return best
}

func uuidIndex(s string) int {
	for i := 0; i+36 <= len(s); i++ {
		if isUUID(s[i : i+36]) {
			return i
		}
	}
	return -1
}
