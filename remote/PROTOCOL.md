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

#### 7. `list_models` (Catalogue des modèles disponibles)
Récupère la liste structurée des modèles via `GetAvailableModels` (réponse imbriquée `FetchAvailableModelsResponse` décodée côté Go — jamais un dump binaire).

```json
{
  "type": "list_models",
  "requestId": "req_108"
}
```

**Réponse Daemon :**
```json
{
  "type": "response",
  "requestId": "req_108",
  "data": {
    "models": [
      {
        "modelId": "claude-3-7-sonnet",
        "displayName": "Claude 3.7 Sonnet",
        "recommended": true,
        "disabled": false,
        "beta": false,
        "preview": false,
        "supportsThinking": true,
        "supportsImages": true,
        "thinkingBudget": 20000,
        "maxOutputTokens": 128000,
        "description": "..."
      }
    ]
  }
}
```
*Note : décodage best-effort (`ParseModels`) — un schéma inconnu renvoie `models: []` + `warning` au lieu d'une erreur fatale.*

#### 8. `delete_cascade` (Suppression définitive d'une session)
Action **destructive et irréversible** — le champ `confirm: true` est obligatoire (le mobile DOIT afficher un dialog natif avant).

```json
{
  "type": "delete_cascade",
  "requestId": "req_109",
  "cascadeId": "cas_abc123",
  "confirm": true
}
```
**Réponse Daemon :** `{"type":"response","requestId":"req_109","data":{...}}`
*Après succès RPC, le daemon purge l'état local : buffer StepRecovery, approbations en attente, auto-approbations de session, marqueurs de stream actif — aucun fantôme sur `get_pending_approval`.*
*Sans `confirm: true` → erreur `"confirmation requise (champ confirm=true)"`.*

#### 9. `read_file` (Lecture de fichier via RPC officiel du LS)
Utilise le RPC `ReadFile` du Language Server (gestion workspace/encodage native) — chemin Windows ou URI `file:///` acceptés.

```json
{
  "type": "read_file",
  "requestId": "req_110",
  "filePath": "C:\\Users\\amine\\proj\\main.go"
}
```

