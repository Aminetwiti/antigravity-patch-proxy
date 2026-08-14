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

// SendMessageStreamModel comme SendMessageStream mais avec un modèle
// explicite (venant du message send_prompt du mobile) : le daemon doit
// respecter la sélection du téléphone, pas le repli global du client.
func (c *Client) SendMessageStreamModel(cascadeID, text, modelUID string, modelEnum uint64, onFrame func([]byte) error) error {
	return c.CallStream("SendUserCascadeMessage", BuildSendMessage(cascadeID, text, c.APIKey, c.SessionID, modelUID, modelEnum), 120*time.Second, onFrame)
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

// ListModels récupère la liste des modèles disponibles via GetAvailableModels
// (réponse imbriquée FetchAvailableModelsResponse — décodée best-effort par
// ParseModels, jamais fatale en cas de schéma inconnu).
func (c *Client) ListModels() ([]byte, error) {
	return c.Call("GetAvailableModels", nil)
}

// DeleteCascade supprime une session via DeleteCascadeTrajectory
// (irréversible — l'appelant DOIT avoir confirmé côté client).
func (c *Client) DeleteCascade(cascadeID string) ([]byte, error) {
	return c.Call("DeleteCascadeTrajectory", BuildDeleteCascadeTrajectory(cascadeID))
}

// ReadFile lit un fichier via le RPC officiel ReadFile du Language Server
// (URI file:/// — gère l'encodage et le workspace tracking du LS).
func (c *Client) ReadFile(uri string) ([]byte, error) {
	return c.Call("ReadFile", BuildReadFileRequest(uri))
}

// WriteFile écrit un fichier via le RPC officiel WriteFile du Language Server.
// overwrite=false → erreur si le fichier existe déjà (pas d'écrasement silencieux).
func (c *Client) WriteFile(uri string, content []byte, overwrite bool) ([]byte, error) {
	return c.Call("WriteFile", BuildWriteFileRequest(uri, content, overwrite))
}

// GetCascadeTrajectory récupère l'historique structuré d'une session
// (GetCascadeTrajectory). verbosity=0 → défaut du LS.
func (c *Client) GetCascadeTrajectory(cascadeID string, verbosity uint64) ([]byte, error) {
	return c.Call("GetCascadeTrajectory", BuildGetCascadeTrajectory(cascadeID, verbosity))
}

// GetTurnDiff récupère le diff officiel d'un tour (GetTurnDiff).
// stepIndex < 0 → le LS résout le dernier tour.
func (c *Client) GetTurnDiff(conversationID string, stepIndex int64) ([]byte, error) {
	return c.Call("GetTurnDiff", BuildGetTurnDiff(conversationID, stepIndex))
}
