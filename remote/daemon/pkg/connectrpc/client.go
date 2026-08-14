package connectrpc

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"io"
	"net/http"
	"sync"
	"time"
)

// Client parle le protocole gRPC-Web validé (voir remote/PROTOCOL.md) :
//
//	POST /exa.language_server_pb.LanguageServerService/<Method>
//	Content-Type: application/grpc-web+proto
//	x-codeium-csrf-token: <token>   (et non X-CSRF-Token)
//	Framing: 1 octet flags + 4 octets BE longueur + payload protobuf
type Client struct {
	mu        sync.RWMutex
	port      int
	csrfToken string
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
		port:      port,
		csrfToken: csrfToken,
		Host:      "127.0.0.1",
		HTTP:      &http.Client{Timeout: 60 * time.Second},
	}
}

// Endpoint retourne le port et le jeton CSRF de maniÃ¨re thread-safe.
func (c *Client) Endpoint() (int, string) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.port, c.csrfToken
}

// UpdateEndpoint met Ã  jour le port et le jeton CSRF suite Ã  un dÃ©marrage du hub.
func (c *Client) UpdateEndpoint(port int, csrfToken string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.port = port
	c.csrfToken = csrfToken
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
	port, csrfToken := c.Endpoint()
	url := fmt.Sprintf("http://%s:%d/exa.language_server_pb.LanguageServerService/%s", c.Host, port, method)
	body := Frame(payload)

	req, err := http.NewRequest("POST", url, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/grpc-web+proto")
	req.Header.Set("Accept", "application/grpc-web+proto,application/grpc-web-text")
	req.Header.Set("x-codeium-csrf-token", csrfToken)
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
	// Le Hub répond parfois « frame de données vide (0 octet) + frame trailer »
	// (ex: GetAllCascadeTrajectories d'une instance sans session) — on ne garde
	// que les frames de DONNÉES non vides (flags 0x00), sinon la première frame
	// retournée serait le trailer et le parseur protobuf recevrait du vide
	// (« aucune frame gRPC-Web »).
	var frames [][]byte
	offset := 0
	for offset+5 <= len(raw) {
		flags := raw[offset]
		length := int(binary.BigEndian.Uint32(raw[offset+1 : offset+5]))
		offset += 5
		if offset+length > len(raw) {
			break // trailer tronqué
		}
		if length > 0 && flags&0x80 == 0 { // frame de données non vide seulement
			frames = append(frames, raw[offset:offset+length])
		}
		offset += length
	}
	if len(frames) == 0 {
		// Réponse sans frame de données (ex: réponse vide DeleteCascade/Empty protobuf avec trailer seul).
		return []byte{}, nil
	}
	return frames[0], nil
}

// CallStream exécute une méthode RPC en streaming gRPC-Web et invoque onFrame pour chaque frame protobuf reçue.
func (c *Client) CallStream(method string, payload []byte, timeout time.Duration, onFrame func([]byte) error) error {
	port, csrfToken := c.Endpoint()
	url := fmt.Sprintf("http://%s:%d/exa.language_server_pb.LanguageServerService/%s", c.Host, port, method)
	body := Frame(payload)

	req, err := http.NewRequest("POST", url, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/grpc-web+proto")
	req.Header.Set("Accept", "application/grpc-web+proto,application/grpc-web-text")
	req.Header.Set("x-codeium-csrf-token", csrfToken)
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
