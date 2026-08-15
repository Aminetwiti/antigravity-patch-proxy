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

// Sources CommandRequestSource (énum exa.codeium_common_pb, décodée du binaire) :
const (
	CommandRequestSourceDefault       = 1
	CommandRequestSourcePlan          = 2
	CommandRequestSourceFastApply     = 3
	CommandRequestSourceTerminal      = 4 // injection slash command depuis le mobile
	CommandRequestSourceSupercomplete = 5
	CommandRequestSourceTabJump       = 6
	CommandRequestSourceCascadeChat   = 7
)

// StartCascadeRequest : field 4 source=1, 5 trajectory_type=1,
// 8 workspace_uris (string), 14 requested_model (varint),
// 15 requested_model_uid (string).
// BuildStartCascade génère un message StartCascadeRequest brut. Le modèle
// demandé est transmis par le mobile : requested_model_uid (15) si fourni,
// sinon repli sur requested_model (14, enum historique).
func BuildStartCascade(workspaceURI, projectID, modelUID string, modelEnum uint64) []byte {
	w := &writer{}
	w.varintField(4, 1)
	w.varintField(5, 1)
	if projectID != "" {
		envW := &writer{}
		envW.stringField(1, projectID)
		envW.bytesField(4, []byte{}) // defaultProjectEnvironment
		w.bytesField(17, envW.b)
	} else {
		w.stringField(8, workspaceURI)
	}
	if modelUID != "" {
		w.stringField(15, modelUID)
	} else if modelEnum != 0 {
		w.varintField(14, modelEnum)
	}
	return w.b
}

// SendUserCascadeMessageRequest : field 1 cascade_id, field 2 items[]
// où chaque item est TextOrScopeItem{ 1: chunk.text }.
//
// Le LS 2.5.0 refuse tout message sans cascade_config (field 5) contenant
// requested_model_id (14) ou requested_model_uid (15) : l'exécuteur plante
// avec « neither PlanModel nor RequestedModel specified ». Même schéma que
// buildSendCascadeMessageRequest de windsurf_main.js (éprouvé en prod).
// Le modelUID est fourni par le client mobile ; s'il est vide on retombe
// sur l'enum historique (requested_model_id).
// BuildSendMessage construit un SendMessageRequest. noTools force
// planner_mode = 3 (NO_TOOL) dans le cascade_config.
func BuildSendMessage(cascadeID, text, apiKey, sessionID, modelUID string, modelEnum uint64, noTools ...bool) []byte {
	item := &writer{}
	item.stringField(1, text)

	w := &writer{}
	w.stringField(1, cascadeID)
	w.bytesField(2, item.b)
	if apiKey != "" {
		w.bytesField(3, buildMetadata(apiKey, sessionID))
	}
	w.bytesField(5, BuildCascadeConfig(modelUID, modelEnum, noTools...))
	return w.b
}

// DefaultModelEnum : repli quand aucun modèle n'est demandé — enum LS
// GOOGLE_GEMINI_3_7_FLASH (défaut Antigravity 2.0 / haute capacité).
// CONSTANTE UNIQUE partagée entre BuildCascadeConfig (plan_model) et le repli
// create_cascade du gateway : deux littéraux 312/190 auraient divergé.
const DefaultModelEnum uint64 = 312

// BuildCascadeConfig construit le sous-message cascade_config.
//
// Format validé contre le vrai Language Server 2.8.0 (probe gRPC-Web le
// 2026-08-14) : l'ancien layout « planner {5: requested_model_id,
// 6: requested_model_uid} » est rejeté par le LS avec
// « neither PlanModel nor RequestedModel specified » (grpc-status 2).
// Le layout accepté (grpc-status 0) est :
//
//	CascadeConfig {
//	  1: planner_config (CascadePlannerConfig) {
//	    1: plan_model (enum, ex: 246 = GOOGLE_GEMINI_2_5_PRO)
//	    2: conversational_config {1: planner_mode}
//	    15: requested_model (ModelOrAlias {1: model})
//	  }
//	}
//
// planner_mode 3 = NO_TOOL (pas de boucle d'outils — le mobile ne voit
// que le texte). requested_model (15) est la clé qui débloque le LS.
func BuildCascadeConfig(modelUID string, modelEnum uint64, noTools ...bool) []byte {
	planner := &writer{}

	// plan_model (field 1) : même valeur que requested_model ci-dessous.
	// Le LS l'exige explicitement (« neither PlanModel nor RequestedModel »).
	if modelEnum == 0 {
		modelEnum = DefaultModelEnum
	}
	planner.varintField(1, modelEnum)

	// conversational_config (field 2) {1: planner_mode} :
	// 3 = NO_TOOL (pas de boucle d'outils — le mobile ne voit que le texte),
	// sinon 1 = AUTO (boucle d'outils par défaut du LS).
	mode := uint64(1) // AUTO
	if len(noTools) > 0 && noTools[0] {
		mode = 3 // NO_TOOL
	}
	conv := &writer{}
	conv.varintField(1, mode)
	planner.bytesField(2, conv.b)

	// requested_model (field 15) = ModelOrAlias {1: model}.
	reqModel := &writer{}
	if modelUID != "" {
		// ModelOrAlias.alias = CASCADE_BASE (1) : hérite du modèle de la cascade.
		reqModel.varintField(2, 1)
	} else if modelEnum != 0 {
		reqModel.varintField(1, modelEnum)
	}
	planner.bytesField(15, reqModel.b)

	w := &writer{}
	w.bytesField(1, planner.b)
	return w.b
}

