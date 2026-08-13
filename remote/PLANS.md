# Plans d'ImplÃ©mentation â€” Par Sous-Projet

> Plans dÃ©taillÃ©s par composant. Chaque plan suit le principe directeur : **chaque marche doit fonctionner Ã  100% avant de passer Ã  la suivante** (voir [objectif.md](objectif.md)).

---

## Plan A â€” CLI de Validation (TerminÃ© âœ…)

**Objectif :** Prouver que le contrÃ´le RPC du `language_server` est possible.
**Statut :** âœ… TerminÃ© et validÃ© (Phase 1 du PRD)

### Ã‰tapes
| # | Ã‰tape | Statut |
|:--|:---|:---|
| A1 | DÃ©couverte du processus (PID + port + CSRF) | âœ… |
| A2 | Client gRPC-Web manuel (framing, headers) | âœ… |
| A3 | Encodage protobuf manuel (StartCascade, SendMessage) | âœ… |
| A4 | CrÃ©ation de session + envoi de prompt | âœ… |
| A5 | Liste des sessions (GetAllCascadeTrajectories) | âœ… |
| A6 | Gestion des modÃ¨les (GetAvailableModels) | âœ… |
| A7 | Workspace tree + lecture de fichiers | âœ… |

### Fichiers
- `cli/src/discovery.ts` â€” dÃ©couverte processus + probe Heartbeat
- `cli/src/grpcweb.ts` â€” client gRPC-Web
- `cli/src/protobuf.ts` â€” encodeur/dÃ©codeur varint manuel
- `cli/src/client.ts` â€” mÃ©thodes RPC haut niveau
- `cli/src/index.ts` â€” script de validation

### DÃ©couverte clÃ© validÃ©e
> L'instance qui expose le service RPC est le **hub standalone** (`--subclient_type hub`), pas les instances IDE qui rÃ©pondent 404.

---

## Plan B â€” Daemon Bridge Go (En cours ðŸ”„)

**Objectif :** Pont WebSocket entre le mobile et le `language_server`.
**Statut :** ðŸ”„ Fonctionnel â€” validation E2E en cours

