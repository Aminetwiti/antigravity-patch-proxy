# Protocole ConnectRPC/gRPC-Web & WebSocket Daemon Validé — Antigravity Remote

> Document de référence officiel de l'infrastructure. Basé sur l'analyse de `LanguageServerService` (`language_server.exe`), les tests réels dans `remote/scratch/` et l'implémentation du Daemon Go (`remote/daemon`).

---

## 1. Binaire et Architecture Moteur

Le "cerveau" d'Antigravity est **`language_server`** :

- `language_server_windows_x64.exe` — instances liées à un workspace IDE (`--subclient_type ide`)
- `language_server.exe` — instance standalone hub (`--subclient_type hub`, patchée par le proxy : `--api_server_url http://localhost:50999`)

---

## 2. Arguments Critiques du Processus

| Argument | Rôle | Exemple réel |
|:---|:---|:---|
| `--csrf_token` | Auth cloud (hub) / auth locale | `dca42d6a-3d87-4a6b-a620-dde9bc7ce40e` |
| `--extension_server_csrf_token` | Auth locale des instances IDE | `61edfa3c-af9d-457c-96af-bb466dcb4eab` |
| `--extension_server_port` | Port de BASE — le serveur écoute sur `base` et `base+1` | `55256` → actifs `55256`/`55257` |
| `--workspace_id` | Projet lié (instances IDE) | `file_c_3A_Users_amine_...` |
| `--subclient_type` | `ide` ou `hub` | `hub` (cible RPC) |

---

## 3. Découverte Automatique des Ports

1. Scanner les processus `language_server*` via WMI / PowerShell CIM.
2. **Cibler l'instance hub** (`--subclient_type hub`) — les instances IDE répondent **404** aux appels de service RPC de session.
3. Obtenir les ports TCP ouverts par le PID via `netstat -ano`.
4. **Validation par Probe Heartbeat** :
   ```http
   POST http://127.0.0.1:<port>/exa.language_server_pb.LanguageServerService/Heartbeat
   Content-Type: application/grpc-web+proto
   x-codeium-csrf-token: <csrf_token>
   ```
   → Le code HTTP `200` confirme le port actif du Hub.

---

## 4. Protocole HTTP gRPC-Web (Daemon ↔ LanguageServer)

### Endpoint
```
POST http://127.0.0.1:<port>/exa.language_server_pb.LanguageServerService/<Method>
```

### Méthodes Principales
| Méthode | Payload Protobuf | Rôle |
|:---|:---|:---|
| `StartCascade` | `StartCascadeRequest` | Crée une nouvelle session de conversation |
| `GetAllCascadeTrajectories` | Vide | Liste toutes les sessions et leurs états |
| `SendUserCascadeMessage` | `SendUserCascadeMessageRequest` | Envoie un prompt et ouvre le flux de réponse |
| `SubmitToolApproval` | `SubmitToolApprovalRequest` | Approuve ou rejette une action bloquante de l'agent |
| `Heartbeat` | Vide | Ping / maintien de vie de session |

### Headers Obligatoires
```http
Content-Type: application/grpc-web+proto
Accept: application/grpc-web+proto,application/grpc-web-text
x-codeium-csrf-token: <csrf_token>
Connect-Protocol-Version: 1
X-Grpc-Web: 1
```

### Framing gRPC-Web
Chaque trame binaire respecte le standard gRPC-Web : `1 octet flags (0x00 standard, 0x80 trailers) + 4 octets longueur Big-Endian + charge utile Protobuf`.

---

## 5. Schémas Protobuf Rétro-Ingéniérés

### `StartCascadeRequest`
- Field 4 : `source` (varint enum: 1 = `CORTEX_TRAJECTORY_SOURCE_CASCADE_CLIENT`)
- Field 5 : `trajectory_type` (varint enum: 1 = `CORTEX_TRAJECTORY_TYPE_USER_MAINLINE`)
- Field 8 : `workspace_uris` (repeated string: `file:///C:/path/workspace`)
- Field 14 : `requested_model` (varint enum: 190 = `CASCADE_BASE_MODEL_ID`)

### `SendUserCascadeMessageRequest`
- Field 1 : `cascade_id` (string UUID)
- Field 2 : `items` (repeated TextOrScopeItem)
  - Subfield 1 : `chunk.text` (string)

---

## 6. Protocole WebSocket JSON (Mobile Flutter ↔ Daemon Go)

Le Daemon Go expose un serveur WebSocket (`ws://<ip>:<port>/ws?token=<auth_token>`) traduisant les requêtes JSON en RPC Protobuf.

### A. Actions Client ➔ Daemon

#### 1. `send_prompt` (Envoi de message & support multimodal)
```json
{
  "type": "send_prompt",
  "requestId": "req_101",
  "cascadeId": "cas_abc123",
  "prompt": "Peux-tu analyser cette image et corriger le bug ?",
  "base64Data": "iVBORw0KGgoAAAANSUhEUgAA...",
  "fileName": "screen.png",
  "images": []
}
```
*Note : Le Daemon écrit automatiquement l'image dans `brain/<cascadeId>/scratch/` et concatène `![Uploaded Image](file:///...)` au prompt avant transmission gRPC-Web.*

