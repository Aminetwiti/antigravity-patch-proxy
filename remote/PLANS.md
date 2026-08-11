# Plans d'Implémentation — Par Sous-Projet

> Plans détaillés par composant. Chaque plan suit le principe directeur : **chaque marche doit fonctionner à 100% avant de passer à la suivante** (voir [objectif.md](objectif.md)).

---

## Plan A — CLI de Validation (Terminé ✅)

**Objectif :** Prouver que le contrôle RPC du `language_server` est possible.
**Statut :** ✅ Terminé et validé (Phase 1 du PRD)

### Étapes
| # | Étape | Statut |
|:--|:---|:---|
| A1 | Découverte du processus (PID + port + CSRF) | ✅ |
| A2 | Client gRPC-Web manuel (framing, headers) | ✅ |
| A3 | Encodage protobuf manuel (StartCascade, SendMessage) | ✅ |
| A4 | Création de session + envoi de prompt | ✅ |
| A5 | Liste des sessions (GetAllCascadeTrajectories) | ✅ |
| A6 | Gestion des modèles (GetAvailableModels) | ✅ |
| A7 | Workspace tree + lecture de fichiers | ✅ |

### Fichiers
- `cli/src/discovery.ts` — découverte processus + probe Heartbeat
- `cli/src/grpcweb.ts` — client gRPC-Web
- `cli/src/protobuf.ts` — encodeur/décodeur varint manuel
- `cli/src/client.ts` — méthodes RPC haut niveau
- `cli/src/index.ts` — script de validation

### Découverte clé validée
> L'instance qui expose le service RPC est le **hub standalone** (`--subclient_type hub`), pas les instances IDE qui répondent 404.

---

## Plan B — Daemon Bridge Go (En cours 🔄)

**Objectif :** Pont WebSocket entre le mobile et le `language_server`.
**Statut :** 🔄 Fonctionnel — validation E2E en cours

