# Instructions — Validation du Protocole ConnectRPC (Phase 1)

> **Règle absolue :** Ne rien coder pour Android ou pour le Daemon tant que ces étapes ne sont pas validées à 100%.

---

## Marche 0 : Découvrir le Processus `localharness`

### Objectif
Confirmer que le binaire Go `localharness` tourne sur votre PC et récupérer ses paramètres critiques.

### Prérequis
- Antigravity IDE (ou Antigravity 2.0 Desktop) doit être **ouvert et actif** avec au moins un workspace chargé.

### Procédure sur Windows (PowerShell)

**Étape 1 — Trouver le processus :**
```powershell
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*language_server*' -or $_.CommandLine -like '*localharness*' } | Select-Object ProcessId, CommandLine | Format-List
```

**Étape 2 — Extraire le token CSRF :**
Dans la sortie `CommandLine`, chercher l'argument qui contient `--csrf_token=` ou `--api_key=`. Copier la valeur.

**Étape 3 — Extraire le port d'extension :**
Chercher l'argument `--extensionPort=XXXXX`. Ce port est le port de BASE — le serveur ConnectRPC écoute sur un port dans la plage `extensionPort+1` à `extensionPort+20`.

**Étape 4 — Trouver le port ConnectRPC actif :**
```powershell
# Remplacer 45000 par votre extensionPort
$basePort = 45000
$basePort..($basePort+20) | ForEach-Object {
    $result = Test-NetConnection -ComputerName 127.0.0.1 -Port $_ -WarningAction SilentlyContinue
    if ($result.TcpTestSucceeded) { Write-Host "Port actif: $_" }
}
```

### Résultat Attendu

Vous devez avoir 3 informations :
1. **PID** du processus `localharness`
2. **Token CSRF** (chaîne de caractères longue)
3. **Port ConnectRPC actif** (dans la plage extensionPort+1 à +20)

> [!WARNING]
> Si aucun processus n'est trouvé, vérifiez qu'Antigravity IDE est bien ouvert. Si le processus existe mais sans `--csrf_token`, il est possible que la version d'Antigravity ait changé les noms des arguments.

---

## Marche 1 : Test `curl` — CreateCascade

### Objectif
Prouver que le `localharness` accepte une requête ConnectRPC externe et crée une session.