#### 2. `upload_image` (Téléversement d'image autonome)
```json
{
  "type": "upload_image",
  "requestId": "req_102",
  "cascadeId": "cas_abc123",
  "base64Data": "iVBORw0KGgoAAAANSUhEUgAA...",
  "fileName": "architecture.png",
  "mimeType": "image/png"
}
```
**Réponse Daemon :**
```json
{
  "type": "response",
  "requestId": "req_102",
  "data": {
    "filePath": "C:/Users/.../brain/cas_abc123/scratch/upload_1723632000_1.png",
    "markdownRef": "![Uploaded Image](file:///C:/Users/.../brain/cas_abc123/scratch/upload_1723632000_1.png)"
  }
}
```

#### 3. `submit_question_response` (Réponse aux QCM interactifs `ask_question`)
```json
{
  "type": "submit_question_response",
  "requestId": "req_103",
  "cascadeId": "cas_abc123",
  "trajectoryId": "traj_xyz",
  "stepIndex": 5,
  "selectedAnswers": ["PostgreSQL", "Redis"],
  "customAnswer": "Optionnel: configuration personnalisée"
}
```

#### 4. `sync_session` (Rattrapage réseau sans perte `StepRecovery`)
```json
{
  "type": "sync_session",
  "requestId": "req_104",
  "cascadeId": "cas_abc123",
  "lastStepIndex": 42
}
```
**Réponse Daemon :**
```json
{
  "type": "response",
  "requestId": "req_104",
  "data": {
    "missedEvents": [
      { "type": "stream_delta", "data": { "text": "...", "stepIndex": 43 } },
      { "type": "stream_delta", "data": { "text": "...", "stepIndex": 44 } }
    ],
    "currentStepIndex": 44
  }
}
```

#### 5. `list_git_branches` & `list_git_worktrees` (Découverte Git)
```json
{
  "type": "list_git_branches",
  "requestId": "req_105",
  "workspacePath": "C:/projects/my-app"
}
```
```json
{
  "type": "list_git_worktrees",
  "requestId": "req_106",
  "workspacePath": "C:/projects/my-app"
}
```

#### 6. `tool_decision` (Validation d'action bloquante `run_command` / `file_permission`)
```json
{
  "type": "tool_decision",
  "requestId": "req_107",
  "cascadeId": "cas_abc123",
  "trajectoryId": "traj_xyz",
  "stepIndex": 3,
  "approvalType": "run_command",
  "decision": "approved",
  "scope": "once",
  "command": "npm run build"
}
```

---

## 7. Sécurité & Résilience Réseau

1. **Anti-DNS Rebinding** : `checkOrigin` n'autorise que `localhost`, `127.0.0.1`, les sous-réseaux privés locaux (`192.168.*`, `10.*`, `172.16.*`) et les tunnels approuvés (`trycloudflare.com`, `pinggy.link`, `ngrok.io`).
2. **Confinement Path Traversal** : `resolvePath` et `saveUploadedImage` valident strictement l'ancrage des chemins dans la racine du workspace ou du sous-dossier `scratch/`.
3. **Protection des Secrets** : Vérification des tokens d'authentification en temps constant via `crypto/subtle.ConstantTimeCompare`.
4. **Buffer Circulaire `StepRecovery`** : 100 trames conservées en mémoire vive par cascade pour un rattrapage immédiat post-reconnexion.

---

## 8. Source de Vérité Canonique : `antigravity-client`

Pour toute extension ou validation des champs Protobuf du service gRPC-Web `LanguageServerService`, se référer au sous-projet canonique :

- **Emplacement** : [`remote/tools/antigravity-client-main/antigravity-client-main`](file:///C:/Users/amine/Downloads/antigravity-add-model-main/antigravity-add-model-main/remote/tools/antigravity-client-main/antigravity-client-main)
- **Définitions RPC exhaustives (188 méthodes)** : [`src/gen/exa/language_server_pb/language_server_pb.ts`](file:///C:/Users/amine/Downloads/antigravity-add-model-main/antigravity-add-model-main/remote/tools/antigravity-client-main/antigravity-client-main/src/gen/exa/language_server_pb/language_server_pb.ts)
- **Schémas de Trajectoires & Planners** : `src/gen/exa/cortex_pb/` et `src/gen/exa/jetski_cortex_pb/`
- **Parseur d'Événements de Référence** : [`src/core/cascade/event-parser.ts`](file:///C:/Users/amine/Downloads/antigravity-add-model-main/antigravity-add-model-main/remote/tools/antigravity-client-main/antigravity-client-main/src/core/cascade/event-parser.ts)
- **Harnais de validation Node.js** : `src/test-*.ts` (ex: `test-10-tool-approval.ts`, `test-6-model.ts`, etc.)