### Étapes
| # | Étape | Statut |
|:--|:---|:---|
| B1 | Découverte automatique (hub + probe Heartbeat) | ✅ |
| B2 | Client gRPC-Web Go (`pkg/connectrpc`) | ✅ |
| B3 | Gateway WebSocket (`pkg/gateway`) | ✅ |
| B4 | CreateCascade via WebSocket | ✅ (testé, reçoit cascadeId) |
| B5 | ListSessions via WebSocket | ✅ (55 trajectoires lues) |
| B6 | **Streaming SendMessage (multi-frames)** | ⏳ EN COURS |
| B7 | SubmitToolApproval via WebSocket | ⏳ |
| B8 | Watchdog : ré-authentification si l'IDE redémarre | ⏳ |
| B9 | Sécurisation (token d'accès, origine, TLS optionnel) | ⏳ |

### Plan d'implémentation B6 — Streaming multi-frames
1. **Client** : modifier `client.go` → `CallStream(method, payload, onFrame)` qui itère TOUTES les frames gRPC-Web (pas seulement la première), et ne s'arrête pas sur une frame vide.
2. **Gateway** : `send_prompt` → émettre un événement WS par frame reçue :
   ```json
   {"type":"stream","requestId":"p1","frame":1,"data":{...decoded...}}
   {"type":"stream_end","requestId":"p1"}
   ```
3. **Timeout** : 120 s par prompt (les agents longs dépassent 60 s).
4. **Test** : `scratch/test_ws_prompt.ps1` — attendre ≥ 3 frames ou un `finished`.

### Plan d'implémentation B7 — SubmitToolApproval
1. **Schéma protobuf** : confirmer les numéros de champs exacts (actuellement : 1=cascadeID, 2=callID, 3=decision — à vérifier contre le stream).
2. **Gateway** : `submit_approval` → appeler `SubmitToolApproval` avec `DECISION_ALLOW` (1) / `DECISION_DENY` (2).
3. **Test** : prompt déclenchant `run_command`, attendre l'événement d'approbation, approuver, vérifier la reprise du stream.

### Plan d'implémentation B8 — Watchdog CSRF
1. Goroutine toutes les 10 s : `discovery.Discover()`.
2. Si PID/token changent → recréer le `connectrpc.Client`, logguer « re-authentifié ».
3. Les connexions WS actives restent ouvertes (le client RPC est partagé).

### Fichiers
- `daemon/main.go` — bootstrap + endpoints HTTP
- `daemon/pkg/discovery/scanner.go` — découverte hub + probe
- `daemon/pkg/connectrpc/client.go` — transport gRPC-Web
- `daemon/pkg/connectrpc/protobuf.go` — encodeurs varint manuels
- `daemon/pkg/connectrpc/methods.go` — méthodes RPC
- `daemon/pkg/gateway/websocket.go` — protocole JSON mobile

### Protocole WS v1 (en vigueur)
```json
→ {"type":"heartbeat","requestId":"r1"}
← {"type":"response","requestId":"r1","data":{...}}

→ {"type":"list_sessions","requestId":"r2"}
← {"type":"response","requestId":"r2","data":{"fields":[...]}}

→ {"type":"create_cascade","requestId":"r3","workspacePath":"C:\\path"}
← {"type":"response","requestId":"r3","data":{"fields":[{"field":1,"text":"<cascadeId>"}]}}
```

---

## Plan C — Application Mobile Android (À venir 📋)

**Objectif :** Télécommande native — tableau de bord, chat, approbations, workspace.
**Statut :** 📋 Planifié — dépend de B6/B7 validés

### Étapes
| # | Étape | Critère de succès |
|:--|:---|:---|
| C1 | Connexion WebSocket au Daemon (OkHttp) | État de connexion visible, reconnexion auto |
| C2 | Écran tableau de bord (liste sessions) | 55 sessions affichées depuis le hub |
| C3 | Écran chat + streaming | Deltas affichés en temps réel |
| C4 | Boutons d'approbation | Approuver/Refuser un `run_command` bloqué |
| C5 | Workspace browser | Arborescence + diffs (lecture seule) |
| C6 | Room DB offline-first | Historique consultable hors-ligne |
| C7 | Notifications FCM | Alerte système quand un agent attend |

### Plan d'implémentation C1 — Connexion WebSocket
1. **Dépendance** : OkHttp 4.12 (déjà dans `build.gradle.kts`).
2. **Service** : `WebSocketService` (foreground) qui maintient la connexion et expose un `StateFlow<ConnectionState>`.
3. **Repository** : `DaemonRepository` — mapping messages JSON ↔ modèles Kotlin (`DaemonEvent`).
4. **Écran** : champ « Adresse du PC » (ex. `ws://192.168.1.20:8089/ws`), bouton connecter.
5. **Test** : émulateur Android + daemon local → liste des sessions affichée.

### Plan d'implémentation C4 — Approbation tactile
1. **Modèle** : `ApprovalRequest(cascadeId, callId, toolName, command)`.
2. **UI** : carte avec la commande à exécuter + boutons Approuver (vert) / Refuser (rouge).
3. **Action** : `submit_approval` avec `decision:"allow"|"deny"`.
4. **Feedback** : le stream reprend → l'UI passe en mode « exécution en cours ».

### Plan d'implémentation C6 — Offline-first
1. **Room** : `SessionEntity`, `MessageEntity`, `ApprovalEntity`.
2. **Sync** : au retour du réseau, rejouer les actions en attente (queue).
3. **Anti-doublon** : `requestId` généré côté mobile → idempotence côté daemon.

### Fichiers cibles
- `mobile/app/src/main/java/com/antigravity/remote/`
  - `data/ws/WebSocketService.kt`
  - `data/ws/DaemonRepository.kt`
  - `data/db/AppDatabase.kt` (+ DAOs)
  - `ui/DashboardScreen.kt`, `ui/ChatScreen.kt`, `ui/ApprovalCard.kt`
  - `MainActivity.kt`

---

## Plan D — Infrastructure & Déploiement (À venir 📋)

| # | Étape | Détail |
|:--|:---|:---|
| D1 | Packaging Daemon | Binaire Windows/macOS/Linux (cross-compile Go) |
| D2 | Autostart | Tâche planifiée Windows / launchd macOS |
| D3 | Tunnel | `cloudflared` ou Tailscale — script d'installation + config |
| D4 | Versioning | `daemon --version`, protocole WS versionné |
| D5 | Sécurité | Token d'accès aléatoire exigé par le gateway, TLS optionnel |

---

## Dépendances entre plans

```
A (CLI) ✅ ──► B (Daemon) 🔄 ──► C (Mobile) 📋
                        │
                        └──► D (Déploiement) 📋
```

**Règle :** ne pas commencer C avant la fin de B6 (streaming) et B7 (approbation).
