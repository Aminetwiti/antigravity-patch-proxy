# PRD â€” Antigravity Remote Control OS (V1 Ã‰tendue)

## Product Requirements Document

---

## 1. PÃ©rimÃ¨tre de la V1 Ã‰tendue

La V1 couvre les fonctionnalitÃ©s suivantes, classÃ©es par prioritÃ© :

### P0 â€” Critique (sans Ã§a, le produit ne sert Ã  rien)

| # | FonctionnalitÃ© | Endpoint RPC associÃ© | Description |
|:--|:---|:---|:---|
| 1 | DÃ©couverte du `localharness` | â€” (processus systÃ¨me) | Scanner les processus, extraire le port + token CSRF |
| 2 | CrÃ©ation de session | `CreateCascade` | Instancier une Cascade rattachÃ©e Ã  un workspace |
| 3 | Envoi de prompt | `SendCascadeMessage` | Envoyer un message texte Ã  l'agent et recevoir le stream de rÃ©ponse |
| 4 | Approbation d'outils | `SubmitToolApproval` | Valider ou refuser les commandes `run_command` bloquÃ©es par `ask_user` |
| 5 | Liste des sessions | `GetAllCascades` | RÃ©cupÃ©rer toutes les sessions actives pour basculer entre elles |

### P1 â€” Important (V1 Ã©tendue)

| # | FonctionnalitÃ© | Endpoint RPC associÃ© | Description |
|:--|:---|:---|:---|
| 6 | Arborescence du workspace | `GetWorkspaceTree` | Afficher la structure du projet (dossiers, fichiers) |
| 7 | Lecture de fichiers | `GetFileContent` (Ã  confirmer) | Lire le contenu d'un fichier du workspace |
| 8 | Visualisation des diffs | (via les Ã©vÃ©nements du stream) | Afficher les modifications de code apportÃ©es par l'agent |
| 9 | Historique de conversation | `GetCascadeHistory` (Ã  confirmer) | Relire les Ã©changes passÃ©s d'une session |

### P2 â€” Souhaitable (peut attendre la V2)

| # | FonctionnalitÃ© | Description |
|:--|:---|:---|
| 10 | Ã‰dition de fichiers Ã  distance | Modifier du code depuis le mobile |
| 11 | Tableau de bord multi-agents | Onglets sÃ©parÃ©s : Planning / Execution / Review |
| 12 | Mode Offline-First | Room DB locale avec synchronisation au retour du rÃ©seau |
| 13 | Notifications push FCM | Alertes systÃ¨me Android quand un agent attend une validation |
| 14 | Changement de modÃ¨le Ã  distance | Basculer entre Gemini, Claude, DeepSeek depuis le mobile |

---

## 2. Les 7 Sous-ProblÃ¨mes Techniques

Le projet se dÃ©compose en 7 problÃ¨mes indÃ©pendants Ã  rÃ©soudre sÃ©quentiellement :

### SP1 â€” DÃ©couverte du `localharness`
**EntrÃ©e :** Un PC avec Antigravity IDE ouvert  
**Sortie :** Le PID du processus, le port ConnectRPC, le token CSRF  
**MÃ©thode :** Inspection des processus systÃ¨me  
**DifficultÃ© :** ðŸŸ¢ Facile (dÃ©jÃ  rÃ©solu par la communautÃ©)  
**Risque :** Multi-plateforme (Windows PowerShell vs macOS/Linux `ps aux`)

### SP2 â€” Authentification ConnectRPC
**EntrÃ©e :** Port + Token CSRF  
**Sortie :** RequÃªte HTTP/2 valide acceptÃ©e par `localharness`  
**MÃ©thode :** Forger les headers (`Content-Type: application/connect+json`, `X-CSRF-Token`, `Connect-Protocol-Version: 1`)  
**DifficultÃ© :** ðŸŸ¢ Facile  
**Risque :** Le token change Ã  chaque redÃ©marrage â†’ il faut dÃ©tecter et rÃ©-extraire automatiquement

### SP3 â€” Gestion de Sessions (Cascades)
**EntrÃ©e :** Un workspace path  
**Sortie :** Un `cascadeId` valide  
**MÃ©thode :** `POST /antigravity.v1.CascadeService/CreateCascade`  
**DifficultÃ© :** ðŸŸ¡ Moyen  
**Risque :** Les schÃ©mas Protobuf exacts ne sont pas documentÃ©s â€” il faut les confirmer par rÃ©tro-ingÃ©nierie

