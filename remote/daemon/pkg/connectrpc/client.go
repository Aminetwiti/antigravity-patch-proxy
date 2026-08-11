package connectrpc

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

type Client struct {
	Port      int
	CSRFToken string
	Host      string
	HTTP      *http.Client
}

func NewClient(port int, csrfToken string) *Client {
	return &Client{
		Port:      port,
		CSRFToken: csrfToken,
		Host:      "127.0.0.1",
		HTTP:      &http.Client{Timeout: 60 * time.Second},
	}
}

func (c *Client) Post(path string, body map[string]interface{}) ([]byte, error) {
	jsonPayload, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}

	url := fmt.Sprintf("http://%s:%d%s", c.Host, c.Port, path)
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonPayload))
	if err != nil {
		return nil, err
	}

	req.Header.Set("Content-Type", "application/connect+json")
	req.Header.Set("X-CSRF-Token", c.CSRFToken)
	req.Header.Set("Connect-Protocol-Version", "1")

	resp, err := c.HTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	return io.ReadAll(resp.Body)
}

func (c *Client) CreateCascade(workspacePath string) (map[string]interface{}, error) {
	respBytes, err := c.Post("/antigravity.v1.CascadeService/CreateCascade", map[string]interface{}{
		"workspacePath": workspacePath,
	})
	if err != nil {
		return nil, err
	}
	var res map[string]interface{}
	err = json.Unmarshal(respBytes, &res)
	return res, err
}

func (c *Client) GetAllCascades() (map[string]interface{}, error) {
	respBytes, err := c.Post("/antigravity.v1.CascadeService/GetAllCascades", map[string]interface{}{})
	if err != nil {
		return nil, err
	}
	var res map[string]interface{}
	err = json.Unmarshal(respBytes, &res)
	return res, err
}

func (c *Client) SubmitToolApproval(cascadeID, callID, decision string) (map[string]interface{}, error) {
	respBytes, err := c.Post("/antigravity.v1.CascadeService/SubmitToolApproval", map[string]interface{}{
		"cascadeId": cascadeID,
		"callId":    callID,
		"decision":  decision,
	})
	if err != nil {
		return nil, err
	}
	var res map[string]interface{}
	err = json.Unmarshal(respBytes, &res)
	return res, err
}
