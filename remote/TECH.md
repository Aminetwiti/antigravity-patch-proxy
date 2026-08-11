# Stack Technique — Antigravity Remote Control OS

> Décisions technologiques, justifications et contraintes. Chaque choix est validé par le terrain (tests réels sur machine), pas par la théorie.

---

## 1. Vue d'ensemble

| Composant | Choix | Justification |
|:---|:---|:---|
| **Daemon Bridge (PC)** | Go 1.22 — binaire unique | Même langage que le `language_server` (Go), stdlib `net/http`, aucun runtime requis, binaire ~10 MB |
| **Client mobile** | APK Android natif — Kotlin + Jetpack Compose | Notifications FCM, service arrière-plan, Room DB, performances 120 Hz, vrai contrôle système |
| **Transport PC ↔ Mobile** | WebSocket (JSON v1) | Typage strict, streaming temps réel, bidirectionnel, supporté nativement par OkHttp et Gorilla |
| **Stockage local mobile** | Room / SQLite | Mode offline-first, synchronisation au retour du réseau |
| **Accès réseau distant** | Cloudflare Tunnel ou Tailscale | Zero Trust, aucun port ouvert sur le routeur |
| **Sérialisation RPC interne** | Protobuf manuel (varint) | Contrainte AGENTS.md : aucune lib protobuf — encodage manuel validé |

---

## 2. Couche 1 — PC : Daemon Bridge (Go)

### 2.1 Pourquoi Go
- Le moteur cible (`language_server`) est **écrit en Go** → mêmes primitives, mêmes formats.
- **Binaire unique** sans dépendance système (facile à distribuer, à lancer au démarrage).
- Goroutines naturelles pour le streaming multi-sessions.

### 2.2 Protocole RPC : gRPC-Web natif (PAS Connect JSON)
Validation terrain (voir [PROTOCOL.md](PROTOCOL.md)) :
- Le serveur répond **404** à `application/connect+json` — il attend **`application/grpc-web+proto`**.
- Header d'auth obligatoire : **`x-codeium-csrf-token`** (héritage Codeium, PAS `X-CSRF-Token`).
- Framing : `1 octet flags + 4 octets longueur BE + payload protobuf`.

### 2.3 Découverte automatique du moteur
1. PowerShell CIM : lister les processus `language_server*`.
2. **Préférer l'instance hub** (`--subclient_type hub`) — les instances IDE répondent 404 au service RPC.
3. Ports candidats : `extension_server_port+1..+20`, sinon `netstat -ano` sur le PID.
4. **Probe Heartbeat** : seul critère fiable = `POST /exa.language_server_pb.LanguageServerService/Heartbeat` → HTTP 200.

### 2.4 Bibliothèques utilisées
| Librairie | Rôle |
|:---|:---|
| `github.com/gorilla/websocket` | Serveur WebSocket du gateway (seule dépendance externe) |
| stdlib `net/http`, `encoding/binary`, `regexp` | Client gRPC-Web + parsing |

---

## 3. Couche 2 — Transport réseau

### 3.1 En LAN
- `ws://<IP-PC>:8089/ws` — connexion directe WiFi local.
- Le Daemon écoute sur toutes les interfaces (`:8089`), pas seulement loopback.

### 3.2 À distance (hors LAN)
| Option | Avantage | Inconvénient |
|:---|:---|:---|
| **Cloudflare Tunnel** (`cloudflared`) | Zero Trust, gratuit, pas de port ouvert | Latence ~50-150 ms selon région |
| **Tailscale** | Mesh WireGuard, très faible latence, auth par identité | Nécessite un compte, appareils enregistrés |

### 3.3 Protocole Daemon ↔ Mobile (v1 = JSON)
- Messages entrants : `{type, requestId, workspacePath?, cascadeId?, callId?, decision?, prompt?}`
- Messages sortants : `{type, requestId, data?, error?}`
- **v2 prévue** : passage en Protobuf binaire (`remote/proto/remote_service.proto`) pour les deltas de streaming.

---

## 4. Couche 3 — Mobile : APK Android natif

### 4.1 Stack applicative
| Technologie | Usage |
|:---|:---|
| **Kotlin** (JVM 1.8) | Langage |
| **Jetpack Compose** (Material 3, BOM 2024.02) | UI déclarative |
| **OkHttp 4.12** | Client WebSocket |
| **Room** (SQLite) | Persistance offline-first |
| **Coroutines + Flow** | Concurrence & réactivité |
| **Hilt** | Injection de dépendances (à ajouter) |
| **FCM** | Notifications push système |

### 4.2 Écrans prévus (V1)
1. **Tableau de bord** — liste des sessions (Cascades), statut, modèle actif
2. **Chat/Stream** — envoi de prompt, affichage des deltas en temps réel
3. **Approbation** — boutons Approuver / Refuser quand un agent bloque sur `ask_user`
4. **Workspace browser** — arborescence + diffs de code (lecture seule)

### 4.3 Gradle (déjà initialisé)
- `minSdk 26` (Android 8.0+), `targetSdk 34`, `compileSdk 34`
- Package : `com.antigravity.remote`

---

## 5. Contraintes & non-choix assumés

- ❌ **Pas de protobuf library** — encodage varint manuel (AGENTS.md, binaire 10 MB).
- ❌ **Pas de framework web** (Express/Koa/Fastify) — `net/http` brut.
- ❌ **Pas de CDP/DOM scraping** — c'est le cœur de la proposition de valeur.
- ❌ **Pas d'iOS en V1** — Android uniquement, PWA de secours possible en V2.
- ❌ **Pas d'auth Google côté mobile** — si la session expire sur le PC, message « reconnectez-vous sur le PC ».
- ❌ **Pas de gestion d'API keys** — tout le secret reste sur le PC.

---

## 6. Évolution de la stack (V2+)

| Besoin futur | Technologie candidate |
|:---|:---|
| Protobuf binaire sur WebSocket | Génération depuis `remote/proto/remote_service.proto` |
| Multi-PC / multi-instance | Table de routage dans le Daemon, ID d'instance |
| Notifications d'approbation | FCM topic par instance |
| Édition de code distante | Endpoint RPC `WriteFile` du language_server (validé en CLI) |