### SP4 â€” Streaming de RÃ©ponse Agent
**EntrÃ©e :** Un prompt envoyÃ© via `SendCascadeMessage`  
**Sortie :** Un flux d'Ã©vÃ©nements (`TEXT_DELTA`, `TOOL_CALL`, `APPROVAL_REQUIRED`, `FINISHED`)  
**MÃ©thode :** SSE / Chunked HTTP avec parsing JSON ou Protobuf  
**DifficultÃ© :** ðŸŸ¡ Moyen  
**Risque :** Chunks tronquÃ©s, fragments incomplets, gestion mÃ©moire

### SP5 â€” Approbation d'Outils
**EntrÃ©e :** Un Ã©vÃ©nement `APPROVAL_REQUIRED` dans le stream  
**Sortie :** Un appel `SubmitToolApproval` avec `DECISION_ALLOW` ou `DECISION_DENY`  
**MÃ©thode :** RequÃªte POST unitaire au mÃªme endpoint ConnectRPC  
**DifficultÃ© :** ðŸŸ¢ Facile (une fois SP2 et SP4 rÃ©solus)  
**Risque :** S'assurer que l'agent attend indÃ©finiment sans timeout cÃ´tÃ© serveur

### SP6 â€” Gestion des Workspaces
**EntrÃ©e :** Un cascadeId ou un chemin de workspace  
**Sortie :** L'arborescence du projet + le contenu des fichiers  
**MÃ©thode :** Endpoints RPC Ã  identifier (`GetWorkspaceTree`, `GetFileContent`)  
**DifficultÃ© :** ðŸŸ¡ Moyen  
**Risque :** Ces endpoints existent-ils vraiment ? Ã€ confirmer par la cartographie des mÃ©thodes RPC

### SP7 â€” RÃ©silience RÃ©seau
**EntrÃ©e :** Coupure rÃ©seau (4G â†” WiFi, mise en veille PC)  
**Sortie :** L'application mobile se resynchronise automatiquement sans doublons  
**MÃ©thode :** Architecture Offline-First (Room DB) + Reconnexion automatique du Daemon  
**DifficultÃ© :** ðŸ”´ Difficile  
**Risque :** DÃ©synchronisation d'Ã©tat si le PC et le mobile envoient des commandes simultanÃ©ment

---

## 3. Architecture en 3 Couches

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚                    COUCHE 1 : PC HÃ”TE                    â”‚
â”‚                                                          â”‚
â”‚  Antigravity IDE â”€â”€â–º localharness (Go, ConnectRPC)       â”‚
â”‚                           â”‚ 127.0.0.1 (loopback)        â”‚
â”‚                           â–¼                              â”‚
â”‚                    Daemon Bridge (Go)                     â”‚
â”‚                    - DÃ©couverte auto du port + CSRF       â”‚
â”‚                    - Traducteur ConnectRPC â†’ WebSocket    â”‚
â”‚                    - Reconnexion auto si crash IDE        â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                           â”‚ WebSocket + Protobuf
                           â”‚ (LAN direct ou Tunnel Zero Trust)
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”´â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚              COUCHE 2 : RÃ‰SEAU DE TRANSPORT              â”‚
â”‚                                                          â”‚
â”‚  Option A : WiFi local (mÃªme rÃ©seau)                     â”‚
â”‚  Option B : Cloudflare Tunnel / Tailscale (accÃ¨s global) â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                           â”‚
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”´â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚               COUCHE 3 : APK ANDROID NATIF               â”‚
â”‚                                                          â”‚
â”‚  Kotlin + Jetpack Compose                                â”‚
â”‚  - Tableau de bord des sessions                          â”‚
â”‚  - Arborescence du workspace                             â”‚
â”‚  - Visualiseur de diffs de code                          â”‚
â”‚  - Boutons d'approbation (Approuver / Refuser)           â”‚
â”‚  - Room DB (historique hors-ligne)                       â”‚
â”‚  - FCM (notifications push systÃ¨me)                      â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

---

## 4. Feuille de Route en Escalier

Chaque marche doit fonctionner Ã  100% avant de passer Ã  la suivante.

### Phase 1 â€” Validation du Protocole (CLI sur PC)

| Marche | Objectif | CritÃ¨re de SuccÃ¨s | Statut |
|:---|:---|:---|:---|
| **0** | DÃ©couvrir le `localharness` | Un script affiche le PID, le port et le token CSRF | âœ… ValidÃ© |
| **1** | Test unitaire | Un `POST CreateCascade` renvoie un `cascadeId` valide, envoi de prompt et rÃ©ception | âœ… ValidÃ© (`test-1` Ã  `test-3`) |
| **2** | CLI - Gestion des Workspaces | Ajouter un workspace et changer de projet actif | âœ… ValidÃ© (`test-7-workspace.ts`) |
| **3** | CLI - Gestion des ModÃ¨les | Lister les modÃ¨les LLM disponibles, changer le modÃ¨le actif | âœ… ValidÃ© (`test-6-model.ts`) |
| **4** | CLI - Gestion des Sessions | Lister toutes les sessions (Cascades) actives | âœ… ValidÃ© (`test-4-list.ts`) |
| **5** | CLI - Interaction Session | Ouvrir une session existante, envoyer un prompt, rÃ©cupÃ©rer les donnÃ©es | âœ… ValidÃ© (`test-5-history.ts` et `test-marche.ts`) |
| **6** | CLI - Actions AvancÃ©es | Appels d'outils, Focus (SmartFocusConversation), GetSidecars | âœ… ValidÃ© (`test-8` Ã  `test-17`) |

