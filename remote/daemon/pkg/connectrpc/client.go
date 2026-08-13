package connectrpc

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"io"
	"net/http"
	"time"
)

// Client parle le protocole gRPC-Web validé (voir remote/PROTOCOL.md) :
//   POST /exa.language_server_pb.LanguageServerService/<Method>
//   Content-Type: application/grpc-web+proto
//   x-codeium-csrf-token: <token>   (et non X-CSRF-Token)
//   Framing: 1 octet flags + 4 octets BE longueur + payload protobuf
type Client struct {
	Port      int
	CSRFToken string
	Host      string
	HTTP      *http.Client
	// APIKey est la clé d'API envoyée au Language Server (champ metadata 3).
	// Sans elle le LS répond « untrusted workspace ».
	APIKey string
	// SessionID stable sur la session — le LS associe l'état du panneau à
	// cette valeur (voir buildMetadata champ 10).
	SessionID string
	// ModelUID / ModelEnum : modèle demandé pour les messages cascade
	// (cascade_config requested_model_uid/id). Renseigné au démarrage.
	ModelUID  string
	ModelEnum uint64
}

func NewClient(port int, csrfToken string) *Client {
	return &Client{
		Port:      port,
		CSRFToken: csrfToken,
		Host:      "127.0.0.1",
		HTTP:      &http.Client{Timeout: 60 * time.Second},
	}
}

// Frame encadre un message protobuf pour gRPC-Web.
func Frame(payload []byte) []byte {
	buf := make([]byte, 5+len(payload))
	buf[0] = 0 // flags: pas de compression
	binary.BigEndian.PutUint32(buf[1:5], uint32(len(payload)))
	copy(buf[5:], payload)
	return buf
}

// Call exécute une méthode RPC et retourne les messages protobuf bruts.
func (c *Client) Call(method string, payload []byte) ([]byte, error) {
	url := fmt.Sprintf("http://%s:%d/exa.language_server_pb.LanguageServerService/%s", c.Host, c.Port, method)
	body := Frame(payload)

	req, err := http.NewRequest("POST", url, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/grpc-web+proto")
	req.Header.Set("Accept", "application/grpc-web+proto,application/grpc-web-text")
	req.Header.Set("x-codeium-csrf-token", c.CSRFToken)
	req.Header.Set("Connect-Protocol-Version", "1")
	req.Header.Set("X-Grpc-Web", "1")

	resp, err := c.HTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != http.StatusOK {
		return raw, fmt.Errorf("HTTP %d: %s", resp.StatusCode, truncate(string(raw), 200))
	}

	// Découper les frames gRPC-Web : flags(1) + longueur BE(4) + message
	var frames [][]byte
	offset := 0
	for offset+5 <= len(raw) {
		length := int(binary.BigEndian.Uint32(raw[offset+1 : offset+5]))
		offset += 5
		if offset+length > len(raw) {
			break // trailer tronqué
		}
		frames = append(frames, raw[offset:offset+length])
		offset += length
	}
	if len(frames) == 0 {
		return nil, fmt.Errorf("aucune frame gRPC-Web dans la réponse (%d octets)", len(raw))
	}
	return frames[0], nil
}

// CallStream exécute une méthode RPC en streaming gRPC-Web et invoque onFrame pour chaque frame protobuf reçue.
func (c *Client) CallStream(method string, payload []byte, timeout time.Duration, onFrame func([]byte) error) error {
	url := fmt.Sprintf("http://%s:%d/exa.language_server_pb.LanguageServerService/%s", c.Host, c.Port, method)
	body := Frame(payload)

	req, err := http.NewRequest("POST", url, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/grpc-web+proto")
	req.Header.Set("Accept", "application/grpc-web+proto,application/grpc-web-text")
	req.Header.Set("x-codeium-csrf-token", c.CSRFToken)
	req.Header.Set("Connect-Protocol-Version", "1")
	req.Header.Set("X-Grpc-Web", "1")

	client := &http.Client{Timeout: timeout}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		raw, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("HTTP %d: %s", resp.StatusCode, truncate(string(raw), 200))
	}

	buf := make([]byte, 32768)
	var accumulated []byte

	for {
		n, readErr := resp.Body.Read(buf)
		if n > 0 {
			accumulated = append(accumulated, buf[:n]...)
			frames, rest := splitFrames(accumulated)
			accumulated = rest
			for _, frameData := range frames {
				if err := onFrame(frameData); err != nil {
					return err
				}
			}
		}
		if readErr != nil {
			if readErr == io.EOF {
				break
			}
			return readErr
		}
	}
	return nil
}

// splitFrames extrait les frames gRPC-Web complètes d'un buffer.
// Retourne les frames de données (les trailers flag 0x80 sont ignorés) et
// le reste fragmentaire non consommé (frame partielle en attente de données).
func splitFrames(buf []byte) ([][]byte, []byte) {
	var frames [][]byte
	for len(buf) >= 5 {
		flags := buf[0]
		length := int(binary.BigEndian.Uint32(buf[1:5]))
		if len(buf) < 5+length {
			break
		}
		if flags&0x80 == 0 {
			frames = append(frames, buf[5:5+length])
		}
		buf = buf[5+length:]
	}
	return frames, buf
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}

