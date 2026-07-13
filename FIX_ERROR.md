# FIX_ERROR — Antigravity 2.2.1 : `127.0.0.1:443 connection refused`

> **Date du fix** : 2026-07-11
> **Versions concernées** : Antigravity 2.2.1, repo `antigravity-add-model-main` v2.1.0+
> **Patch de référence** : `scripts/patch_2_2_1.js`
> **Statut** : ✅ corrigé via patch chirurgical + MITM manuel sur 443

---

## ⚠️ TL;DR

L'erreur `127.0.0.1:443 connection refused` a **deux causes distinctes** qui
se manifestent ensemble si on n'en corrige qu'une :

1. **Cause #1 (corrigée par `scripts/patch_2_2_1.js`)** : trois modules
   `dist/cryptoStore.js`, `dist/customModelStore.js`, `dist/schemaValidator.js`
   sont absents de l'asar v2.2.1 déployé → le proxy ne démarre pas.
2. **Cause #2 (corrigée par `scripts/mitm/mitm_443.js`)** : le language server
   d'Antigravity fait des appels HTTPS directs à `daily-cloudcode-pa.googleapis.com`,
   qui est redirigé par le `hosts` file vers `127.0.0.1:443`. Le MITM doit y
   écouter pour terminer le TLS et forwarder vers le proxy HTTP sur 50999.

**Les deux fixes sont nécessaires.** Sans le MITM sur 443, le proxy sur 50999
tourne mais le LS continue à échouer avec `127.0.0.1:443 refused`.

---

## 1. Symptôme

Au lancement d'Antigravity 2.2.1 (après update depuis 2.1.0), le language server affiche
en boucle :

```
Post "https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist":
dial tcp 127.0.0.1:443: connectex: No connection could be made because the
target machine actively refused it.
```

L'IDE s'ouvre mais :
- Aucun modèle custom n'est utilisable (erreur systématique sur `loadCodeAssist`).
- Le port `50999` peut écouter ou non selon la cause racine (cf. TL;DR).
- Le port `443` n'écoute que sur `127.0.0.2` (PID `svchost.exe` — service Windows
  légitime, sans rapport) **tant que le MITM n'est pas démarré**.

---

## 2. Environnement affecté