// HandleStreamingCommandRequest (champs validés par décodage du DescriptorProto
// réel dans language_server.exe, offset 47540541) :
//
//	1 metadata (Metadata)   2 document (Document)   3 editor_options
//	4 requested_model_id    5 experiment_config    6 selection_start_line
//	7 selection_end_line    8 command_text          9 request_source
//	10 mentioned_scope      11 action_pointer      12 parent_completion_id
//	13 diff_type            14 diagnostics         15 supercomplete_trigger_condition
//	16 terminal_command_data 17 ignore_supercomplete_debounce
//	18 clipboard_entry      19 intellisense_suggestions
//
// BuildHandleStreamingCommand construit une demande de commande minimale
// (source = Terminal, comme si la commande venait du terminal IDE) pour
// router une slash commande vers le Language Server sans passer par le chat.
func BuildHandleStreamingCommand(commandText string, source uint64) []byte {
	w := &writer{}
	w.stringField(8, commandText)
	w.varintField(9, source)
	return w.b
}

// Champs oneof de CascadeUserInteraction (vérifiés dans cortex_pb.ts).
const (
	InteractionRunCommand     = 5  // CascadeRunCommandInteraction
	InteractionOpenBrowserURL = 6  // CascadeOpenBrowserUrlInteraction
	InteractionFilePermission = 19 // FilePermissionInteraction
	InteractionPermission     = 21 // PermissionInteraction
	InteractionApproval       = 23 // ApprovalInteraction
)

// BuildRunCommandInteraction : {1: confirm, 2: proposed, 3: submitted}.
func BuildRunCommandInteraction(confirm bool, proposed, submitted string) []byte {
	w := &writer{}
	w.varintField(1, boolToUint64(confirm))
	w.stringField(2, proposed)
	if submitted != "" {
		w.stringField(3, submitted)
	}
	return w.b
}

// BuildPermissionInteraction : {1: allow, 2: scope} (le scope 2 = CONVERSATION).
func BuildPermissionInteraction(allow bool, scope uint64) []byte {
	w := &writer{}
	w.varintField(1, boolToUint64(allow))
	w.varintField(2, scope)
	return w.b
}

// BuildFilePermissionInteraction : {1: allow, 2: scope, 3: absolute_path_uri}.
func BuildFilePermissionInteraction(allow bool, scope uint64, pathURI string) []byte {
	w := &writer{}
	w.varintField(1, boolToUint64(allow))
	w.varintField(2, scope)
	w.stringField(3, pathURI)
	return w.b
}

// BuildApprovalInteraction : {1: confirm} — fallback générique.
func BuildApprovalInteraction(confirm bool) []byte {
	w := &writer{}
	w.varintField(1, boolToUint64(confirm))
	return w.b
}

// BuildHandleCascadeUserInteraction construit le payload de
// HandleCascadeUserInteractionRequest : {1: cascade_id, 2: interaction}
// où interaction = {1: trajectory_id, 2: step_index, <oneofField>: oneofPayload}.
func BuildHandleCascadeUserInteraction(cascadeID, trajectoryID string, stepIndex uint32, oneofField int, oneofPayload []byte) []byte {
	interaction := &writer{}
	interaction.stringField(1, trajectoryID)
	interaction.varintField(2, uint64(stepIndex))
	interaction.bytesField(oneofField, oneofPayload)

	w := &writer{}
	w.stringField(1, cascadeID)
	w.bytesField(2, interaction.b)
	return w.b
}

