package connectrpc

import (
	"fmt"
	"time"
)

// CreateCascade crée une session via StartCascade.
func (c *Client) CreateCascade(workspaceURI string, requestedModel uint64) ([]byte, error) {
	return c.Call("StartCascade", BuildStartCascade(workspaceURI, requestedModel))
}

// GetAllCascades liste toutes les sessions via GetAllCascadeTrajectories.
func (c *Client) GetAllCascades() ([]byte, error) {
	return c.Call("GetAllCascadeTrajectories", nil)
}

// SendMessage envoie un prompt et retourne la première frame de réponse.
func (c *Client) SendMessage(cascadeID, text string) ([]byte, error) {
	return c.Call("SendUserCascadeMessage", BuildSendMessage(cascadeID, text))
}

// SendMessageStream envoie un prompt et transmet chaque frame de réponse reçue au callback onFrame.
func (c *Client) SendMessageStream(cascadeID, text string, onFrame func([]byte) error) error {
	return c.CallStream("SendUserCascadeMessage", BuildSendMessage(cascadeID, text), 120*time.Second, onFrame)
}

// SubmitToolApproval approuve/refuse un appel d'outil.
func (c *Client) SubmitToolApproval(cascadeID, callID string, decision uint64) ([]byte, error) {
	return c.Call("SubmitToolApproval", BuildSubmitToolApproval(cascadeID, callID, decision))
}

// Heartbeat vérifie que le serveur répond et que l'auth passe.
func (c *Client) Heartbeat() ([]byte, error) {
	return c.Call("Heartbeat", nil)
}

var _ = fmt.Sprintf // garde l'import fmt si les messages d'erreur évoluent