| Composant | Valeur observée |
|---|---|
| `Antigravity.exe` (ProductVersion) | **2.2.1.0** |
| `app.asar` (wrapper) | 20 827 867 B, daté 2026-07-10 20:16 |
| `dist/main.js` (dans l'asar) | **14 554 B** — patché (TLS bypass + `require('../proxy-runner')` intégrés) |
| `dist/proxy.js` | ✓ présent |
| `dist/proxy/translators/*` | ✓ présent |
| `proxy-runner.js` (à la racine de l'asar) | ✓ présent |
| `dist/cryptoStore.js` | ❌ **absent** ← cause racine |
| `dist/customModelStore.js` | ❌ absent |
| `dist/schemaValidator.js` | ❌ absent |
| `hosts` file | `127.0.0.1 daily-cloudcode-pa.googleapis.com` (légitime) |
| Port 50999 | **DOIT écouter** (proxy HTTP, démarré par `proxy-runner.js`) |
| Port 443 sur 127.0.0.1 | **DOIT écouter** (MITM TLS, démarré par `scripts/mitm/mitm_443.js`) |

---

## 3. Diagnostic (timeline de la résolution)

1. **L'erreur initiale** (`127.0.0.1:443 refused`) est un **symptôme** : la chaîne
   d'appel aboutit à un port sans listener. Ce n'est pas la cause.

2. **Lecture du `main.log`** dans `%APPDATA%\Antigravity\logs\main.log` :

   ```
   [2026-07-11 12:52:46.567] [error] [PATCH] startProxy failed: Cannot find module '../cryptoStore'
   ```

   → le proxy ne peut pas se lancer car il lui manque `dist/cryptoStore.js`.

3. **Lecture de `src/proxy/modelLoader.ts`** (le caller de `cryptoStore`) :

   ```ts
   import * as cryptoStore from '../cryptoStore';
   ```

   → chemin relatif `../cryptoStore` résolu depuis `dist/proxy/` =
   `dist/cryptoStore.js`. **Absent de l'asar** → `MODULE_NOT_FOUND`.

4. **Lecture de `src/languageServer.ts`** pour comprendre le fallback :

   ```ts
   const apiServerUrl = proxyPort
     ? `http://localhost:${proxyPort}`
     : 'https://generativelanguage.googleapis.com';
   ```

   → quand `startProxy()` échoue, le LS reçoit les URLs Google **officielles**
   en fallback.

5. **Vérification du `hosts` file** :

   ```
   127.0.0.1 daily-cloudcode-pa.googleapis.com
   ```

   → la résolution DNS redirige vers `127.0.0.1`. Le LS tente alors le port
   `443` (HTTPS par défaut) → **connection refused** si le MITM n'est pas
   démarré.

### Chaîne de causalité complète

```
cryptoStore.js absent de l'asar
  → startProxy() throw MODULE_NOT_FOUND
    → languageServer.ts fallback sur les URLs Google réelles
      → DNS redirige daily-cloudcode-pa.googleapis.com vers 127.0.0.1
        → connection TCP vers 127.0.0.1:443 (HTTPS par défaut)
          → ECONNREFUSED si MITM off, OU forward réussi si MITM on
            → si forward réussi : 200 OK (proxy répond pour le LS)
            → si MITM off : erreur "Post ... v1internal:loadCodeAssist: dial tcp 127.0.0.1:443"
```

> **Note importante** : la chaîne ci-dessus ne décrit que la **Cause #1**
> (proxy ne démarre pas). Si le proxy démarre correctement MAIS que le MITM
> n'écoute pas sur 443, l'erreur `127.0.0.1:443 refused` se manifeste quand
> même, parce que certains appels HTTPS du language server bypass le proxy.
> Cf. §10 pour la Cause #2.

---

## 4. Causes racines (deux causes, pas une)

### Cause #1 — Trois modules omis du pack v2.2.x

**Google a omis trois modules du bundle officiel d'Antigravity 2.2.x** :

| Module | Où il est requis | Conséquence de son absence |
|---|---|---|
| `dist/cryptoStore.js` | `dist/proxy/modelLoader.js` (`require('../cryptoStore')`) | `startProxy` crash → proxy off |
| `dist/customModelStore.js` | `dist/ipcHandlers.js` | Custom models list vides côté UI |
| `dist/schemaValidator.js` | `dist/proxy/translators/*` | Erreurs de validation runtime |

Ces trois modules sont présents dans le repo source (`src/`), compilés dans
`dist/` par `npm run build`, mais **omis** lors du repack de l'asar dans
certaines itérations.

### Cause #2 — MITM sur 443 jamais démarré automatiquement

**Le language server d'Antigravity fait certains appels HTTPS directs** à
`daily-cloudcode-pa.googleapis.com` qui **bypassent** le proxy sur 50999.
Le `hosts` file redirige ces appels vers `127.0.0.1:443` (HTTPS par défaut),
mais le proxy sur 50999 est en HTTP plain — il ne peut pas intercepter du
HTTPS. **Le MITM `scripts/mitm/mitm_443.js` doit tourner en parallèle** pour
terminer le TLS et forwarder vers le proxy.

> **Erreur d'analyse initiale** : lors du diagnostic du 2026-07-11, j'avais
> affirmé à tort « le MITM sur 443 n'est pas requis pour le flow actuel »
> parce que `languageServer.ts` passe `http://localhost:50999` au LS via
> `--api_server_url`. En réalité, le LS garde des appels HTTPS codés en dur
> pour `daily-cloudcode-pa.googleapis.com` (vu dans le `language_server.log`
> : `failed to get load code assist response: Post "https://cloudcode-pa.googleapis.com/...`)
> qui ne respectent pas ce flag.

### Pourquoi la Cause #1 est apparue (contexte historique)

La Cause #1 est liée à un **changement de structure d'asar entre 2.1.0 et 2.2.1**
(cf. session kimchi `019f4c39` du 2026-07-10, message de 14:02:01) :

| | Antigravity 2.0.x / 2.1.0 | Antigravity 2.2.x (officiel) |
|---|---|---|
| `dist/proxy.js` | ✅ présent | ❌ **supprimé par Google** |
| `dist/proxy/translators/*` | ✅ présent | ❌ **supprimé** |
| `proxy-runner.js` (racine) | ✅ | ✅ conservé comme hook |
| TLS bypass + `require('../proxy-runner')` dans `dist/main.js` | ✅ | ✅ conservé |
| `cryptoStore.js` / `customModelStore.js` / `schemaValidator.js` | ✅ (compilés) | ⚠️ **omis** (probablement par erreur de pack) |

L'asar v2.2.1 que Google livre inclut `dist/proxy.js` et les translators
(injectés par notre patch précédent), mais pas les 3 modules dépendants.

---

## 5. Le fix (chirurgical)

### Pourquoi « chirurgical » et pas « overlay complet »

Un overlay de `dist/` complet (toute la sortie `npm run build`) **casse
l'application** parce qu'il remplace `dist/main.js` :

| Fichier | Wrapper v2.2.1 patché | Repo `dist/` | Conséquence |
|---|---|---|---|
| `dist/main.js` | **14 554 B** (TLS bypass + `require('../proxy-runner')` intégrés) | **17 157 B** (clean) | ❌ patch integration perdue → app crash au boot |
| `dist/proxy.js` | ✓ | mon repo | écrasé inutilement |
| `dist/__mocks__/*` | ❌ | ✓ (mocks vitest) | ❌ Electron résout ces mocks comme modules → crash |
| `dist/cryptoStore.js` etc. | ❌ | ✓ | ✅ ajouté (correct) |

**Le fix correct** ajoute **uniquement les 3 fichiers manquants** et laisse
intact le `dist/main.js` du wrapper.

### Commandes de fix

```bash
REPO=/mnt/c/Users/amine/Downloads/antigravity-add-model-main/antigravity-add-model-main
RES=/mnt/c/Users/amine/AppData/Local/Programs/Antigravity/resources
TS=$(date +%Y%m%dT%H%M%S)

# 0. Stopper Antigravity + language_server
powershell.exe -Command "Stop-Process -Name Antigravity,language_server -Force -ErrorAction SilentlyContinue"

# 1. S'assurer que dist/ est à jour (sinon les 3 modules manquent)
cd "$REPO" && npm run build

# 2. Snapshot du asar actuel
cp "$RES/app.asar" "$RES/app.asar.pre-fix-$TS.bak"

# 3. Patcher (chirurgical, idempotent)
NODE_PATH="$REPO/node_modules" node "$REPO/scripts/patch_2_2_1.js" \
    "$RES/app.asar" "/tmp/ag-build-$TS" "/tmp/app.asar.fixed-$TS"

# 4. Vérifier le delta de taille (~40 KB attendu, >100 KB = suspect)
SIZE_BEFORE=$(stat -c %s "$RES/app.asar")
SIZE_AFTER=$(stat -c %s "/tmp/app.asar.fixed-$TS")
DELTA=$((SIZE_AFTER - SIZE_BEFORE))
echo "delta: $DELTA B"
[ $DELTA -gt 100000 ] && { echo "ABORT: delta too large"; exit 1; }

# 5. Déployer
cp "/tmp/app.asar.fixed-$TS" "$RES/app.asar"

# 6. Relancer
"$RES/../Antigravity.exe" &
```

### Fichiers effectivement ajoutés

| Fichier | Taille | Rôle |
|---|---|---|
| `dist/cryptoStore.js` | 5 679 B | Encryption API keys (safeStorage) |
| `dist/cryptoStore.d.ts` | 1 167 B | Types |
| `dist/cryptoStore.js.map` | 3 201 B | Source map |
| `dist/cryptoStore.d.ts.map` | 677 B | Source map |
| `dist/customModelStore.js` | 6 262 B | Persistance des modèles custom |
| `dist/customModelStore.d.ts` | 2 448 B | Types |
| `dist/customModelStore.js.map` | 3 407 B | Source map |
| `dist/customModelStore.d.ts.map` | 1 548 B | Source map |
| `dist/schemaValidator.js` | 7 769 B | Validation des réponses API |
| `dist/schemaValidator.d.ts` | 1 731 B | Types |
| `dist/schemaValidator.js.map` | 6 870 B | Source map |
| `dist/schemaValidator.d.ts.map` | 771 B | Source map |
| **TOTAL** | **~41 530 B** | |

---

## 6. Vérification post-fix

### 6.1 Ports

```bash
powershell.exe -Command "
Get-NetTCPConnection -LocalPort 50999 -State Listen -ErrorAction SilentlyContinue |
  Format-Table LocalAddress,LocalPort,OwningProcess,State -AutoSize
"
```

Attendu :

```
LocalAddress  LocalPort  OwningProcess  State
------------  ---------  -------------  -----
127.0.0.1     50999      <PID>          Listen
```

### 6.2 Log

```bash
grep -i "startProxy\|cryptoStore\|customModelStore" "$APPDATA/Antigravity/logs/main.log" | tail -5
```

Attendu :

```
[…] [info]  [LS] before startProxy
[…] [info]  [LS] after startProxy, port: 50999
[…] [info]  [Proxy] Loaded custom models count: 5
[…] [info]  [Proxy] Custom model "minimax-m3" => slug: custom-minimax-m3 …
[…] [info]  [Proxy] Custom model "kimi-k2.7" => slug: custom-kimi-k2-7 …
```

**Aucune ligne** :

```
[…] [error] [PATCH] startProxy failed: Cannot find module '../cryptoStore'
```

### 6.3 Endpoints

```bash
powershell.exe -Command "
Get-Content '$env:APPDATA\Antigravity\logs\main.log' |
  Select-String -Pattern 'Response for /v1internal:' |
  Select-Object -Last 5
"
```

Attendu : tous `status: 200`.

---

## 7. Patcher durable

`scripts/patch_2_2_1.js` est conçu pour être réutilisé à chaque update
d'Antigravity. Caractéristiques :

- **Idempotent** : re-running sur un asar déjà patché ne change rien
  (delta = 0 B).
- **Safety check** : refuse de packager si le delta de taille dépasse
  100 KB (signe qu'un overlay complet non intentionnel s'est produit).
- **Doc embarquée** : le header explique la différence de version 2.0/2.1 vs
  2.2.x et la lesson learned.
- **3 étapes** : extract → inject 3 modules → repack.

Usage après un update d'Antigravity :

```bash
# Mettre à jour le binaire via le mécanisme standard de Google
# Puis relancer le patch :
NODE_PATH="$REPO/node_modules" node "$REPO/scripts/patch_2_2_1.js" \
    "$RES/app.asar" "/tmp/ag-build" "/tmp/app.asar.patched"
```

---

## 8. Leçons apprises

### 8.1 Toujours lire les logs applicatifs AVANT l'erreur réseau

L'erreur `127.0.0.1:443 refused` est déroutante parce qu'elle parle réseau,
mais la cause est dans `main.log` :

```
[error] [PATCH] startProxy failed: Cannot find module '../cryptoStore'
```

→ Le réflexe : `grep -i "error\|fail" main.log` **avant** de chercher du côté
des ports/firewall/réseau.

### 8.2 Diff `dist/` du repo vs `dist/` de l'asar déployé

```bash
# Fichiers dans dist/ du repo mais pas dans l'asar déployé :
npx -y @electron/asar list "$RES/app.asar" | sort > /tmp/asar.txt
ls "$REPO/dist/"*.js | xargs -n1 basename | sort > /tmp/dist.txt
comm -23 /tmp/dist.txt <(awk -F'/' '/^\/dist\/[a-zA-Z][^\/]*\.js$/ {print $3}' /tmp/asar.txt | sort)
```

Cette commande a révélé les 3 modules manquants.

### 8.3 L'overlay complet de `dist/` n'est PAS une option sûre

Un repack qui copie tout `dist/` :

- Remplace le `dist/main.js` patché par le `main.js` upstream (perd
  l'integration TLS bypass + `require('../proxy-runner')`).
- Emporte les `__mocks__/*` (mocks vitest) → Electron résout ces mocks
  comme s'ils étaient les vrais modules `electron`, `electron-log`, etc.
- Emporte les `*.test.js` → pollution de l'asar de production.

→ Toujours faire un overlay **chirurgical** : copier uniquement les fichiers
explicitement nécessaires.

### 8.4 Backup avant chaque opération destructive

Le pattern `app.asar.pre-<operation>-<ISO>.bak` a sauvé la mise plusieurs fois :

```
app.asar.pre-recon-20260711T133348.bak       ← utilisé pour restaurer après tentative ratée
app.asar.pre-surgical-20260711T135228.bak    ← snapshot après restauration
```

À garder : au minimum les 3 derniers backups.

### 8.5 Versioning sémantique d'Antigravity = breaking changes

| 2.0.x → 2.1.0 | pas de breaking change (proxy intact) |
| 2.1.0 → 2.2.x | **breaking** : proxy code supprimé du bundle officiel |
| 2.2.x → 2.3+ | à surveiller (le pattern de Google est de réduire le surface area) |

À chaque update, refaire le diagnostic de §3 avant d'appliquer le patch.

---

## 9. Références

- **Session kimchi de référence** : `019f4c39-447f-74ac-8dc8-8e4be561aa0d` (2026-07-10 13:30)
  - Message 14:02:01 : explication de la suppression du proxy en v2.2.x
  - Message 14:20:24 : première confirmation de patch réussi
- **Patcher** : `scripts/patch_2_2_1.js`
- **Code source des modules injectés** :
  - `src/cryptoStore.ts`
  - `src/customModelStore.ts`
  - `src/schemaValidator.ts`
- **Caller** : `src/proxy/modelLoader.ts` (ligne 10 : `import * as cryptoStore from '../cryptoStore';`)
- **Fallback dans le LS** : `src/languageServer.ts` (ligne 168-169)
- **Autre doc liée** :
  - `TROUBLESHOOTING.md` (flowchart port 50999)
  - `SOLUTION_LAUNCH_FIX.md` (problème de lancement après update)
  - `docs/MITM-Notes.md` (notes sur le MITM 443)

---

## 10. Le MITM sur 443 (Cause #2 — OBLIGATOIRE)

### 10.1 Pourquoi c'est obligatoire

Le proxy sur 50999 est en **HTTP plain** (pas HTTPS). Il ne peut pas
intercepter les appels HTTPS que le language server fait directement à
`daily-cloudcode-pa.googleapis.com` (que le `hosts` file redirige vers
`127.0.0.1`).

Le MITM (`scripts/mitm/mitm_443.js`) est un **terminateur TLS** qui :
1. Écoute sur `127.0.0.1:443` avec un certificat auto-signé.
2. Décrypte le trafic HTTPS entrant.
3. Forwarde la requête HTTP déchiffrée vers `http://127.0.0.1:50999` (le proxy).
4. Récupère la réponse, la renvoie cryptée au client.

Le CA (`certs/ca-cert.pem`) doit être trusted dans le Windows cert store
**LocalMachine\Root** ET **CurrentUser\Root** pour que le language server
accepte le certificat.

### 10.2 Pourquoi il ne démarre pas automatiquement

Le patch (v2.2.x et antérieur) :
- Démarre automatiquement le proxy sur 50999 (via `proxy-runner.js` chargé
  par `dist/main.js`).
- **Ne démarre PAS le MITM sur 443** parce que :
  - Le MITM a besoin des droits **administrateur** (port 443 < 1024 réservé,
    installation du CA dans LocalMachine\Root).
  - Lancer un process admin depuis Electron sans UAC prompt est compliqué.
  - Google ne fournit pas ce mécanisme — c'est à l'utilisateur.

Conséquence pratique : **après chaque reboot ou après chaque mise à jour
d'Antigravity, il faut relancer manuellement le MITM**.

### 10.3 Lancement manuel

Voir §12 pour la procédure complète étape par étape.

En une ligne (PowerShell **ADMINISTRATEUR**) :

```powershell
Start-Process -FilePath "powershell" -Verb RunAs -ArgumentList @(
  "-NoProfile","-ExecutionPolicy","Bypass","-File",
  "C:\Users\amine\Downloads\antigravity-add-model-main\antigravity-add-model-main\scripts\mitm\start_mitm_443.ps1"
)
```

### 10.4 Vérification

```powershell
Get-NetTCPConnection -LocalPort 443 -State Listen | Format-Table LocalAddress,LocalPort,OwningProcess
```

Attendu :

```
LocalAddress  LocalPort  OwningProcess
------------  ---------  -------------
127.0.0.1     443        <PID node.exe>   ← MITM actif
127.0.0.2     443        <PID svchost>    ← Windows service (sans rapport)
```

Si seul `127.0.0.2:443` apparaît (pas de `127.0.0.1`), le MITM n'est pas
démarré — relancer avec §12.

---

## 11. Quick-start :流程 complet après un update Antigravity

Quand Antigravity est mis à jour par Google (auto-update ou manuel), voici la
séquence **exacte** pour revenir à un état fonctionnel.

### 11.1 Pré-requis

- WSL2 fonctionnel
- Node.js ≥ 18 + le repo `antigravity-add-model-main` à jour
- Droits admin Windows (pour lancer le MITM)
- `certs/ca-cert.pem` présent dans le repo

### 11.2 Pipeline (copier-coller depuis WSL)

```bash
# ───────────────────────────────────────────────────────────────────
# Étape 1 — Stopper tout
# ───────────────────────────────────────────────────────────────────
powershell.exe -Command "Stop-Process -Name Antigravity,language_server -Force -ErrorAction SilentlyContinue"

# ───────────────────────────────────────────────────────────────────
# Étape 2 — Rebuild + patch chirurgical (Cause #1)
# ───────────────────────────────────────────────────────────────────
cd /mnt/c/Users/amine/Downloads/antigravity-add-model-main/antigravity-add-model-main
git pull                         # si repo versionné
npm install --no-save @electron/asar
npm run build                    # compile dist/

# Snapshot avant patch
TS=$(date +%Y%m%dT%H%M%S)
RES="/mnt/c/Users/amine/AppData/Local/Programs/Antigravity/resources"
cp "$RES/app.asar" "$RES/app.asar.pre-update-$TS.bak"

# Patch
NODE_PATH="$(pwd)/node_modules" node scripts/patch_2_2_1.js \
    "$RES/app.asar" "/tmp/ag-build-$TS" "/tmp/app.asar.fixed-$TS"

# Vérifier delta (~40 KB)
SIZE_BEFORE=$(stat -c %s "$RES/app.asar")
SIZE_AFTER=$(stat -c %s "/tmp/app.asar.fixed-$TS")
DELTA=$((SIZE_AFTER - SIZE_BEFORE))
echo "delta: $DELTA B"
[ $DELTA -lt 100000 ] && cp "/tmp/app.asar.fixed-$TS" "$RES/app.asar"

# ───────────────────────────────────────────────────────────────────
# Étape 3 — Lancer le MITM (Cause #2, depuis PowerShell ADMIN)
# ───────────────────────────────────────────────────────────────────
powershell.exe -Command "Start-Process -FilePath 'powershell' -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Users\amine\Downloads\antigravity-add-model-main\antigravity-add-model-main\scripts\mitm\start_mitm_443.ps1'"

# Attendre que le MITM démarre
sleep 5
powershell.exe -Command "Get-NetTCPConnection -LocalPort 443 -State Listen | Where-Object { \$_.LocalAddress -eq '127.0.0.1' } | Format-Table LocalAddress,LocalPort,OwningProcess"

# ───────────────────────────────────────────────────────────────────
# Étape 4 — Lancer Antigravity
# ───────────────────────────────────────────────────────────────────
powershell.exe -Command "Start-Process -FilePath 'C:\Users\amine\AppData\Local\Programs\Antigravity\Antigravity.exe'"

# Attendre la stabilisation
sleep 20

# ───────────────────────────────────────────────────────────────────
# Étape 5 — Vérifier
# ───────────────────────────────────────────────────────────────────
LOG="/mnt/c/Users/amine/AppData/Roaming/Antigravity/logs/main.log"
echo "=== ports ==="
powershell.exe -Command "Get-NetTCPConnection -LocalPort 50999,443 -State Listen | Where-Object { \$_.LocalAddress -match '127.0.0.1' } | Format-Table LocalAddress,LocalPort,OwningProcess,State"
echo "=== dernier log ==="
tail -10 "$LOG"
echo "=== modèles custom chargés ==="
grep "Custom model" "$LOG" | tail -5
echo "=== startProxy errors ==="
grep -c "startProxy failed" "$LOG"
```

Si `startProxy failed` est > 0 OU si aucun « Custom model » n'apparaît,
relancer `npm run build` puis ré-appliquer l'étape 2.

---

## 12. Procédure manuelle complète du MITM

### 12.1 Préparation unique (une seule fois)

1. **Ouvrir PowerShell en tant qu'administrateur** :
   - Clic droit sur le menu Démarrer → « Terminal (Admin) » ou « Windows PowerShell (Admin) ».

2. **Vérifier que le CA existe** :
   ```powershell
   Test-Path "C:\Users\amine\Downloads\antigravity-add-model-main\antigravity-add-model-main\certs\ca-cert.pem"
   ```
   Si `False`, le générer :
   ```bash
   # Depuis WSL :
   cd /mnt/c/Users/amine/Downloads/antigravity-add-model-main/antigravity-add-model-main/certs
   openssl req -x509 -newkey rsa:2048 -nodes -keyout ca-key.pem -out ca-cert.pem -days 3650 -subj "/CN=Antigravity MITM CA"
   ```

3. **Importer le CA dans le store Windows** :
   ```powershell
   Import-Certificate -FilePath "C:\Users\amine\Downloads\antigravity-add-model-main\antigravity-add-model-main\certs\ca-cert.pem" -CertStoreLocation Cert:\LocalMachine\Root
   Import-Certificate -FilePath "C:\Users\amine\Downloads\antigravity-add-model-main\antigravity-add-model-main\certs\ca-cert.pem" -CertStoreLocation Cert:\CurrentUser\Root
   ```

### 12.2 Lancement à chaque reboot / update Antigravity

Option A — Script PowerShell (le plus simple) :

```powershell
# PowerShell ADMIN
& "C:\Users\amine\Downloads\antigravity-add-model-main\antigravity-add-model-main\scripts\mitm\start_mitm_443.ps1"
```

Le script :
- Réimporte le CA (idempotent)
- Lance `node scripts/mitm/mitm_443.js` en foreground
- Affiche les logs en temps réel dans la console
- `(Ctrl+C)` pour arrêter

Option B — Wrapper VBS (pour lancer sans ouvrir une console admin) :

Créer `C:\Users\amine\StartAntigravityMITM.vbs` :
```vbs
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell -NoProfile -ExecutionPolicy Bypass -File ""C:\Users\amine\Downloads\antigravity-add-model-main\antigravity-add-model-main\scripts\mitm\start_mitm_443.ps1""", 1, False
Set WshShell = Nothing
```

Double-clic sur le VBS → UAC prompt → MITM démarre.

### 12.3 Troubleshooting MITM

| Symptôme | Cause probable | Fix |
|---|---|---|
| `EACCES` au lancement | Pas en admin | Relancer en admin |
| `EADDRINUSE` port 443 | Un autre process bind déjà 443 | `netstat -ano \| findstr :443` → tuer le process |
| MITM démarre mais LS continue d'échouer | CA non trusté | Réimporter §12.1 |
| MITM forward error vers 50999 | Proxy off | Démarrer Antigravity (qui lance le proxy) |
| Erreur TLS côté LS | CA fingerprint mismatch | Vérifier que `certs/ca-cert.pem` n'a pas été régénéré sans réimport |

### 12.4 Logs du MITM

Les logs vont dans la console où le script a été lancé. Pour logger dans un
fichier :

```powershell
& node "C:\Users\amine\Downloads\antigravity-add-model-main\antigravity-add-model-main\scripts\mitm\mitm_443.js" *>&1 \| Tee-Object -FilePath "C:\Users\amine\AppData\Local\Temp\mitm-443.log"
```

---

## 13. Leçons apprises (version corrigée)

### 13.1 MITM sur 443 est OBLIGATOIRE, pas optionnel

**Erreur d'analyse initiale** : lors du diagnostic du 2026-07-11 14:00, j'ai
affirmé à tort que le MITM n'était pas requis. La vérité :

- ✅ Le proxy sur 50999 est démarré automatiquement par `proxy-runner.js`.
- ❌ Le MITM sur 443 doit être démarré **manuellement** par l'utilisateur.
- Sans MITM : `ECONNREFUSED 127.0.0.1:443` récurrent même si le proxy tourne.

**Règle** : avant de considérer le patch comme fonctionnel, vérifier que
`127.0.0.1:443` est LISTENING (cf. §10.4).

### 13.2 Toujours lire les logs applicatifs AVANT l'erreur réseau

L'erreur `127.0.0.1:443 refused` parle réseau mais la cause est dans
`main.log` :

```
[error] [PATCH] startProxy failed: Cannot find module '../cryptoStore'
```

→ Réflexe : `grep -i "error\|fail" main.log` avant de chercher côté
ports/firewall/réseau.

### 13.3 Diff `dist/` du repo vs `dist/` de l'asar déployé

```bash
npx -y @electron/asar list "$RES/app.asar" | sort > /tmp/asar.txt
ls "$REPO/dist/"*.js | xargs -n1 basename | sort > /tmp/dist.txt
comm -23 /tmp/dist.txt <(awk -F'/' '/^\/dist\/[a-zA-Z][^\/]*\.js$/ {print $3}' /tmp/asar.txt | sort)
```

Cette commande a révélé les 3 modules manquants.

### 13.4 L'overlay complet de `dist/` n'est PAS une option sûre

Un repack qui copie tout `dist/` :

- Remplace le `dist/main.js` patché par le `main.js` upstream (perd
  l'integration TLS bypass + `require('../proxy-runner')`).
- Emporte les `__mocks__/*` (mocks vitest) → Electron résout ces mocks
  comme s'ils étaient les vrais modules.
- Emporte les `*.test.js` → pollution de l'asar de production.

→ Toujours faire un overlay **chirurgical**.

### 13.5 Backup avant chaque opération destructive

Le pattern `app.asar.pre-<operation>-<ISO>.bak` a sauvé la mise plusieurs
fois. À garder : au minimum les 3 derniers backups.

### 13.6 Versioning sémantique d'Antigravity = breaking changes

| 2.0.x → 2.1.0 | pas de breaking change (proxy intact) |
| 2.1.0 → 2.2.x | **breaking** : proxy code supprimé du bundle officiel |
| 2.2.x → 2.3+ | à surveiller (le pattern de Google est de réduire la surface area) |

À chaque update, refaire le diagnostic de §3 avant d'appliquer le patch.

### 13.7 Distinguer « l'app démarre » de « l'app fonctionne »

Symptômes trompeurs :
- App lance + fenêtre s'ouvre ≠ App fonctionnelle
- Proxy répond 200 sur /v1internal:listExperiments ≠ Custom models utilisables
- MITM bind sur 127.0.0.2 ≠ MITM bind sur 127.0.0.1

**Réflexe** : faire le tour des checks de §10.4 + §11.2 étape 5 avant de
déclarer le fix fonctionnel.

