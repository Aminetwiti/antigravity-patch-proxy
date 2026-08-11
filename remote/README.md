# Antigravity Remote Control OS

> Contrôle total d'Antigravity 2.0 depuis un smartphone — en dialoguant **directement avec le moteur Go** (`language_server`) via son protocole natif, et non en simulant des clics sur l'interface (CDP).

---

## Pourquoi ce projet existe

Les agents Antigravity exécutent des tâches longues mais **se bloquent régulièrement** pour demander une validation humaine (`ask_user`). Le développeur est enchaîné à son écran.

Les 5 solutions communautaires existantes passent toutes par le **CDP (scraping DOM)** → fragiles, lentes, cassées à chaque mise à jour.

**Nous** parlons directement au `language_server` (le cerveau Go) via **gRPC-Web** → stable, rapide, contrôle total. Voir [objectif.md](objectif.md) pour la vision complète.

---

## Architecture

```
Smartphone (APK Android)                PC (Daemon Go)                Antigravity
        │                                    │                           │
   WebSocket JSON                      gRPC-Web + Protobuf         language_server
        │                                    │                     (--subclient_type hub)
        ▼                                    ▼                           ▼
   Écrans Kotlin/Compose              Découverte auto                CascadeService
   (dashboard, chat,                  (PID + port + CSRF)           (sessions, prompts,
    approbations)                     + proxy RPC                   approbations, workspace)
```

## Stack Technologique

| Couche | Technologie |
|:---|:---|
| **PC — Daemon** | Go 1.22, stdlib `net/http`, `gorilla/websocket` |
| **RPC moteur** | gRPC-Web + Protobuf (varint manuel, aucune lib) |
| **Mobile** | Kotlin, Jetpack Compose (Material 3), OkHttp, Room, FCM |
| **Réseau distant** | Cloudflare Tunnel / Tailscale (Zero Trust) |

➡️ Détails et justifications : [TECH.md](TECH.md)

---

## Statut du projet

| Phase | Composant | Statut |
|:---|:---|:---|
| **1** | CLI de validation du protocole (`remote/cli/`) | ✅ Terminée |
| **2** | Daemon Bridge Go (`remote/daemon/`) | 🔄 En cours — streaming E2E |
| **3** | APK Android (`remote/mobile/`) | 📋 Planifiée |

> [!NOTE]
> **Dernière validation (2026-08-11) :** le Daemon découvre automatiquement le hub, et le gateway WebSocket crée des sessions (`create_cascade` → `cascadeId`) et liste les 55 trajectoires du hub. Le streaming multi-frames des prompts est en cours.

---

## Démarrage rapide

### Prérequis
- Antigravity IDE **ouvert** (le hub `language_server` tourne)
- Windows (PowerShell), Go 1.22+, Node.js 20+

### 1. Valider la découverte (CLI)
```powershell
cd remote/cli
npm install
npm run scan          # affiche PID + port + CSRF du hub
```

### 2. Lancer le Daemon (pont WebSocket)
```powershell
cd remote/daemon
go build -o daemon.exe .
.\daemon.exe          # écoute sur ws://localhost:8089/ws
```

### 3. Tester le gateway WebSocket
```powershell
powershell -File ..\scratch\test_ws_full.ps1
# attendu : heartbeat OK + liste des sessions + cascadeId à la création
```

---

## Documentation

| Document | Contenu |
|:---|:---|
| [objectif.md](objectif.md) | Vision produit, problème, solution |
| [prd.md](prd.md) | Product Requirements Document (V1 étendue) |
| [TECH.md](TECH.md) | **Stack technique, choix et justifications** |
| [PLANS.md](PLANS.md) | **Plans d'implémentation par sous-projet** |
| [PROTOCOL.md](PROTOCOL.md) | Protocole gRPC-Web validé (référence infra) |
| [localharness.md](localharness.md) | Analyse du binaire `language_server` |
| [docs.md](docs.md) | État de l'art communautaire (CDP vs RPC) |

---

## Arborescence

```
remote/
├── README.md            # Ce fichier
├── TECH.md              # Stack technique
├── PLANS.md             # Plans par sous-projet
├── PROTOCOL.md          # Protocole gRPC-Web validé
├── objectif.md          # Vision
├── prd.md               # PRD
├── instruction.md       # Marches de validation (Phase 1)
├── docs.md              # Recherche communautaire
├── localharness.md      # Analyse du binaire
│
├── proto/               # Contrat Protobuf Daemon ↔ Mobile (v2)
│   └── remote_service.proto
│
├── cli/                 # Phase 1 : validation du protocole (TypeScript)
│   └── src/             # discovery, grpcweb, protobuf, client, index
│
├── daemon/              # Phase 2 : Daemon Bridge (Go)
│   ├── main.go
│   └── pkg/
│       ├── discovery/   # Découverte hub + probe Heartbeat
│       ├── connectrpc/  # Client gRPC-Web + protobuf manuel
│       └── gateway/     # WebSocket JSON (protocole mobile)
│
├── mobile/              # Phase 3 : APK Android (Kotlin/Compose)
│   └── app/             # Gradle initialisé, package com.antigravity.remote
│
└── scratch/             # Scripts de test (probes, WS E2E)
```

---

## Découvertes clés (rétro-ingénierie)

1. Le service RPC s'appelle `exa.language_server_pb.LanguageServerService` — **pas** `antigravity.v1.CascadeService`.
2. Le port actif est celui du **hub standalone** (`--subclient_type hub`), pas les instances IDE.
3. Header d'auth : **`x-codeium-csrf-token`** (héritage Codeium).
4. Framing gRPC-Web : `1 octet flags + 4 octets BE + payload protobuf`.
5. Les méthodes validées : `Heartbeat`, `GetStatus`, `StartCascade`, `GetAllCascadeTrajectories`, `SendUserCascadeMessage`.

---

## Prochaines étapes

1. **B6** — Streaming multi-frames `SendUserCascadeMessage` (deltas temps réel via WS)
2. **B7** — `SubmitToolApproval` (approbation d'outils à distance)
3. **B8** — Watchdog CSRF (reconnexion auto si l'IDE redémarre)
4. **C1** — Première connexion APK Android au Daemon

➡️ Détail : [PLANS.md](PLANS.md)
