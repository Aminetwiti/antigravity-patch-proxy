# PRD — Antigravity Remote Control OS (V1 Étendue)

## Product Requirements Document

---

## 1. Périmètre de la V1 Étendue

La V1 couvre les fonctionnalités suivantes, classées par priorité :

### P0 — Critique (sans ça, le produit ne sert à rien)

| # | Fonctionnalité | Endpoint RPC associé | Description |
|:--|:---|:---|:---|
| 1 | Découverte du `localharness` | — (processus système) | Scanner les processus, extraire le port + token CSRF |
| 2 | Création de session | `CreateCascade` | Instancier une Cascade rattachée à un workspace |
| 3 | Envoi de prompt | `SendCascadeMessage` | Envoyer un message texte à l'agent et recevoir le stream de réponse |
| 4 | Approbation d'outils | `SubmitToolApproval` | Valider ou refuser les commandes `run_command` bloquées par `ask_user` |
| 5 | Liste des sessions | `GetAllCascades` | Récupérer toutes les sessions actives pour basculer entre elles |

### P1 — Important (V1 étendue)

| # | Fonctionnalité | Endpoint RPC associé | Description |
|:--|:---|:---|:---|
| 6 | Arborescence du workspace | `GetWorkspaceTree` | Afficher la structure du projet (dossiers, fichiers) |
| 7 | Lecture de fichiers | `GetFileContent` (à confirmer) | Lire le contenu d'un fichier du workspace |
| 8 | Visualisation des diffs | (via les événements du stream) | Afficher les modifications de code apportées par l'agent |
| 9 | Historique de conversation | `GetCascadeHistory` (à confirmer) | Relire les échanges passés d'une session |

### P2 — Souhaitable (peut attendre la V2)

| # | Fonctionnalité | Description |
|:--|:---|:---|
| 10 | Édition de fichiers à distance | Modifier du code depuis le mobile |
| 11 | Tableau de bord multi-agents | Onglets séparés : Planning / Execution / Review |
| 12 | Mode Offline-First | Room DB locale avec synchronisation au retour du réseau |
| 13 | Notifications push FCM | Alertes système Android quand un agent attend une validation |
| 14 | Changement de modèle à distance | Basculer entre Gemini, Claude, DeepSeek depuis le mobile |

---

## 2. Les 7 Sous-Problèmes Techniques

Le projet se décompose en 7 problèmes indépendants à résoudre séquentiellement :

### SP1 — Découverte du `localharness`
**Entrée :** Un PC avec Antigravity IDE ouvert  
**Sortie :** Le PID du processus, le port ConnectRPC, le token CSRF  
**Méthode :** Inspection des processus système  
**Difficulté :** 🟢 Facile (déjà résolu par la communauté)  
**Risque :** Multi-plateforme (Windows PowerShell vs macOS/Linux `ps aux`)

### SP2 — Authentification ConnectRPC
**Entrée :** Port + Token CSRF  
**Sortie :** Requête HTTP/2 valide acceptée par `localharness`  
**Méthode :** Forger les headers (`Content-Type: application/connect+json`, `X-CSRF-Token`, `Connect-Protocol-Version: 1`)  
**Difficulté :** 🟢 Facile  
**Risque :** Le token change à chaque redémarrage → il faut détecter et ré-extraire automatiquement

### SP3 — Gestion de Sessions (Cascades)
**Entrée :** Un workspace path  
**Sortie :** Un `cascadeId` valide  
**Méthode :** `POST /antigravity.v1.CascadeService/CreateCascade`  
**Difficulté :** 🟡 Moyen  
**Risque :** Les schémas Protobuf exacts ne sont pas documentés — il faut les confirmer par rétro-ingénierie

### SP4 — Streaming de Réponse Agent
**Entrée :** Un prompt envoyé via `SendCascadeMessage`  
**Sortie :** Un flux d'événements (`TEXT_DELTA`, `TOOL_CALL`, `APPROVAL_REQUIRED`, `FINISHED`)  
**Méthode :** SSE / Chunked HTTP avec parsing JSON ou Protobuf  
**Difficulté :** 🟡 Moyen  
**Risque :** Chunks tronqués, fragments incomplets, gestion mémoire

### SP5 — Approbation d'Outils
**Entrée :** Un événement `APPROVAL_REQUIRED` dans le stream  
**Sortie :** Un appel `SubmitToolApproval` avec `DECISION_ALLOW` ou `DECISION_DENY`  
**Méthode :** Requête POST unitaire au même endpoint ConnectRPC  
**Difficulté :** 🟢 Facile (une fois SP2 et SP4 résolus)  
**Risque :** S'assurer que l'agent attend indéfiniment sans timeout côté serveur

### SP6 — Gestion des Workspaces
**Entrée :** Un cascadeId ou un chemin de workspace  
**Sortie :** L'arborescence du projet + le contenu des fichiers  
**Méthode :** Endpoints RPC à identifier (`GetWorkspaceTree`, `GetFileContent`)  
**Difficulté :** 🟡 Moyen  
**Risque :** Ces endpoints existent-ils vraiment ? À confirmer par la cartographie des méthodes RPC

### SP7 — Résilience Réseau
**Entrée :** Coupure réseau (4G ↔ WiFi, mise en veille PC)  
**Sortie :** L'application mobile se resynchronise automatiquement sans doublons  
**Méthode :** Architecture Offline-First (Room DB) + Reconnexion automatique du Daemon  
**Difficulté :** 🔴 Difficile  
**Risque :** Désynchronisation d'état si le PC et le mobile envoient des commandes simultanément

---

## 3. Architecture en 3 Couches

