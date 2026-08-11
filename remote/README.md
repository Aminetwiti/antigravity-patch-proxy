# Antigravity Remote Control OS 🚀

> Contrôle total de vos agents Antigravity depuis votre smartphone — en dialoguant **directement avec le moteur Go** (`language_server`) via son protocole natif.

---

## 🎯 Pourquoi ce projet existe

Les agents Antigravity exécutent des tâches longues mais se bloquent souvent pour demander une validation humaine (`ask_user`), vous obligeant à rester devant l'écran de votre PC. 

**La Solution :** Une application mobile couplée à un Daemon (serveur relais) sur votre PC, vous permettant d'approuver des actions, de lancer des prompts et de surveiller l'agent depuis n'importe où, avec une latence quasi-nulle grâce à un tunnel SSH.

Contrairement aux autres solutions qui s'appuient sur le "scraping" d'interface (CDP) très instable, **Antigravity Remote** se branche directement sur le cœur d'Antigravity via gRPC-Web (Protobuf). C'est stable, robuste et instantané.

---

## 🏗 Architecture globale

Le système se compose de 3 piliers principaux qui communiquent entre eux :

```mermaid
graph TD
    A[Application Mobile Flutter] -->|WebSocket JSON| B(Tunnel Pinggy/Cloudflare)
    B -->|WebSocket JSON| C[Daemon Bridge Go]
    C -->|Découverte Automatique| D[LocalHarness]
    C -->|gRPC-Web Protobuf| E[Language Server Hub]
    
    subgraph PC Local (Doctor UI)
    C
    D
    E
    end
```

---

## 🛠 Technologies utilisées (Stack)

| Couche | Technologie | Justification |
|:---|:---|:---|
| **Daemon (Relais PC)** | **Go 1.22** | Performance, empreinte mémoire faible, idéal pour les serveurs et le réseau. |
| **Tunnel Public** | **Pinggy SSH** / Cloudflare | Expose le port local (8080) sur Internet en 1 seconde sans configuration lourde. |
| **Communication PC ↔ IDE** | **gRPC-Web + Protobuf** | Rétro-ingénierie du vrai protocole d'Antigravity (manuel, sans bibliothèque pour rester léger). |
| **Communication Mobile ↔ PC**| **WebSockets (JSON)** | Flux bidirectionnel asynchrone parfait pour le streaming de texte (LLM). |
| **Interface PC (Manager)** | **Electron (Doctor UI)** | S'intègre naturellement à l'écosystème existant de l'utilisateur pour gérer le Daemon et scanner le QR Code. |
| **Application Mobile** | **Flutter (Dart)** | Multi-plateforme (iOS/Android), UI riche, gestion réactive de l'état avec BLoC/Riverpod. |

---

## 🚀 Phases du projet (Statut d'implémentation)

### ✅ Phase 1 : Rétro-ingénierie et Client CLI (Terminée)
- Analyse du binaire `language_server` (LocalHarness).
- Extraction du jeton d'authentification CSRF (hérité de Codeium).
- Mapping manuel des structures Protobuf (ID: `exa.language_server_pb.LanguageServerService`).
- **Validation :** Scripts TypeScript capables de lister les sessions et d'envoyer des prompts directement.

### ✅ Phase 2 : Le Daemon Bridge Go (Terminée)
- **Découverte automatique :** Le Daemon trouve tout seul le processus Antigravity et récupère le jeton.
- **Watchdog CSRF :** Si l'IDE redémarre, le Daemon détecte le nouveau port et met à jour ses identifiants.
- **Passerelle WebSocket :** Traduction instantanée des requêtes JSON (Mobile) vers Protobuf (Antigravity).
- **Auto-Tunneling :** Lancement asynchrone de `ssh` (Pinggy) avec parsing des logs (`stdout`/`stderr`) pour extraire l'URL publique automatiquement.

### ✅ Phase 3 : Intégration Doctor UI & Mobile (Terminée / En cours de design UI)
- **Doctor UI :** Refonte de l'interface Electron pour piloter le Daemon (Start/Stop).
- **Génération QR Code :** Une fois le tunnel Pinggy établi, Doctor UI génère un QR Code contenant l'URL publique et le Token de sécurité.
- **Flutter App :** L'application mobile scanne le QR Code et se connecte au WebSockets.

---

## 📖 Démarrage Rapide (Comment utiliser)

### 1. Côté PC (Doctor UI)
1. Ouvrez **Doctor UI** (l'interface Electron).
2. Allez dans l'onglet **Remote**.
3. Définissez le port (ex: `8080`), choisissez le tunnel (`pinggy`) et définissez un Token de sécurité (ex: `516d5qyy`).
4. Cliquez sur **Start Remote Server**.
5. Le Daemon Go se lance, le tunnel s'ouvre, et un **QR Code** apparaît à l'écran.

### 2. Côté Smartphone (Flutter)
1. Lancez l'application **Antigravity Remote**.
2. Scannez le QR Code affiché sur votre écran PC.
3. L'application est connectée ! Vous pouvez maintenant voir les sessions actives et répondre aux requêtes `ask_user`.

---

## 📁 Arborescence détaillée du projet

```
remote/
├── README.md            # Ce fichier de documentation
├── TECH.md              # Détails techniques historiques
├── prd.md               # Product Requirements Document
├── docs.md              # Recherches et notes communautaires
│
├── daemon/              # Code source du Serveur Relais (Go)
│   ├── main.go          # Point d'entrée
│   ├── daemon.exe       # Binaire compilé (Windows)
│   └── pkg/
│       ├── connectrpc/  # Encodeur/Décodeur Protobuf manuel
│       ├── discovery/   # Scanner de processus (PID/CSRF) & Watchdog
│       ├── gateway/     # Serveur WebSocket JSON
│       └── tunnel/      # Gestionnaire Cloudflare/Pinggy SSH
│
├── tools/
│   └── antigravity-client/ # (Phase 1) Scripts TS de test du protocole
│
└── ag-doctor-ui/        # Application PC (Electron) - Pilotage du Daemon
    ├── src/main.ts      # Gestion du cycle de vie du processus daemon.exe
    └── src/renderer/    # Interface UI avec le QR Code auto-généré
```

---

## 🔐 Sécurité

- Le Daemon est protégé par un **Token d'authentification** fort, partagé via le QR Code.
- Toutes les communications passent par des tunnels sécurisés (WSS / HTTPS).
- Le Daemon n'a pas besoin des privilèges Administrateur (scan LocalHarness basé sur WMI en espace utilisateur).
- L'URL Pinggy SSH change à chaque démarrage (si on utilise la version gratuite), évitant toute attaque ciblée de long terme.