### Phase 1.5 â€” IntÃ©gration UI (Doctor UI)

| Marche | Objectif | CritÃ¨re de SuccÃ¨s | Statut |
|:---|:---|:---|:---|
| **7** | Onglet Remote App | Ajouter une vue "Remote Server" dans l'UI d'Antigravity Doctor | âœ… ValidÃ© |
| **8** | GÃ©nÃ©ration de QR Code | Le Main process gÃ©nÃ¨re un QR code avec l'adresse IP locale et le port (`8090`) | âœ… ValidÃ© |

### Phase 2 â€” Daemon Bridge (Go)

| Marche | Objectif | CritÃ¨re de SuccÃ¨s |
|:---|:---|:---|
| **9** | Le CLI devient un Daemon | Le Daemon Go Ã©coute sur le port `:8090` WebSocket et relaye vers ConnectRPC |
| **10** | Reconnexion automatique | Si le token CSRF change, le Daemon se rÃ©-authentifie seul |
| **11** | Tunneling rÃ©seau | Le Daemon est accessible via Cloudflare Tunnel ou Tailscale |

### Phase 3 â€” APK Android Natif

| Marche | Objectif | CritÃ¨re de SuccÃ¨s |
|:---|:---|:---|
| **12** | Connexion au Daemon | L'APK scanne le QR code, se connecte via WebSocket et affiche les sessions |
| **13** | Envoi de prompt + streaming | L'APK envoie un message et affiche la rÃ©ponse en temps rÃ©el |
| **14** | Approbation tactile | L'APK affiche un bouton Approuver/Refuser quand l'agent bloque |
| **15** | Workspace browser | L'APK affiche l'arborescence du projet et les diffs de code |
| **16** | Notifications FCM | L'APK rÃ©veille l'Ã©cran quand un agent attend une validation |

---

## 5. Risques IdentifiÃ©s et Mitigations

| Risque | Impact | ProbabilitÃ© | Mitigation |
|:---|:---|:---|:---|
| **Breaking changes Google** (renommage des endpoints RPC) | ðŸ”´ Critique | Moyenne | Couche d'abstraction dans le Daemon : un mapping de noms d'endpoints modifiable sans recompiler |
| **Token CSRF qui change** au redÃ©marrage IDE | ðŸŸ¡ Ã‰levÃ© | Certaine | Watchdog dans le Daemon qui surveille le processus `localharness` et rÃ©-extrait le token automatiquement |
| **Concurrence Desktop + Mobile** (deux sources de commandes simultanÃ©es) | ðŸŸ¡ Ã‰levÃ© | Moyenne | Ã€ investiguer : est-ce que `localharness` supporte plusieurs clients ConnectRPC ? Sinon â†’ verrouillage optimiste |
| **Coupure rÃ©seau** (4G â†” WiFi) | ðŸŸ¡ Moyen | Certaine | Architecture Offline-First avec Room DB + queue de resynchronisation |
| **Parsing de chunks Protobuf tronquÃ©s** | ðŸŸ¡ Moyen | Ã‰levÃ©e | Utiliser `application/connect+json` (JSON) plutÃ´t que le binaire pour simplifier le parsing initial |
| **Expiration OAuth Google sur le PC** | ðŸŸ  Moyen | Faible | L'APK ne gÃ¨re pas l'auth â€” si la session expire, afficher un message "Reconnectez-vous sur le PC" |

---

## 6. Ce qui est hors pÃ©rimÃ¨tre (V1)

- âŒ ExÃ©cution de code sur le tÃ©lÃ©phone (toute l'exÃ©cution reste sur le PC)
- âŒ Gestion de l'authentification Google depuis le mobile
- âŒ Support iOS (V1 = Android uniquement, une PWA de fallback pourra Ãªtre ajoutÃ©e en V2)
- âŒ Interface d'Ã©dition de code complÃ¨te (V1 = lecture seule + diffs, pas un Ã©diteur)
- âŒ DÃ©ploiement sur le Google Play Store (V1 = APK distribuÃ© directement)

