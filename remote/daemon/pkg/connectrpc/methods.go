package connectrpc

import (
	"time"
)

// CreateCascade crée une session via StartCascade. Le modèle demandé est
// transmis par le mobile : ModelUID (requested_model_uid) si fourni, sinon
// l'enum historique (requested_model_id).
func (c *Client) CreateCascade(workspaceURI, projectID, modelUID string, modelEnum uint64) ([]byte, error) {
	return c.Call("StartCascade", BuildStartCascade(workspaceURI, projectID, modelUID, modelEnum))
}

// GetAllCascades liste toutes les sessions via GetAllCascadeTrajectories.
func (c *Client) GetAllCascades() ([]byte, error) {
	return c.Call("GetAllCascadeTrajectories", nil)
}

// SendMessage envoie un prompt et retourne la première frame de réponse.
func (c *Client) SendMessage(cascadeID, text string) ([]byte, error) {
	return c.Call("SendUserCascadeMessage", BuildSendMessage(cascadeID, text, c.APIKey, c.SessionID, c.ModelUID, c.ModelEnum))
}

// SendMessageStream envoie un prompt et transmet chaque frame de réponse reçue au callback onFrame.
func (c *Client) SendMessageStream(cascadeID, text string, onFrame func([]byte) error) error {
	return c.CallStream("SendUserCascadeMessage", BuildSendMessage(cascadeID, text, c.APIKey, c.SessionID, c.ModelUID, c.ModelEnum), 120*time.Second, onFrame)
}

// SubmitToolApproval approuve/refuse une interaction d'outil via le RPC officiel
// HandleCascadeUserInteraction (trajectory_id + step_index + oneof décision).
func (c *Client) SubmitToolApproval(cascadeID, trajectoryID string, stepIndex uint32, oneofField int, oneofPayload []byte) ([]byte, error) {
	return c.Call("HandleCascadeUserInteraction", BuildHandleCascadeUserInteraction(cascadeID, trajectoryID, stepIndex, oneofField, oneofPayload))
}

// Heartbeat vérifie que le serveur répond et que l'auth passe.
func (c *Client) Heartbeat() ([]byte, error) {
	return c.Call("Heartbeat", nil)
}

// SendCommand route une slash commande vers le Language Server comme si elle
// venait du terminal IDE (source=4), via HandleStreamingCommand.
func (c *Client) SendCommand(commandText string) ([]byte, error) {
	return c.Call("HandleStreamingCommand", BuildHandleStreamingCommand(commandText, CommandRequestSourceTerminal))
}

// SetBrowserOpenConversation force l'IDE Antigravity à s'abonner et ouvrir une session spécifique.
func (c *Client) SetBrowserOpenConversation(cascadeID string) ([]byte, error) {
	return c.Call("SetBrowserOpenConversation", BuildSetBrowserOpenConversation(cascadeID))
}
