// protodump affiche l'arbre protobuf d'un fichier binaire gRPC-Web.
// Usage: go run ./cmd/protodump <fichier.bin> [profondeur_max]
package main

import (
	"encoding/binary"
	"fmt"
	"os"
	"strings"

	"github.com/antigravity/remote-daemon/pkg/connectrpc"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("usage: protodump <file.bin> [depth]")
		os.Exit(1)
	}
	raw, err := os.ReadFile(os.Args[1])
	if err != nil {
		fmt.Println("read:", err)
		os.Exit(1)
	}
	depth := 3
	if len(os.Args) > 2 {
		fmt.Sscanf(os.Args[2], "%d", &depth)
	}

	// Dé-framing gRPC-Web : flags(1) + longueur BE(4) + payload
	payload := raw
	for len(payload) >= 5 {
		length := int(binary.BigEndian.Uint32(payload[1:5]))
		if length <= 0 || 5+length > len(payload) {
			break
		}
		fmt.Printf("=== grpc-web frame flags=0x%02x len=%d ===\n", payload[0], length)
		dump(payload[5:5+length], 0, depth)
		payload = payload[5+length:]
	}
	if len(payload) > 0 {
		fmt.Printf("=== restant %d octets (trailers?) ===\n", len(payload))
		dump(payload, 0, depth)
	}
}

func dump(buf []byte, level, depth int) {
	if level > depth {
		fmt.Printf("%s... (profondeur max atteinte, %d octets)\n", strings.Repeat("  ", level), len(buf))
		return
	}
	fields := connectrpc.DecodeFields(buf)
	indent := strings.Repeat("  ", level)
	for _, f := range fields {
		if f.WireType == 0 {
			fmt.Printf("%s#%d varint=%d\n", indent, f.Num, f.Varint)
			continue
		}
		if f.WireType == 2 {
			if len(f.Bytes) == 0 {
				fmt.Printf("%s#%d bytes[0]\n", indent, f.Num)
				continue
			}
			if isLeaf(f.Bytes) {
				fmt.Printf("%s#%d str[%d] %q\n", indent, f.Num, len(f.Bytes), truncate(printable(f.Bytes), 80))
				continue
			}
			fmt.Printf("%s#%d msg[%d]\n", indent, f.Num, len(f.Bytes))
			dump(f.Bytes, level+1, depth)
			continue
		}
		fmt.Printf("%s#%d wire=%d len=%d\n", indent, f.Num, f.WireType, len(f.Bytes))
	}
}

// isLeaf : un blob est une feuille (chaîne) si le contenu est imprimable ou
// si l'entête ne ressemble pas à un message protobuf imbriqué.
func isLeaf(b []byte) bool {
	if len(b) == 0 {
		return true
	}
	// Heuristique chaîne : >85% imprimable
	printableRatio := 0.0
	n := 0
	for _, c := range b {
		if (c >= 0x20 && c < 0x7f) || c == '\n' || c == '\t' || c == '\r' {
			n++
		}
	}
	printableRatio = float64(n) / float64(len(b))
	if printableRatio > 0.85 {
		return true
	}

	// Sinon : doit ressembler à un message (clé protobuf valide)
	key := b[0]
	fieldNum := int(key >> 3)
	wireType := int(key & 7)
	if fieldNum < 1 || fieldNum > 29 || (wireType != 0 && wireType != 2) {
		return true // pas une clé valide → feuille binaire
	}
	// wireType 2 : longueur doit tenir dans le buffer
	if wireType == 2 {
		if len(b) < 2 {
			return true
		}
		if b[1]&0x80 != 0 {
			return true
		}
		l := int(b[1])
		if 2+l > len(b) {
			return true
		}
	}
	return false
}

func printable(b []byte) string {
	var sb strings.Builder
	for _, c := range b {
		if c >= 0x20 && c < 0x7f {
			sb.WriteByte(c)
		} else if c == '\n' || c == '\t' || c == '\r' {
			sb.WriteByte(' ')
		} else {
			sb.WriteByte('·')
		}
	}
	return sb.String()
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}
