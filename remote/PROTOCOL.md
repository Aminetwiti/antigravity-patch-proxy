# Protocole ConnectRPC/gRPC-Web Validé — LanguageServerService

> Document de référence infrastructure. Basé sur les tests réels dans `remote/scratch/` (test_grpcweb.ps1, test_cascade_list.ps1, test_send_message.ps1) et l'analyse des processus (`remote/localharness.md`).

## 1. Binaire réel

Le "cerveau" d'Antigravity est **`language_server`** (et non `localharness`) :

- `language_server_windows_x64.exe` — instances liées à un workspace IDE (`--subclient_type ide`)
- `language_server.exe` — instance standalone hub (`--subclient_type hub`, patchée par le proxy : `--api_server_url http://localhost:50999`)

## 2. Arguments critiques (extraits de la command line)

| Argument | Rôle | Exemple réel |
|:---|:---|:---|
| `--csrf_token` | Auth cloud (hub) / auth locale | `dca42d6a-3d87-4a6b-a620-dde9bc7ce40e` |
| `--extension_server_csrf_token` | Auth locale des instances IDE | `61edfa3c-af9d-457c-96af-bb466dcb4eab` |
| `--extension_server_port` | Port de BASE — le serveur écoute sur `base` et `base+1` | `55256` → actifs `55256`/`55257` |
| `--workspace_id` | Projet lié (instances IDE) | `file_c_3A_Users_amine_...` |
| `--subclient_type` | `ide` ou `hub` | `ide` |

## 3. Découverte des ports (observé sur cette machine)

| PID | Base | Ports actifs | Type |
|:---|:---|:---|:---|
| 35280 | 55256 | 55256, 55257, 55262, 55263 | IDE |
| 34320 | 55342 | 55342 | IDE (workspace raouf_taxi) |
| 36464 | 53336 | 53336 | IDE |
| 37136 | (hub) | 60656, 60657 | Hub standalone |

**Règle de découverte :** scanner `base..base+1` (HTTP + HTTPS local), les deux répondent.

## 4. Protocole HTTP réel (gRPC-Web, PAS Connect JSON)

### Endpoint

```
POST http://127.0.0.1:<port>/exa.language_server_pb.LanguageServerService/<Method>
```

### Méthodes confirmées

| Méthode | Corps | Notes |
|:---|:---|:---|
| `StartCascade` | StartCascadeRequest (protobuf) | Crée une session |
| `GetAllCascadeTrajectories` | vide | Liste toutes les sessions |
| `SendUserCascadeMessage` | SendUserCascadeMessageRequest | Envoie un message → stream |
| `Heartbeat` | vide | Ping |
| `GetStatus` | vide | État du serveur |

### Headers obligatoires

```
Content-Type: application/grpc-web+proto
Accept: application/grpc-web+proto,application/grpc-web-text
x-codeium-csrf-token: <csrf_token ou extension_server_csrf_token>
Connect-Protocol-Version: 1
X-Grpc-Web: 1
```

> ⚠️ Le header CSRF s'appelle **`x-codeium-csrf-token`** (héritage Codeium), pas `X-CSRF-Token`.

### Framing gRPC-Web

Chaque message est encadré : `1 octet flags (0) + 4 octets longueur BE + payload protobuf`.

## 5. Schémas protobuf rétro-ingéniérés (champs validés)

### StartCascadeRequest

| # | Champ | Type | Valeur connue |
|:---|:---|:---|:---|
| 4 | `source` | varint enum | 1 = `CORTEX_TRAJECTORY_SOURCE_CASCADE_CLIENT` |
| 5 | `trajectory_type` | varint enum | 1 = `CORTEX_TRAJECTORY_TYPE_USER_MAINLINE` |
| 8 | `workspace_uris` | repeated string | `file:///C:/path/workspace` |
| 14 | `requested_model` | varint enum | 190 = `CASCADE_BASE_MODEL_ID` |

### SendUserCascadeMessageRequest

| # | Champ | Type |
|:---|:---|:---|
| 1 | `cascade_id` | string (UUID) |
| 2 | `items` | repeated TextOrScopeItem |

### TextOrScopeItem

| # | Champ | Type |
|:---|:---|:---|
| 1 | `chunk.text` | string |

## 6. Fichiers d'infrastructure liés

- Client TypeScript : `remote/cli/src/protobuf.ts`, `remote/cli/src/grpcweb.ts`, `remote/cli/src/client.ts`
- Client Go : `remote/daemon/pkg/connectrpc/client.go`
- Schémas : `remote/proto/remote_service.proto`
- Tests de validation réels : `remote/scratch/test_grpcweb.ps1`, `test_cascade_list.ps1`, `test_send_message.ps1`