### Prérequis
- Marche 0 validée (vous avez le port et le token CSRF)
- `curl` installé (Windows 10+ l'a nativement, ou utiliser Git Bash)

### Commande exacte

```bash
curl --http2-prior-knowledge \
  -X POST "http://127.0.0.1:<PORT_TROUVÉ>/antigravity.v1.CascadeService/CreateCascade" \
  -H "Content-Type: application/connect+json" \
  -H "X-CSRF-Token: <VOTRE_TOKEN_CSRF>" \
  -H "Connect-Protocol-Version: 1" \
  -d '{"workspacePath": "C:\\Users\\amine\\Downloads\\antigravity-add-model-main\\antigravity-add-model-main"}'
```

> **Note Windows :** Si vous utilisez PowerShell (pas Git Bash), remplacez les `\` de continuation par des backticks `` ` `` et échappez les guillemets dans le JSON.

### Résultat Attendu — Succès ✅

```json
{
  "cascadeId": "cas_XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX",
  "createdAt": "2026-08-11T...",
  "status": "CASCADE_STATUS_READY"
}
```

### Résultats Possibles — Échec ❌

| Erreur | Cause Probable | Action |
|:---|:---|:---|
| `Connection refused` | Mauvais port — refaire le scan de ports | Relancer la Marche 0, étape 4 |
| `403 Forbidden` | Token CSRF invalide ou expiré | Ré-extraire le token (le `localharness` a peut-être redémarré) |
| `404 Not Found` | L'endpoint n'existe plus (breaking change Google) | Extraire les méthodes du binaire : `strings localharness \| grep "antigravity.v1."` |
| `415 Unsupported Media Type` | Mauvais Content-Type | Vérifier que le header est exactement `application/connect+json` |
| Réponse binaire illisible | Le serveur répond en Protobuf binaire | Ajouter le header `Accept: application/json` ou retenter avec `Content-Type: application/proto` |

---

## Marche 2 : Test `curl` — SendCascadeMessage (Streaming)

### Objectif
Envoyer un prompt à l'agent et recevoir sa réponse en streaming (token par token).

### Prérequis
- Marche 1 validée (vous avez un `cascadeId` valide)

### Commande exacte

```bash
curl --http2-prior-knowledge \
  -X POST "http://127.0.0.1:<PORT>/antigravity.v1.CascadeService/SendCascadeMessage" \
  -H "Content-Type: application/connect+json" \
  -H "X-CSRF-Token: <TOKEN>" \
  -H "Connect-Protocol-Version: 1" \
  -d '{
    "cascadeId": "<VOTRE_CASCADE_ID>",
    "message": {
      "role": "ROLE_USER",
      "parts": [{"text": "Dis bonjour en une ligne"}]
    }
  }' \
  --no-buffer
```

> Le flag `--no-buffer` est essentiel pour voir le streaming en temps réel.

### Résultat Attendu

Un flux de lignes JSON successives dans le terminal :

```json
{"type": "EVENT_TYPE_TEXT_DELTA", "textDelta": "Bonjour"}
{"type": "EVENT_TYPE_TEXT_DELTA", "textDelta": " ! Comment"}
{"type": "EVENT_TYPE_TEXT_DELTA", "textDelta": " puis-je vous aider ?"}
{"type": "EVENT_TYPE_FINISHED"}
```

### Ce qu'il faut observer

- **Les deltas de texte arrivent-ils un par un ?** Si oui, le streaming fonctionne.
- **Le format est-il du JSON lisible ou du Protobuf binaire ?** Si binaire, il faudra ajuster les headers ou utiliser le mode JSON.
- **Y a-t-il des événements `TOOL_CALL` ?** Si le prompt déclenche un outil, vous verrez un `EVENT_TYPE_TOOL_CALL` suivi d'un `EVENT_TYPE_APPROVAL_REQUIRED` (si la politique est `ask_user`).

---

## Marche 3 : Test `curl` — SubmitToolApproval

### Objectif
Prouver qu'on peut approuver une commande d'outil bloquée depuis un appel RPC externe.

### Prérequis
- Marche 2 validée
- Un prompt qui déclenche un appel d'outil (ex: "Liste les fichiers du dossier courant")

### Comment déclencher un `ask_user`

Envoyez un prompt qui forcera l'agent à exécuter une commande terminal :
```
"Exécute la commande 'ls -la' dans le terminal"
```

Si Antigravity est en mode `ask_user`, le stream s'arrêtera avec :
```json
{
  "type": "EVENT_TYPE_APPROVAL_REQUIRED",
  "toolCall": {
    "callId": "call_XXXXX",
    "toolName": "run_command",
    "args": {"command": "ls -la"}
  }
}
```

### Commande d'approbation

```bash
curl --http2-prior-knowledge \
  -X POST "http://127.0.0.1:<PORT>/antigravity.v1.CascadeService/SubmitToolApproval" \
  -H "Content-Type: application/connect+json" \
  -H "X-CSRF-Token: <TOKEN>" \
  -H "Connect-Protocol-Version: 1" \
  -d '{
    "cascadeId": "<CASCADE_ID>",
    "callId": "<CALL_ID_DU_TOOL>",
    "decision": "DECISION_ALLOW"
  }'
```

### Résultat Attendu

Après l'envoi de l'approbation :
1. Le stream de la Marche 2 reprend avec les résultats de la commande
2. L'agent continue son exécution normalement
3. Le tout se termine par un `EVENT_TYPE_FINISHED`

---

## Marche 4 : Cartographier les Endpoints RPC

### Objectif
Obtenir la liste complète de toutes les méthodes RPC disponibles dans votre version du `localharness`.

### Méthode 1 — Extraire les chaînes du binaire

```bash
# Trouver le chemin du binaire localharness
# Windows : chercher dans %LOCALAPPDATA%\AntigravityAI\
# ou utiliser le chemin visible dans la CommandLine de la Marche 0

strings <chemin_vers_localharness> | grep "antigravity.v1." | sort -u
```

### Méthode 2 — Extraire les schémas de l'app Electron

```bash
# Trouver le app.asar de l'IDE Antigravity
npx asar extract <chemin>/resources/app.asar ./extracted

# Chercher les définitions de services
grep -r "CascadeService\|WorkspaceService\|createPromiseClient" ./extracted/ --include="*.js"
```

### Endpoints attendus (basé sur la rétro-ingénierie communautaire)

Les endpoints **confirmés** par le code source d'OmniAntigravity :
- `/antigravity.v1.CascadeService/CreateCascade`
- `/antigravity.v1.CascadeService/SendCascadeMessage`
- `/antigravity.v1.CascadeService/GetAllCascades`
- `/antigravity.v1.CascadeService/SubmitToolApproval`

Les endpoints **probables** (à vérifier sur votre version) :
- `/antigravity.v1.CascadeService/GetCascade` (historique d'une session)
- `/antigravity.v1.CascadeService/DeleteCascade` (supprimer une session)
- `/antigravity.v1.WorkspaceService/GetWorkspaceTree` (arborescence)
- `/antigravity.v1.WorkspaceService/GetFileContent` (lire un fichier)
- `/antigravity.v1.ModelService/GetAvailableModels` (liste des modèles)

---

## Checklist de Validation — Phase 1

| # | Marche | Statut | Date |
|:--|:---|:---:|:---|
| 0 | Processus `localharness` découvert (PID + Port + CSRF Token) | ✅ | Validé |
| 1 | `curl CreateCascade` → reçoit un `cascadeId` | ✅ | Validé (via `test-1`) |
| 2 | `curl SendCascadeMessage` → reçoit un stream de `TEXT_DELTA` | ✅ | Validé (via `test-2`) |
| 3 | `curl SubmitToolApproval` → l'agent reprend après validation | ⬜ | En attente |
| 4 | Cartographie des endpoints RPC de votre version | ✅ | Validé |

> [!IMPORTANT]
> **Ne passez à la Phase 2 (Daemon Go) qu'une fois les 5 cases cochées.**
> Si la Marche 1 échoue, c'est que les endpoints ont changé — il faut d'abord refaire de la rétro-ingénierie (Marche 4) avant de retenter.