### Ã‰tapes
| # | Ã‰tape | Statut |
|:--|:---|:---|
| B1 | DÃ©couverte automatique (hub + probe Heartbeat) | âœ… |
| B2 | Client gRPC-Web Go (`pkg/connectrpc`) | âœ… |
| B3 | Gateway WebSocket (`pkg/gateway`) | âœ… |
| B4 | CreateCascade via WebSocket | âœ… (testÃ©, reÃ§oit cascadeId) |
| B5 | ListSessions via WebSocket | âœ… (55 trajectoires lues) |
| B6 | **Streaming SendMessage (multi-frames)** | â³ EN COURS |
| B7 | SubmitToolApproval via WebSocket | â³ |
| B8 | Watchdog : rÃ©-authentification si l'IDE redÃ©marre | â³ |
| B9 | SÃ©curisation (token d'accÃ¨s, origine, TLS optionnel) | â³ |

### Plan d'implÃ©mentation B6 â€” Streaming multi-frames
1. **Client** : modifier `client.go` â†’ `CallStream(method, payload, onFrame)` qui itÃ¨re TOUTES les frames gRPC-Web (pas seulement la premiÃ¨re), et ne s'arrÃªte pas sur une frame vide.
2. **Gateway** : `send_prompt` â†’ Ã©mettre un Ã©vÃ©nement WS par frame reÃ§ue :
   ```json
   {"type":"stream","requestId":"p1","frame":1,"data":{...decoded...}}
   {"type":"stream_end","requestId":"p1"}
   ```
3. **Timeout** : 120 s par prompt (les agents longs dÃ©passent 60 s).
4. **Test** : `scratch/test_ws_prompt.ps1` â€” attendre â‰¥ 3 frames ou un `finished`.

### Plan d'implÃ©mentation B7 â€” SubmitToolApproval
1. **SchÃ©ma protobuf** : confirmer les numÃ©ros de champs exacts (actuellement : 1=cascadeID, 2=callID, 3=decision â€” Ã  vÃ©rifier contre le stream).
2. **Gateway** : `submit_approval` â†’ appeler `SubmitToolApproval` avec `DECISION_ALLOW` (1) / `DECISION_DENY` (2).
3. **Test** : prompt dÃ©clenchant `run_command`, attendre l'Ã©vÃ©nement d'approbation, approuver, vÃ©rifier la reprise du stream.

### Plan d'implÃ©mentation B8 â€” Watchdog CSRF
1. Goroutine toutes les 10 s : `discovery.Discover()`.
2. Si PID/token changent â†’ recrÃ©er le `connectrpc.Client`, logguer Â« re-authentifiÃ© Â».
3. Les connexions WS actives restent ouvertes (le client RPC est partagÃ©).

### Fichiers
- `daemon/main.go` â€” bootstrap + endpoints HTTP
- `daemon/pkg/discovery/scanner.go` â€” dÃ©couverte hub + probe
- `daemon/pkg/connectrpc/client.go` â€” transport gRPC-Web
- `daemon/pkg/connectrpc/protobuf.go` â€” encodeurs varint manuels
- `daemon/pkg/connectrpc/methods.go` â€” mÃ©thodes RPC
- `daemon/pkg/gateway/websocket.go` â€” protocole JSON mobile

### Protocole WS v1 (en vigueur)
```json
â†’ {"type":"heartbeat","requestId":"r1"}
â† {"type":"response","requestId":"r1","data":{...}}

â†’ {"type":"list_sessions","requestId":"r2"}
â† {"type":"response","requestId":"r2","data":{"fields":[...]}}

â†’ {"type":"create_cascade","requestId":"r3","workspacePath":"C:\\path"}
â† {"type":"response","requestId":"r3","data":{"fields":[{"field":1,"text":"<cascadeId>"}]}}
```

---

## Plan C â€” Application Mobile Android (Ã€ venir ðŸ“‹)

**Objectif :** TÃ©lÃ©commande native â€” tableau de bord, chat, approbations, workspace.
**Statut :** ðŸ“‹ PlanifiÃ© â€” dÃ©pend de B6/B7 validÃ©s

### Ã‰tapes
| # | Ã‰tape | CritÃ¨re de succÃ¨s |
|:--|:---|:---|
| C1 | Connexion WebSocket au Daemon (OkHttp) | Ã‰tat de connexion visible, reconnexion auto |
| C2 | Ã‰cran tableau de bord (liste sessions) | 55 sessions affichÃ©es depuis le hub |
| C3 | Ã‰cran chat + streaming | Deltas affichÃ©s en temps rÃ©el |
| C4 | Boutons d'approbation | Approuver/Refuser un `run_command` bloquÃ© |
| C5 | Workspace browser | Arborescence + diffs (lecture seule) |
| C6 | Room DB offline-first | Historique consultable hors-ligne |
| C7 | Notifications FCM | Alerte systÃ¨me quand un agent attend |

### Plan d'implÃ©mentation C1 â€” Connexion WebSocket
1. **DÃ©pendance** : OkHttp 4.12 (dÃ©jÃ  dans `build.gradle.kts`).
2. **Service** : `WebSocketService` (foreground) qui maintient la connexion et expose un `StateFlow<ConnectionState>`.
3. **Repository** : `DaemonRepository` â€” mapping messages JSON â†” modÃ¨les Kotlin (`DaemonEvent`).
4. **Ã‰cran** : champ Â« Adresse du PC Â» (ex. `ws://192.168.1.20:8090/ws`), bouton connecter.
5. **Test** : Ã©mulateur Android + daemon local â†’ liste des sessions affichÃ©e.

### Plan d'implÃ©mentation C4 â€” Approbation tactile
1. **ModÃ¨le** : `ApprovalRequest(cascadeId, callId, toolName, command)`.
2. **UI** : carte avec la commande Ã  exÃ©cuter + boutons Approuver (vert) / Refuser (rouge).
3. **Action** : `submit_approval` avec `decision:"allow"|"deny"`.
4. **Feedback** : le stream reprend â†’ l'UI passe en mode Â« exÃ©cution en cours Â».

### Plan d'implÃ©mentation C6 â€” Offline-first
1. **Room** : `SessionEntity`, `MessageEntity`, `ApprovalEntity`.
2. **Sync** : au retour du rÃ©seau, rejouer les actions en attente (queue).
3. **Anti-doublon** : `requestId` gÃ©nÃ©rÃ© cÃ´tÃ© mobile â†’ idempotence cÃ´tÃ© daemon.

### Fichiers cibles
- `mobile/app/src/main/java/com/antigravity/remote/`
  - `data/ws/WebSocketService.kt`
  - `data/ws/DaemonRepository.kt`
  - `data/db/AppDatabase.kt` (+ DAOs)
  - `ui/DashboardScreen.kt`, `ui/ChatScreen.kt`, `ui/ApprovalCard.kt`
  - `MainActivity.kt`

---

## Plan D â€” Infrastructure & DÃ©ploiement (Ã€ venir ðŸ“‹)

| # | Ã‰tape | DÃ©tail |
|:--|:---|:---|
| D1 | Packaging Daemon | Binaire Windows/macOS/Linux (cross-compile Go) |
| D2 | Autostart | TÃ¢che planifiÃ©e Windows / launchd macOS |
| D3 | Tunnel | `cloudflared` ou Tailscale â€” script d'installation + config |
| D4 | Versioning | `daemon --version`, protocole WS versionnÃ© |
| D5 | SÃ©curitÃ© | Token d'accÃ¨s alÃ©atoire exigÃ© par le gateway, TLS optionnel |

---

## DÃ©pendances entre plans

```
A (CLI) âœ… â”€â”€â–º B (Daemon) ðŸ”„ â”€â”€â–º C (Mobile) ðŸ“‹
                        â”‚
                        â””â”€â”€â–º D (DÃ©ploiement) ðŸ“‹
```

**RÃ¨gle :** ne pas commencer C avant la fin de B6 (streaming) et B7 (approbation).