func boolToUint64(b bool) uint64 {
	if b {
		return 1
	}
	return 0
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

// BuildSetBrowserOpenConversation construit un message SetBrowserOpenConversationRequest
// pour forcer l'IDE Antigravity à ouvrir et afficher une cascade spécifique.
func BuildSetBrowserOpenConversation(cascadeID string) []byte {
	w := &writer{}
	w.stringField(1, cascadeID)
	return w.b
}

// BuildDeleteCascadeTrajectory construit un DeleteCascadeTrajectoryRequest :
// {1: cascade_id} — schéma vérifié dans antigravity-client
// (src/gen/exa/language_server_pb/language_server_pb.ts, ligne 11572).
func BuildDeleteCascadeTrajectory(cascadeID string) []byte {
	w := &writer{}
	w.stringField(1, cascadeID)
	return w.b
}

// BuildReadFileRequest construit un ReadFileRequest : {1: uri} — schéma
// vérifié dans antigravity-client (ligne 15483).
func BuildReadFileRequest(uri string) []byte {
	w := &writer{}
	w.stringField(1, uri)
	return w.b
}

// BuildWriteFileRequest construit un WriteFileRequest :
// {1: uri, 2: content (bytes), 3: overwrite (bool)} — schéma vérifié dans
// antigravity-client (ligne 15631).
func BuildWriteFileRequest(uri string, content []byte, overwrite bool) []byte {
	w := &writer{}
	w.stringField(1, uri)
	w.bytesField(2, content)
	if overwrite {
		w.varintField(3, 1)
	}
	return w.b
}

// BuildStatUriRequest construit un StatUriRequest : {1: uri} — schéma vérifié
// dans antigravity-client (ligne 15397).
func BuildStatUriRequest(uri string) []byte {
	w := &writer{}
	w.stringField(1, uri)
	return w.b
}

// Verbosités ClientTrajectoryVerbosity (enum exa.language_server_pb,
// language_server_pb.ts ligne 257) — 0 = UNSPECIFIED, 1 = DEBUG,
// 2 = PROD_UI, 3 = FULL. 3 est demandé par défaut (vue structurée complète).
const (
	TrajectoryVerbosityUnspecified = 0
	TrajectoryVerbosityDebug       = 1
	TrajectoryVerbosityProdUI      = 2
	TrajectoryVerbosityFull        = 3
)

// BuildGetCascadeTrajectory construit un GetCascadeTrajectoryRequest :
// {1: cascade_id, 2: verbosity, 3: trajectory_verbosity} — schéma vérifié
// dans antigravity-client (language_server_pb.ts ligne 8711).
// verbosity=0 (UNSPECIFIED) → champ omis (le LS applique son défaut).
func BuildGetCascadeTrajectory(cascadeID string, verbosity uint64) []byte {
	w := &writer{}
	w.stringField(1, cascadeID)
	if verbosity != 0 {
		w.varintField(2, verbosity)
		w.varintField(3, verbosity)
	}
	return w.b
}

// BuildGetTurnDiff construit un GetTurnDiffRequest :
// {1: conversation_id, 2: step_index} — schéma vérifié dans
// antigravity-client (language_server_pb.ts ligne 7779).
// step_index < 0 → champ omis (le LS résout le dernier tour).
func BuildGetTurnDiff(conversationID string, stepIndex int64) []byte {
	w := &writer{}
	w.stringField(1, conversationID)
	if stepIndex >= 0 {
		w.varintField(2, uint64(stepIndex))
	}
	return w.b
}

// BuildGetRevertPreview construit un GetRevertPreviewRequest :
// {1: cascade_id, 2: step_index, 3: metadata, 4: override_config}
func BuildGetRevertPreview(cascadeID string, stepIndex int64, apiKey, sessionID string, modelUID string, modelEnum uint64) []byte {
	w := &writer{}
	w.stringField(1, cascadeID)
	if stepIndex >= 0 {
		w.varintField(2, uint64(stepIndex))
	}
	if apiKey != "" {
		w.bytesField(3, buildMetadata(apiKey, sessionID))
	}
	if modelUID != "" || modelEnum != 0 {
		w.bytesField(4, BuildCascadeConfig(modelUID, modelEnum))
	}
	return w.b
}

// BuildRevertToCascadeStep construit un RevertToCascadeStepRequest :
// {1: metadata, 2: cascade_id, 3: step_index, 5: override_config}
func BuildRevertToCascadeStep(cascadeID string, stepIndex int64, apiKey, sessionID string, modelUID string, modelEnum uint64) []byte {
	w := &writer{}
	if apiKey != "" {
		w.bytesField(1, buildMetadata(apiKey, sessionID))
	}
	w.stringField(2, cascadeID)
	if stepIndex >= 0 {
		w.varintField(3, uint64(stepIndex))
	}
	if modelUID != "" || modelEnum != 0 {
		w.bytesField(5, BuildCascadeConfig(modelUID, modelEnum))
	}
	return w.b
}

// BuildSendStepsToBackground construit un SendStepsToBackgroundRequest :
// {1: conversation_id, 2: repeated step_indices}
func BuildSendStepsToBackground(conversationID string, stepIndices []int64) []byte {
	w := &writer{}
	w.stringField(1, conversationID)
	for _, idx := range stepIndices {
		if idx >= 0 {
			w.varintField(2, uint64(idx))
		}
	}
	return w.b
}

// BuildSkipBrowserSubagent construit un SkipBrowserSubagentRequest :
// {1: cascade_id, 2: step_index}
func BuildSkipBrowserSubagent(cascadeID string, stepIndex int64) []byte {
	w := &writer{}
	w.stringField(1, cascadeID)
	if stepIndex >= 0 {
		w.varintField(2, uint64(stepIndex))
	}
	return w.b
}

// BuildRetrieveUserQuotaSummary construit un RetrieveUserQuotaSummaryRequest :
// {1: metadata}
func BuildRetrieveUserQuotaSummary(apiKey, sessionID string) []byte {
	w := &writer{}
	if apiKey != "" {
		w.bytesField(1, buildMetadata(apiKey, sessionID))
	}
	return w.b
}