```
┌──────────────────────────────────────────────────────────┐
│                    COUCHE 1 : PC HÔTE                    │
│                                                          │
│  Antigravity IDE ──► localharness (Go, ConnectRPC)       │
│                           │ 127.0.0.1 (loopback)        │
│                           ▼                              │
│                    Daemon Bridge (Go)                     │
│                    - Découverte auto du port + CSRF       │
│                    - Traducteur ConnectRPC → WebSocket    │
│                    - Reconnexion auto si crash IDE        │
└──────────────────────────┬───────────────────────────────┘
                           │ WebSocket + Protobuf
                           │ (LAN direct ou Tunnel Zero Trust)
┌──────────────────────────┴───────────────────────────────┐
│              COUCHE 2 : RÉSEAU DE TRANSPORT              │
│                                                          │
│  Option A : WiFi local (même réseau)                     │
│  Option B : Cloudflare Tunnel / Tailscale (accès global) │
└──────────────────────────┬───────────────────────────────┘
                           │
┌──────────────────────────┴───────────────────────────────┐
│               COUCHE 3 : APK ANDROID NATIF               │
│                                                          │
│  Kotlin + Jetpack Compose                                │
│  - Tableau de bord des sessions                          │
│  - Arborescence du workspace                             │
│  - Visualiseur de diffs de code                          │
│  - Boutons d'approbation (Approuver / Refuser)           │
│  - Room DB (historique hors-ligne)                       │
│  - FCM (notifications push système)                      │
└──────────────────────────────────────────────────────────┘
```

---

## 4. Feuille de Route en Escalier

Chaque marche doit fonctionner à 100% avant de passer à la suivante.

### Phase 1 — Validation du Protocole (CLI sur PC)

| Marche | Objectif | Critère de Succès | Statut |
|:---|:---|:---|:---|
| **0** | Découvrir le `localharness` | Un script affiche le PID, le port et le token CSRF | ✅ Validé |
| **1** | Test unitaire | Un `POST CreateCascade` renvoie un `cascadeId` valide, envoi de prompt et réception | ✅ Validé (`test-1` à `test-3`) |
| **2** | CLI - Gestion des Workspaces | Ajouter un workspace et changer de projet actif | ✅ Validé (`test-7-workspace.ts`) |
| **3** | CLI - Gestion des Modèles | Lister les modèles LLM disponibles, changer le modèle actif | ✅ Validé (`test-6-model.ts`) |
| **4** | CLI - Gestion des Sessions | Lister toutes les sessions (Cascades) actives | ✅ Validé (`test-4-list.ts`) |
| **5** | CLI - Interaction Session | Ouvrir une session existante, envoyer un prompt, récupérer les données | ✅ Validé (`test-5-history.ts`) |
| **6** | CLI - Mode Autonome / Cleanup | Supprimer une session, gérer `ask_user` dynamiquement | ⏳ À faire |

### Phase 2 — Daemon Bridge (Go)

| Marche | Objectif | Critère de Succès |
|:---|:---|:---|
| **5** | Le CLI devient un Daemon | Le Daemon écoute sur un port WebSocket et relaye les sessions |
| **6** | Reconnexion automatique | Si le token CSRF change (redémarrage IDE), le Daemon se ré-authentifie seul |
| **7** | Tunneling réseau | Le Daemon est accessible via Cloudflare Tunnel ou Tailscale |

### Phase 3 — APK Android Natif

| Marche | Objectif | Critère de Succès |
|:---|:---|:---|
| **8** | Connexion au Daemon | L'APK se connecte via WebSocket et affiche la liste des sessions |
| **9** | Envoi de prompt + streaming | L'APK envoie un message et affiche la réponse en temps réel |
| **10** | Approbation tactile | L'APK affiche un bouton Approuver/Refuser quand l'agent bloque |
| **11** | Workspace browser | L'APK affiche l'arborescence du projet et les diffs de code |
| **12** | Notifications FCM | L'APK réveille l'écran quand un agent attend une validation |

---

## 5. Risques Identifiés et Mitigations

| Risque | Impact | Probabilité | Mitigation |
|:---|:---|:---|:---|
| **Breaking changes Google** (renommage des endpoints RPC) | 🔴 Critique | Moyenne | Couche d'abstraction dans le Daemon : un mapping de noms d'endpoints modifiable sans recompiler |
| **Token CSRF qui change** au redémarrage IDE | 🟡 Élevé | Certaine | Watchdog dans le Daemon qui surveille le processus `localharness` et ré-extrait le token automatiquement |
| **Concurrence Desktop + Mobile** (deux sources de commandes simultanées) | 🟡 Élevé | Moyenne | À investiguer : est-ce que `localharness` supporte plusieurs clients ConnectRPC ? Sinon → verrouillage optimiste |
| **Coupure réseau** (4G ↔ WiFi) | 🟡 Moyen | Certaine | Architecture Offline-First avec Room DB + queue de resynchronisation |
| **Parsing de chunks Protobuf tronqués** | 🟡 Moyen | Élevée | Utiliser `application/connect+json` (JSON) plutôt que le binaire pour simplifier le parsing initial |
| **Expiration OAuth Google sur le PC** | 🟠 Moyen | Faible | L'APK ne gère pas l'auth — si la session expire, afficher un message "Reconnectez-vous sur le PC" |

---

## 6. Ce qui est hors périmètre (V1)

- ❌ Exécution de code sur le téléphone (toute l'exécution reste sur le PC)
- ❌ Gestion de l'authentification Google depuis le mobile
- ❌ Support iOS (V1 = Android uniquement, une PWA de fallback pourra être ajoutée en V2)
- ❌ Interface d'édition de code complète (V1 = lecture seule + diffs, pas un éditeur)
- ❌ Déploiement sur le Google Play Store (V1 = APK distribué directement)
