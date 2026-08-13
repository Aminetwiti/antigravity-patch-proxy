# Stack Technique â€” Antigravity Remote Control OS

> DÃ©cisions technologiques, justifications et contraintes. Chaque choix est validÃ© par le terrain (tests rÃ©els sur machine), pas par la thÃ©orie.

---

## 1. Vue d'ensemble

| Composant | Choix | Justification |
|:---|:---|:---|
| **Daemon Bridge (PC)** | Go 1.22 â€” binaire unique | MÃªme langage que le `language_server` (Go), stdlib `net/http`, aucun runtime requis, binaire ~10 MB |
| **Client mobile** | APK Android natif â€” Kotlin + Jetpack Compose | Notifications FCM, service arriÃ¨re-plan, Room DB, performances 120 Hz, vrai contrÃ´le systÃ¨me |
| **Transport PC â†” Mobile** | WebSocket (JSON v1) | Typage strict, streaming temps rÃ©el, bidirectionnel, supportÃ© nativement par OkHttp et Gorilla |
| **Stockage local mobile** | Room / SQLite | Mode offline-first, synchronisation au retour du rÃ©seau |
| **AccÃ¨s rÃ©seau distant** | Cloudflare Tunnel ou Tailscale | Zero Trust, aucun port ouvert sur le routeur |
| **SÃ©rialisation RPC interne** | Protobuf manuel (varint) | Contrainte AGENTS.md : aucune lib protobuf â€” encodage manuel validÃ© |

---

## 2. Couche 1 â€” PC : Daemon Bridge (Go)

### 2.1 Pourquoi Go
- Le moteur cible (`language_server`) est **Ã©crit en Go** â†’ mÃªmes primitives, mÃªmes formats.
- **Binaire unique** sans dÃ©pendance systÃ¨me (facile Ã  distribuer, Ã  lancer au dÃ©marrage).
- Goroutines naturelles pour le streaming multi-sessions.

### 2.2 Protocole RPC : gRPC-Web natif (PAS Connect JSON)
Validation terrain (voir [PROTOCOL.md](PROTOCOL.md)) :
- Le serveur rÃ©pond **404** Ã  `application/connect+json` â€” il attend **`application/grpc-web+proto`**.
- Header d'auth obligatoire : **`x-codeium-csrf-token`** (hÃ©ritage Codeium, PAS `X-CSRF-Token`).
- Framing : `1 octet flags + 4 octets longueur BE + payload protobuf`.

### 2.3 DÃ©couverte automatique du moteur
1. PowerShell CIM : lister les processus `language_server*`.
2. **PrÃ©fÃ©rer l'instance hub** (`--subclient_type hub`) â€” les instances IDE rÃ©pondent 404 au service RPC.
3. Ports candidats : `extension_server_port+1..+20`, sinon `netstat -ano` sur le PID.
4. **Probe Heartbeat** : seul critÃ¨re fiable = `POST /exa.language_server_pb.LanguageServerService/Heartbeat` â†’ HTTP 200.

### 2.4 BibliothÃ¨ques utilisÃ©es
| Librairie | RÃ´le |
|:---|:---|
| `github.com/gorilla/websocket` | Serveur WebSocket du gateway (seule dÃ©pendance externe) |
| stdlib `net/http`, `encoding/binary`, `regexp` | Client gRPC-Web + parsing |

---

## 3. Couche 2 â€” Transport rÃ©seau

### 3.1 En LAN
- `ws://<IP-PC>:8090/ws` â€” connexion directe WiFi local.
- Le Daemon écoute sur toutes les interfaces (`:8090`), pas seulement loopback.

### 3.2 Ã€ distance (hors LAN)
| Option | Avantage | InconvÃ©nient |
|:---|:---|:---|
| **Cloudflare Tunnel** (`cloudflared`) | Zero Trust, gratuit, pas de port ouvert | Latence ~50-150 ms selon rÃ©gion |
| **Tailscale** | Mesh WireGuard, trÃ¨s faible latence, auth par identitÃ© | NÃ©cessite un compte, appareils enregistrÃ©s |

### 3.3 Protocole Daemon â†” Mobile (v1 = JSON)
- Messages entrants : `{type, requestId, workspacePath?, cascadeId?, callId?, decision?, prompt?}`
- Messages sortants : `{type, requestId, data?, error?}`
- **v2 prÃ©vue** : passage en Protobuf binaire (`remote/proto/remote_service.proto`) pour les deltas de streaming.

---

## 4. Couche 3 â€” Mobile : APK Android natif

### 4.1 Stack applicative
| Technologie | Usage |
|:---|:---|
| **Kotlin** (JVM 1.8) | Langage |
| **Jetpack Compose** (Material 3, BOM 2024.02) | UI dÃ©clarative |
| **OkHttp 4.12** | Client WebSocket |
| **Room** (SQLite) | Persistance offline-first |
| **Coroutines + Flow** | Concurrence & rÃ©activitÃ© |
| **Hilt** | Injection de dÃ©pendances (Ã  ajouter) |
| **FCM** | Notifications push systÃ¨me |

### 4.2 Ã‰crans prÃ©vus (V1)
1. **Tableau de bord** â€” liste des sessions (Cascades), statut, modÃ¨le actif
2. **Chat/Stream** â€” envoi de prompt, affichage des deltas en temps rÃ©el
3. **Approbation** â€” boutons Approuver / Refuser quand un agent bloque sur `ask_user`
4. **Workspace browser** â€” arborescence + diffs de code (lecture seule)

### 4.3 Gradle (dÃ©jÃ  initialisÃ©)
- `minSdk 26` (Android 8.0+), `targetSdk 34`, `compileSdk 34`
- Package : `com.antigravity.remote`

---

## 5. Contraintes & non-choix assumÃ©s

- âŒ **Pas de protobuf library** â€” encodage varint manuel (AGENTS.md, binaire 10 MB).
- âŒ **Pas de framework web** (Express/Koa/Fastify) â€” `net/http` brut.
- âŒ **Pas de CDP/DOM scraping** â€” c'est le cÅ“ur de la proposition de valeur.
- âŒ **Pas d'iOS en V1** â€” Android uniquement, PWA de secours possible en V2.
- âŒ **Pas d'auth Google cÃ´tÃ© mobile** â€” si la session expire sur le PC, message Â« reconnectez-vous sur le PC Â».
- âŒ **Pas de gestion d'API keys** â€” tout le secret reste sur le PC.

---

## 6. Ã‰volution de la stack (V2+)

| Besoin futur | Technologie candidate |
|:---|:---|
| Protobuf binaire sur WebSocket | GÃ©nÃ©ration depuis `remote/proto/remote_service.proto` |
| Multi-PC / multi-instance | Table de routage dans le Daemon, ID d'instance |
| Notifications d'approbation | FCM topic par instance |
| Ã‰dition de code distante | Endpoint RPC `WriteFile` du language_server (validÃ© en CLI) |