#### 10. `write_file` (Écriture de fichier via RPC officiel du LS)
Le contenu est transmis en **base64** (JSON ne transporte pas de binaire proprement). `overwrite: false` → erreur si le fichier existe (pas d'écrasement silencieux).

```json
{
  "type": "write_file",
  "requestId": "req_111",
  "filePath": "C:\\Users\\amine\\proj\\main.go",
  "content": "cGFja2FnZSBtYWluCg==",
  "overwrite": true
}
```
*Note : le chemin est normalisé en URI `file:///` avant transmission au LS ; base64 invalide → erreur sans appel RPC.*

#### 11. `get_user_status` / `user.get_status` (Profil, Plan et Crédits)
Récupère les informations du compte utilisateur, plan actif et solde de crédits.

```json
{
  "type": "get_user_status",
  "requestId": "req_112"
}
```

#### 12. `get_model_statuses` / `models.get_statuses` (Statuts et Dégradations Modèles)
Récupère la disponibilité en temps réel de tous les modèles (Claude, Gemini, GPT-OSS).

```json
{
  "type": "get_model_statuses",
  "requestId": "req_113"
}
```

#### 13. `generate_commit_message` / `workspace.generate_commit_message` (Générateur de Commit IA)
Génère un message de commit conventionnel basé sur les fichiers actuellement dans le staging Git (`git add`).

```json
{
  "type": "generate_commit_message",
  "requestId": "req_114"
}
```
*En cas d'absence de fichiers indexés, le daemon intercepte l'erreur interne 500 et renvoie une explication claire.*

#### 14. `export_markdown` / `trajectory.export_markdown` (Export de Session Markdown)
Résout le `trajectoryId` et convertit l'intégralité d'une conversation en document Markdown.

```json
{
  "type": "export_markdown",
  "requestId": "req_115",
  "cascadeId": "cas_abc123"
}
```

#### 15. `create_worktree` / `workspace.create_worktree` (Isolation Git Worktree)
Crée un nouveau worktree Git pour exécuter une tâche agentique en parallèle.

```json
{
  "type": "create_worktree",
  "requestId": "req_116",
  "branch": "feature/parallel-task"
}
```

#### 16. `git_state` / `vcs.get_state` (État VCS du workspace)
Délègue au RPC officiel `GetVersionControlState` du Language Server : branche courante, commit actif, historique, changements working directory / staged et conflits de merge. Le daemon décode le protobuf en JSON stable (`vcsType`, `currentRef`, `commits[]`, `workingDirectoryChanges[]`, `stagedChanges[]`, `inConflict`, `conflicts[]`).

```json
{
  "type": "git_state",
  "requestId": "req_117",
  "workspacePath": "C:/Users/amine/projects/myapp"
}
```

**Réponse :**
```json
{
  "type": "response",
  "requestId": "req_117",
  "data": {
    "vcsType": "GIT",
    "currentRef": "main",
    "activeCommitId": "a1b2c3d",
    "commits": [{ "id": "a1b2c3d", "author": "User", "timestampMs": 1700000000000, "subject": "feat: x" }],
    "workingDirectoryChanges": [{ "uri": "file:///C:/.../main.go", "operation": "MODIFIED" }],
    "stagedChanges": [],
    "inConflict": false
  }
}
```

#### 17. `git_stage` / `git_unstage` (Indexation / désindexation)
`data.uris` (liste d'URIs `file:///`) vers `GitStage` / `GitUnstage`.

```json
{
  "type": "git_stage",
  "requestId": "req_118",
  "workspacePath": "C:/Users/amine/projects/myapp",
  "data": { "uris": ["file:///C:/Users/amine/projects/myapp/main.go"] }
}
```

#### 18. `git_commit` (Commit)
`data.message` (ou `command`) vers `GitCommit`.

```json
{
  "type": "git_commit",
  "requestId": "req_119",
  "workspacePath": "C:/Users/amine/projects/myapp",
  "data": { "message": "feat: mobile commit" }
}
```

#### 19. `git_discard` (Annulation destructive — **confirmation requise**)
Annule les modifications non indexées. Exige `confirm: true` (même garde que `delete_cascade`).

```json
{
  "type": "git_discard",
  "requestId": "req_120",
  "workspacePath": "C:/Users/amine/projects/myapp",
  "confirm": true,
  "data": { "uris": ["file:///C:/Users/amine/projects/myapp/main.go"] }
}
```

#### 20. `git_commit_details` / `vcs.get_commit_details` (Détails d'un commit)
`commitId` vers `GetCommitDetails` (fichiers changés + parents).

```json
{
  "type": "git_commit_details",
  "requestId": "req_121",
  "workspacePath": "C:/Users/amine/projects/myapp",
  "commitId": "a1b2c3d"
}
```

#### 21. `list_sidecar_log_files` / `sidecar.list_log_files` (Logs Sidecar)
Liste les fichiers de log d'un sidecar (`sidecarId`) via `ListSidecarLogFiles`.

```json
{
  "type": "list_sidecar_log_files",
  "requestId": "req_122",
  "sidecarId": "sc-web-01"
}
```

#### 22. `get_sidecar_logs` / `sidecar.get_logs` (Contenu d'un log Sidecar)
`sidecarId` + `logFileName` vers `GetSidecarLogs`.

```json
{
  "type": "get_sidecar_logs",
  "requestId": "req_123",
  "sidecarId": "sc-web-01",
  "logFileName": "server.log"
}
```

#### 23. `manage_sidecar` / `sidecar.manage` (Contrôle Sidecar)
`data.action` (1=start, 2=stop, 3=restart, 4=remove) vers `ManageSidecar`. **Défaut : 2 (stop)** — le démarrage/removal reste un choix explicite du client.

```json
{
  "type": "manage_sidecar",
  "requestId": "req_124",
  "sidecarId": "sc-web-01",
  "data": { "action": 3 }
}
```

#### 24. `start_battle_mode` / `colosseum.start` (Duel Multi-Modèles)
Démarre une session Colosseum en instanciant deux worktrees Git isolés et deux modèles concurrents :
```json
{
  "type": "start_battle_mode",
  "requestId": "req_125",
  "workspaceUri": "file:///workspace",
  "prompt": "Implémenter le tri fusion",
  "modelUIDA": "claude-3-7-sonnet",
  "modelEnumA": 312,
  "modelUIDB": "gemini-2-5-pro",
  "modelEnumB": 246
}
```

#### 25. `get_battle_diff` / `colosseum.get_diff` (Diff Comparatif Live)
Récupère le diff unifié comparant en temps réel les deux branches du mode Battle :
```json
{
  "type": "get_battle_diff",
  "requestId": "req_126",
  "workspaceUri": "file:///workspace"
}
```

#### 26. `eliminate_battle_arm` / `colosseum.eliminate_arm` (Élimination d'Arm)
Supprime l'un des deux worktrees perdants :
```json
{
  "type": "eliminate_battle_arm",
  "requestId": "req_127",
  "armId": "arm_b"
}
```

#### 27. `end_battle_mode` / `colosseum.end` (Arbitrage & SafeMerge)
Applique la solution victorieuse dans la branche principale avec la stratégie SafeMerge choisie :
```json
{
  "type": "end_battle_mode",
  "requestId": "req_128",
  "winningArmId": "arm_a",
  "mergeStrategy": 2
}
```

#### 28. `dump_flight_recorder` / `diagnostics.dump_flight_recorder` (Trace Profiling)
Extrait la trace binaire officielle d'exécution du runtime Go (`runtime/trace`) :
```json
{
  "type": "dump_flight_recorder",
  "requestId": "req_129"
}
```

#### 29. `refresh_mcp_servers` / `mcp.refresh_servers` (Rechargement MCP)
Recharge à chaud la configuration des serveurs MCP (`mcp_config.json`) sans redémarrer le Language Server :
```json
{
  "type": "refresh_mcp_servers",
  "requestId": "req_130"
}
```

#### 30. `complete_mcp_oauth` / `mcp.complete_oauth` (OAuth MCP)
Valide les identifiants OAuth reçus pour un serveur MCP tiers :
```json
{
  "type": "complete_mcp_oauth",
  "requestId": "req_131",
  "serverId": "coolify",
  "authCode": "oauth-token-123"
}
```

#### 31. `disconnect_mcp_oauth` / `mcp.disconnect_oauth` (Révocation OAuth MCP)
Révoque les jetons d'accès d'un serveur MCP :
```json
{
  "type": "disconnect_mcp_oauth",
  "requestId": "req_132",
  "serverId": "coolify"
}
```



---

## 7. Sécurité & Résilience Réseau

1. **Anti-DNS Rebinding** : `checkOrigin` n'autorise que `localhost`, `127.0.0.1`, les sous-réseaux privés locaux (`192.168.*`, `10.*`, `172.16.*`) et les tunnels approuvés (`trycloudflare.com`, `pinggy.link`, `ngrok.io`).
2. **Confinement Path Traversal** : `resolvePath` et `saveUploadedImage` valident strictement l'ancrage des chemins dans la racine du workspace ou du sous-dossier `scratch/`.
3. **Protection des Secrets** : Vérification des tokens d'authentification en temps constant via `crypto/subtle.ConstantTimeCompare`.
4. **Buffer Circulaire `StepRecovery`** : 100 trames conservées en mémoire vive par cascade pour un rattrapage immédiat post-reconnexion.
5. **Actions destructives** : `delete_cascade` et `git_discard` exigent `confirm: true` (confirmation explicite au niveau applicatif, en plus du token).
6. **Écriture confinée** : `write_file` passe par le RPC `WriteFile` du LS (pas de chemin direct du daemon) — l'URI est normalisée par `toWorkspaceURI`.
7. **Sidecar destructif** : `manage_sidecar` ne démarre jamais de sidecar par défaut — l'action par défaut est `stop` (2), les actions `start`/`remove` doivent être demandées explicitement.

---

## 8. Source de Vérité Canonique : `antigravity-client`

Pour toute extension ou validation des champs Protobuf du service gRPC-Web `LanguageServerService`, se référer au sous-projet canonique :

- **Emplacement** : [`remote/tools/antigravity-client-main/antigravity-client-main`](file:///C:/Users/amine/Downloads/antigravity-add-model-main/antigravity-add-model-main/remote/tools/antigravity-client-main/antigravity-client-main)
- **Définitions RPC exhaustives (188 méthodes)** : [`src/gen/exa/language_server_pb/language_server_pb.ts`](file:///C:/Users/amine/Downloads/antigravity-add-model-main/antigravity-add-model-main/remote/tools/antigravity-client-main/antigravity-client-main/src/gen/exa/language_server_pb/language_server_pb.ts)
- **Schémas de Trajectoires & Planners** : `src/gen/exa/cortex_pb/` et `src/gen/exa/jetski_cortex_pb/`
- **Parseur d'Événements de Référence** : [`src/core/cascade/event-parser.ts`](file:///C:/Users/amine/Downloads/antigravity-add-model-main/antigravity-add-model-main/remote/tools/antigravity-client-main/antigravity-client-main/src/core/cascade/event-parser.ts)
- **Harnais de validation Node.js** : `src/test-*.ts` (ex: `test-10-tool-approval.ts`, `test-6-model.ts`, etc.)
