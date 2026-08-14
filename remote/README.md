# Antigravity Remote Control OS 🚀

> Contrôle total et temps réel de vos agents Antigravity depuis votre smartphone — en dialoguant **directement avec le moteur Go** (`language_server.exe`) via gRPC-Web et WebSocket.

---

## 🌟 Fonctionnalités Clés & Badges

| Badge | Fonctionnalité | Description |
|:---|:---|:---|
| ![Multimodal](https://img.shields.io/badge/Feature-Multimodal_Images-blue?style=flat-square) | **Prompts Multimodaux** | Téléversement direct de photos, captures d'écran et schémas depuis le smartphone vers `scratch/`. |
| ![StepRecovery](https://img.shields.io/badge/Resilience-StepRecovery_Buffer-success?style=flat-square) | **StepRecovery** | Buffer circulaire FIFO (100 deltas) garantissant zéro perte de streaming lors des bascules Wi-Fi/4G. |
| ![UnifiedDiff](https://img.shields.io/badge/UI-Unified_Diff_Viewer-purple?style=flat-square) | **Revue de Code Mobile** | Diff unifié avec coloration syntaxique (`+` vert, `-` rouge), annotations de lignes et soumission groupée. |
| ![Worktrees](https://img.shields.io/badge/Git-Worktrees_&_Branches-orange?style=flat-square) | **Git Worktrees** | Création de cascades sur des worktrees isolés sans impacter la branche active du PC. |
| ![AskQuestion](https://img.shields.io/badge/UX-AskQuestion_ChoiceCard-yellow?style=flat-square) | **QCM Interactif** | Cartes tactiles de choix unique / multiple pour répondre en 1 tap aux questions de l'agent. |
| ![SlashCommands](https://img.shields.io/badge/Macros-Slash_Commands-cyan?style=flat-square) | **Macros & Slash Commands** | Insertion rapide de `/btw`, `/grill-me`, `/goal`, `/schedule`, `/review`, `/plan`. |

---

## 🎯 Pourquoi ce projet existe

Les agents Antigravity exécutent des tâches longues mais demandent régulièrement des validations humaines (`ask_user`, `run_command`, `ask_question`), vous obligeant à rester devant l'écran de votre PC. 

**La Solution :** Une application mobile couplée à un Daemon Go léger sur votre PC, vous permettant d'approuver des actions, d'injecter des prompts et de surveiller l'agent depuis n'importe où, avec une latence quasi-nulle via un tunnel chiffré (Pinggy SSH / Cloudflare).

Contrairement aux solutions de "scraping" visuel (CDP / DOM) fragiles, **Antigravity Remote** se branche directement sur le service natif `LanguageServerService` via gRPC-Web Protobuf. C'est instantané, stable et insensible aux changements d'interface graphique.

---

## 🏗️ Architecture Globale

```mermaid
graph TD
    subgraph Mobile Flutter
        A[📱 Antigravity Remote App]
        A1[AskQuestionChoiceCard]
        A2[UnifiedDiffViewer]
        A3[Image Picker & Macros]
    end

    subgraph Tunnel Sécurisé
        B[🌐 Pinggy SSH / Cloudflare]
    end

    subgraph PC Local (Daemon Bridge)
        C[⚡ Daemon Go :50999]
        C1[StepRecovery Buffer]
        C2[Git Worktree Discovery]
        C3[Image Handler & Anti-Rebinding]
    end

    subgraph Antigravity Engine
        D[🧠 language_server.exe Hub]
        E[📁 Workspace Local & Brain Directory]
    end

    A -->|WebSocket JSON| B
    B -->|WebSocket JSON| C
    C -->|gRPC-Web Protobuf| D
    C -->|Lecture / Écriture Fichiers| E
```

---

## 🛠️ Technologies Utilisées (Stack)

| Couche | Technologie | Justification |
|:---|:---|:---|
| **Daemon (Relais PC)** | **Go 1.22** | Performance pure, démarrage instantané, binaire autonome de 10 Mo sans dépendances externes. |
| **Tunnel Public** | **Pinggy SSH** / Cloudflare | Expose le port local sur Internet en 1 seconde avec URL sécurisée. |
| **Communication PC ↔ IDE** | **gRPC-Web + Protobuf** | Protocole officiel `LanguageServerService` rétro-ingéniéré sans bibliothèque lourde. |
| **Communication Mobile ↔ PC** | **WebSockets (JSON)** | Flux bidirectionnel asynchrone parfait pour le streaming LLM, les approbations et les uploads. |
| **Application Mobile** | **Flutter (Dart)** | Expérience native iOS & Android fluide (120 Hz), design "Quiet Console", persistance locale. |

---

## 📖 Démarrage Rapide

### 1. Côté PC (Démarrage du Daemon)
```bash
cd remote/daemon
go run ./cmd/daemon
# Ou lancer directement le binaire compilé
./daemon.exe
```
Le Daemon découvre automatiquement le port actif du `language_server.exe` d'Antigravity, ouvre le tunnel public et génère un **QR Code d'appairage** dans le terminal.

### 2. Côté Smartphone (Application Flutter)
1. Ouvrez l'application **Antigravity Remote**.
2. Scannez le QR Code affiché sur votre écran de PC.
3. L'application est immédiatement synchronisée : vos conversations actives, alertes de commandes et formulaires de choix apparaissent en direct.

---

## 📁 Arborescence Détaillée du Projet

```
remote/
├── README.md               # Vue d'ensemble et guide d'utilisation
├── PROTOCOL.md             # Spécification complète gRPC-Web et WebSocket
├── TECH.md                 # Détails techniques d'infrastructure
├── prd.md                  # Spécifications produit et exigences
│
├── daemon/                 # Daemon Bridge (Go)
│   ├── cmd/daemon/main.go  # Point d'entrée
│   └── pkg/
│       ├── connectrpc/     # Parseur et encodeur Protobuf gRPC-Web
│       ├── discovery/      # Découverte automatique des processus et Git Worktrees
│       ├── gateway/        # Serveur WebSocket JSON & StepRecovery
│       └── tunnel/         # Gestionnaire de tunnels SSH / Cloudflare
│
└── mobile/                 # Application Mobile (Flutter)
    ├── lib/
    │   ├── core/           # Protocoles, API WebSocket, parsers de stream
    │   ├── features/       # Écrans de chat, de sessions, et diagnostics
    │   └── widgets/        # AskQuestionChoiceCard, UnifiedDiffViewer, ChatInputBar
    └── test/               # Suite complète de tests unitaires et widgets
```

---

## 🔐 Sécurité & Bonnes Pratiques

- **Token Authentification Fort** : Comparaison en temps constant (`crypto/subtle.ConstantTimeCompare`) pour contrer les attaques temporelles.
- **Anti-DNS Rebinding** : Blocage strict de toutes les origines non autorisées.
- **Confinement Path Traversal** : Résolution sécurisée empêchant tout accès en dehors du workspace ou du dossier `scratch/`.
- **Zéro Écriture Inutile** : Préservation des ressources système et streaming économe en bande passante.
