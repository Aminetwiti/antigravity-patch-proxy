# Stack Technique — Antigravity Remote Control OS

> Décisions technologiques, justifications et contraintes. Chaque choix est validé par le terrain (tests réels sur machine), pas par la théorie.

---

## 1. Vue d'ensemble

| Composant | Choix | Justification |
|:---|:---|:---|
| **Daemon Bridge (PC)** | Go 1.22 — binaire unique | Même langage que le `language_server` (Go), stdlib `net/http`, aucun runtime requis, binaire ~10 MB |
| **Client mobile** | Flutter (Dart) / Android & iOS | Base de code multi-plateforme, rendu réactif 120 Hz, composants UI "Quiet Console", persistance locale |
| **Transport PC ↔ Mobile** | WebSocket (JSON v1) | Typage strict, streaming temps réel, bidirectionnel, support natif |
| **Accès réseau distant** | Pinggy SSH / Cloudflare Tunnel | Zero Trust, URL publique sécurisée en 1 seconde sans port ouvert sur le routeur |
| **Sérialisation RPC interne** | ConnectRPC / gRPC-Web natif | Communication directe avec le `language_server` sans intermédiaire |
| **Source de Vérité Protobuf** | **`antigravity-client`** | Référence canonique des 188 RPC methods et schémas Protobuf officiels |

---

## 2. Source de Vérité & Référence Officielle : `antigravity-client`

Le sous-projet **`remote/tools/antigravity-client-main/antigravity-client-main`** constitue la **Source de Vérité canonique (Golden Reference)** pour l'ensemble de notre stack RPC :

1. **Définition intégrale des 188 méthodes RPC** : [`src/gen/exa/language_server_pb/language_server_pb.ts`](file:///C:/Users/amine/Downloads/antigravity-add-model-main/antigravity-add-model-main/remote/tools/antigravity-client-main/antigravity-client-main/src/gen/exa/language_server_pb/language_server_pb.ts).
2. **Schémas Protobuf de sessions et planners** :
   - `src/gen/exa/cortex_pb/` : `StartCascadeRequest`, `CascadeConfig`, `CascadePlannerConfig`.
   - `src/gen/exa/codeium_common_pb/` : `TextOrScopeItem`, `Metadata`, `ModelOrAlias`.
   - `src/gen/exa/jetski_cortex_pb/` : Trajectoires, étapes et résumés.
3. **Parseur d'Événements Delta Typé** :
   - [`src/core/cascade/event-parser.ts`](file:///C:/Users/amine/Downloads/antigravity-add-model-main/antigravity-add-model-main/remote/tools/antigravity-client-main/antigravity-client-main/src/core/cascade/event-parser.ts) : Modèle de référence pour le décodage des 130+ types d'événements de stream.
4. **Harnais de Test Standalone** :
   - Scripts `src/test-*.ts` pour valider chaque fonctionnalité (approbations, switch de modèle, injection de prompt, focus IDE) de façon unitaire en Node.js.

---

## 3. Couche 1 — PC : Daemon Bridge (Go)

### 3.1 Pourquoi Go
- Le moteur cible (`language_server`) est **écrit en Go** → mêmes primitives de goroutines et de sockets.
- **Binaire unique autonome** sans dépendance système externe (~10 MB compilé).
- Performance maximale et empreinte mémoire négligeable (< 25 MB RAM).

### 3.2 Protocole RPC : gRPC-Web natif
- Le serveur attend du **`application/grpc-web+proto`** (pas du Connect JSON).
- Header d'auth obligatoire : **`x-codeium-csrf-token`** (héritage Codeium).
- Framing standard : `1 octet flags + 4 octets longueur Big-Endian + charge Protobuf`.

### 3.3 Découverte automatique du moteur
1. Scanner les processus `language_server*` via WMI / CIM.
2. **Cibler l'instance hub** (`--subclient_type hub`) — les instances IDE retournent 404 sur les routes de session.
3. Résoudre les ports TCP via `netstat -ano`.
4. **Probe Heartbeat** : validation par `POST /exa.language_server_pb.LanguageServerService/Heartbeat` → HTTP 200.

---

## 4. Couche 2 — Transport Réseau & Résilience

### 4.1 Sécurité des Communications
- **Token d'authentification** vérifié en temps constant (`crypto/subtle.ConstantTimeCompare`).
- **Anti-DNS Rebinding** strict dans `checkOrigin` (autorisant uniquement `127.0.0.1`, LAN privé et tunnels certifiés).
- **Confinement Path Traversal** dans `resolvePath` et `saveUploadedImage`.

### 4.2 StepRecovery & Buffer Circulaire
- Buffer circulaire de **100 deltas** en mémoire vive par cascade.
- Synchronisation delta immédiate via `sync_session(lastStepIndex)` lors des reconnexions Wi-Fi / 4G.

---

## 5. Couche 3 — Mobile : Application Flutter

### 5.1 Architecture Applicative
- **Dart / Flutter** pour une expérience multiplateforme unifiée (Android / iOS).
- Rendu réactif 120 Hz, composants tactiles dédiés (`AskQuestionChoiceCard`, `UnifiedDiffViewer`, `ChatInputBar`).
- File d'attente locale (Outbox) garantissant l'envoi dès le retour de la connexion réseau.

---

## 6. Références & Liens Documentaires

- Documentation Protocole : [PROTOCOL.md](file:///C:/Users/amine/Downloads/antigravity-add-model-main/antigravity-add-model-main/remote/PROTOCOL.md)
- Guide d'utilisation : [README.md](file:///C:/Users/amine/Downloads/antigravity-add-model-main/antigravity-add-model-main/remote/README.md)
- Spécifications SDK & Schemas : [antigravity-client](file:///C:/Users/amine/Downloads/antigravity-add-model-main/antigravity-add-model-main/remote/tools/antigravity-client-main/antigravity-client-main/README.md)
