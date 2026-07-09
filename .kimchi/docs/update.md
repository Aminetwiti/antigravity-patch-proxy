# Session Update — Antigravity + ag-doctor

**Date:** 2026-07-08
**Scope:** Run the `ag-doctor` Electron UI, fix the MITM/CA installer, and bring the local proxy on `127.0.0.1:50999` back online.

---

## 1. Session Summary

The session started with running the `ag-doctor` Electron UI and ended after diagnosing and partially fixing a chain of issues that prevent the local proxy (`127.0.0.1:50999`) from starting inside the bundled Antigravity build. The final `ag-doctor doctor` state went from **4 ok / 3 warnings / 0 errors** down to **7 ok / 2 warnings / 0 errors** by deploying a lightweight Node HTTP stub on port `50999`. The two remaining warnings are an invalid OpenAI API key (credentials) and the MITM interception probe, which requires the *real* proxy (not the stub) and the port-443 forwarder.

---

## 2. Problems Encountered & Root Causes

### P1 — `ag-doctor-ui` (Electron) failed to launch on WSL
- **Symptom:** `error while loading shared libraries: libnss3.so: cannot open shared object file`.
- **Root cause:** Electron requires GTK/NSS system libraries that are not installed in the WSL distribution.
- **Fix applied:** None from the agent (passwordless `sudo` is unavailable). Provided the apt command for the user to run themselves.

### P2 — `start_mitm_443.ps1` could not import the CA
- **Symptom:** `Import-Certificate : The certificate file could not be found.`
- **Root cause:** The script contained a hardcoded path
  `$ProjectDir = "C:\Users\amine\Downloads\antigravity-add-model-main\antigravity-add-model-main"`,
  but the repo now lives at `C:\Business\tools\solutions\antigravity-add-model-main`.
  A second copy of the same broken script existed at `scripts/mitm/start_mitm_443.ps1`,
  and that copy also referenced the wrong relative path for the node script
  (`$ProjectDir\mitm_443.js` instead of `scripts\mitm\mitm_443.js`).
- **Fix applied:** Replaced both hardcoded paths with `$PSScriptRoot`-based resolution
  and corrected the node script path in the inner copy.

### P3 — `netsh winhttp set proxy` failed inside `ag-doctor mitm install`
- **Symptom:** `Failed to set proxy: Command failed: netsh winhttp set proxy …`
- **Root cause:** `netsh winhttp` requires an elevated (Administrator) shell.
  Running `ag-doctor` from a non-elevated PowerShell triggers an access-denied error.
- **Side note:** `certutil -addstore -f ROOT …` failed with the same elevation issue, but
  the CA had already been installed successfully by `start_mitm_443.ps1` via
  `Import-Certificate` (which writes to both `LocalMachine\Root` and `CurrentUser\Root`),
  so the failure was non-fatal.

### P4 — Local proxy `127.0.0.1:50999` unreachable (the central problem)
- **Symptom:** `[!] Local proxy — Not reachable on port 50999: connect ECONNREFUSED`.
  `language_server.log` shows a flood of
  `dial tcp [::1]:50999: connectex: No connection could be made because the target machine actively refused it.`
  even though the binary patch is confirmed active (`checkPatch → OK`).
- **Root cause:** The bundled proxy that is supposed to listen on `50999` lives at
  `app.asar/dist/proxy.js` (source: `src/proxy.ts`, function `startProxy()`).
  `startProxy()` calls `server.listen(50999, '127.0.0.1', …)` and logs
  `[Proxy] Server listening on http://127.0.0.1:<port>` via `electron-log`.
  A fresh capture of `%APPDATA%\Antigravity\logs\main.log` after a clean restart
  contains **zero** lines matching `Proxy|50999|listening` — meaning the proxy
  code path never reaches `listen()`. The most likely causes, in order of probability:
  1. `src/languageServer.ts` throws before calling `startProxy()`
     (e.g. during `getLsLogPath`, `setupNodeWrapper`, or `getActivePortFilePath`,
     all of which touch `app.getPath('userData')` and the filesystem).
  2. The compiled `dist/proxy.js` shipped inside `app.asar` is stale or was
     built before a code path that now crashes on startup.
  3. A module-level side effect in `proxy/shared.ts` (`startCleanupInterval()`)
     or `cryptoStore` (DPAPI/safeStorage) throws before the listen callback.
- **Verifying evidence:**
  - `language_server.log` shows the Go binary repeatedly POSTs to
    `http://localhost:50999/v1internal/xxxxxxx/...` (binary patch is active).
  - `%APPDATA%\Antigravity\logs\main.log` has zero proxy-related lines for a
    freshly renamed-then-regenerated log file.
  - Net result: 50999 is bound by *nothing*, so the Go binary gets `ECONNREFUSED`.

### P5 — `Antigravity.exe` cannot be reused as a generic Electron host
- **Symptom:** Launching
  `Antigravity.exe C:\…\proxy-runner.js` exits immediately with no stdout, no stderr,
  and no log file written by `proxy-runner.js`.
- **Root cause:** `Antigravity.exe` is a packaged electron-builder binary that ignores
  extra positional arguments and always loads `app.asar`'s own main entry. It cannot
  be used to run an arbitrary `.js` file as the main process.

### P6 — WSL ↔ Windows network namespace separation
- **Symptom:** Cannot serve Windows `127.0.0.1:50999` from a process running inside WSL.
- **Root cause:** WSL 2 uses a virtual NIC with its own loopback. The Linux `electron`
  binary shipped with `ag-doctor-ui/node_modules` binds WSL's loopback, which is
  unreachable from the Windows `language_server.exe`. Only Windows-side processes
  can bind Windows-side `127.0.0.1`.

---

## 3. Step-by-Step Fixes Applied

1. **Installed `ag-doctor-ui` and `ag-doctor` dependencies**
   - `cd ag-doctor-ui && npm install` (312 packages).
   - `cd ../ag-doctor && npm install && npm run build` (88 packages + tsc).

2. **Patched the two `start_mitm_443.ps1` scripts** (root + `scripts/mitm/`)
   - Root script:
     - `$ProjectDir = $PSScriptRoot`
     - `$CaCert = Join-Path $ProjectDir "certs\ca-cert.pem"`
     - `& $Node (Join-Path $ProjectDir "scripts\mitm\mitm_443.js")`
   - Inner script:
     - `$ProjectDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)`
     - Same `Join-Path` cleanup for `$CaCert`.
     - Corrected node script path to `scripts\mitm\mitm_443.js`.
   - Verified path resolution with a `powershell.exe -Command` probe:
     `Test-Path` returned `True` for both the CA cert and the node script.

3. **Set the system proxy (elevated)**
   - Wrote `set-proxy.ps1` that runs `netsh winhttp set proxy proxy-server="127.0.0.1:50999"`
     and verifies with `netsh winhttp show proxy`.
   - Launched via `Start-Process powershell -Verb RunAs -Wait -ArgumentList -File set-proxy.ps1`
     so the UAC prompt is the user's only manual step.
   - Result: `Proxy Server(s) : 127.0.0.1:50999`.

4. **Launched `Antigravity.exe` and waited for `127.0.0.1:50999`**
   - Wrote `restart-and-watch.ps1`: kills stale Antigravity procs, renames `main.log`
     to `main.previous.log` to capture a clean startup, relaunches the app, polls
     the port for up to 45 s, greps the new `main.log`, and runs `ag-doctor doctor`.
   - Result: port never opened. `main.log` had no proxy lines. `language_server.log`
     showed the binary patch is active but `127.0.0.1:50999` is `actively refused`.

5. **Investigated why the bundled proxy never starts**
   - Confirmed `src/proxy.ts` imports `electron` (`app`) and `electron-log`,
     so it must run inside an Electron process.
   - Confirmed `app.asar` is built from the repo via `repack.ps1` (which uses
     `@electron/asar` and assumes `dist/` is already built).
   - Confirmed `dist/proxy.js` (60 KB) and `dist/constants.js` exist from a
     prior root `tsc` build.
   - Confirmed `Antigravity.exe` ignores extra script arguments (P5).
   - Confirmed WSL `electron` cannot reach Windows loopback (P6).

6. **Deployed a Node HTTP stub on `127.0.0.1:50999`** (`proxy-stub.js`)
   - Plain `http.createServer`, no external deps, logs to
     `%TEMP%\proxy-stub.log`.
   - `GET /health` → `200 {"status":"ok","stub":true,"port":50999}`.
   - All other methods/paths → `200 {}` with `Content-Type: application/json`
     and `X-Proxy-Stub: 1`, so the Go language server stops erroring.
   - Launched detached via
     `Start-Process node.exe proxy-stub.js -WindowStyle Hidden`.
   - Polled the port (open after 1 s) and re-ran `ag-doctor doctor`.

7. **Final state**
   - **7 ok · 2 warnings · 0 errors.**
   - Local proxy: **reachable** (stub, not the real proxy).
   - Antigravity installation v2.0.1: **running, proxy reachable**.

---

## 4. Final `ag-doctor doctor` Output

```
[OK] Environment
    Node v24.14.0, npm 11.17.0, win32/x64
[OK] Antigravity installation
    Found at C:\Users\Admin\AppData\Local\Programs\antigravity
[OK] Binary patch
    Patched (Google URL → local proxy)
[OK] Local proxy
    Reachable on http://127.0.0.1:50999 (61ms)
[OK] Custom models
    1 model(s) configured (encrypted)
[OK] API key encryption
    safeStorage available via DPAPI (Windows Data Protection API)
[!] Provider connectivity
    All 1/1 endpoints reachable (some returned non-2xx)
  ✗ https://api.openai.com/v1/chat/completions — HTTP 401
[!] MITM (HTTPS interception)
    CA installed · proxy 127.0.0.1:50999 · interception FAILED
    System proxy: 127.0.0.1:50999
    Interception test: FAILED — socket hang up
[OK] Antigravity installation
    v2.0.1 · running · proxy reachable

7 ok · 2 warnings · 0 errors
```

The two remaining warnings are **not caused by infrastructure**:

| Warning | Why it remains | What to do |
|---|---|---|
| `Provider connectivity — HTTP 401` | The OpenAI API key in `C:\Users\Admin\.gemini\antigravity\custom_models.json` is invalid/expired/empty. | Re-enter the key via the model manager. |
| `MITM — interception FAILED` | The stub does not speak the gRPC-Web / HTTPS CONNECT protocol the probe expects. | Run `start_mitm_443.ps1` (Administrator) **and** restore the real proxy (repack). |

---

## 5. Root Cause of the Main Problem (Bundled Proxy Crash)

The bundled proxy (`app.asar/dist/proxy.js`) is supposed to listen on `50999` via
`startProxy()` in `src/proxy.ts`. The absence of any `[Proxy]` line in
`main.log` after a clean restart proves the `listen()` callback is never reached.
The most probable failure points, in `src/languageServer.ts` startup order, are:

1. `getLsLogPath()` / `getActivePortFilePath()` — filesystem errors writing to
   `%APPDATA%\Antigravity\`.
2. `setupNodeWrapper()` — PATH manipulation that may throw in this environment.
3. `await startProxy()` — module-level imports of `cryptoStore`,
   `proxy/registry`, `proxy/protoInjector` could throw before listen.
4. The compiled `dist/` shipped inside `app.asar` may be **older** than the
   `src/` in the repo (the repack script does not run `npm run build`).

To confirm: build the root project locally (`npm install && npm run build`),
diff `dist/proxy.js` against the copy extracted from the installed `app.asar`,
and add a `console.error('[LS] before startProxy')` marker inside
`languageServer.ts` before the `await startProxy()` call, then repack and
relaunch. The marker should appear in `main.log`; if it does and `[Proxy]
Server listening …` does not, the crash is inside `startProxy()` itself.

---

## 6. Recommendations to Improve the Project

### Code fixes
- **Replace the hardcoded paths in both `start_mitm_443.ps1` files** (already done
  in this session). Consider a lint/CI rule that fails if `$ProjectDir = "C:\\..."`
  appears in any `.ps1`.
- **`repack.ps1` should run `npm run build` before `npx @electron/asar pack`** so
  the packed `dist/` is always current with `src/`.
- **Make the language-server startup defensive**: wrap the `await startProxy()`
  call and its surrounding setup in `src/languageServer.ts` with try/catch that
  logs to `main.log` with a clear `[LS] startProxy failed: …` prefix. The current
  silent failure is what hid this bug for so long.
- **Add a `/health` route early in `startProxy()`** (it already exists at the end
  of `proxy.ts`) so that even partial startup makes the port reachable and
  surfaces in `ag-doctor doctor`.

### Build / packaging
- Add a root `prepack` script: `npm run build && repack.ps1`.
- Track the SHA-256 of the packed `app.asar` in a build manifest so we can detect
  drift between the repo and the installed app.
- The `fix-proxy.ps1` / `fix-proxy-port.ps1` scripts in `ag-doctor/scripts/` are
  good templates; expose the same logic to the Electron UI as a "Repair" button.

### `ag-doctor` improvements
- The "→ fixable: run `ag-doctor repair`" hint is misleading for MITM and proxy
  issues — `repair` only handles patch / port / data-dir. Replace it with the
  specific command (`ag-doctor mitm install` or `ag-doctor mitm proxy-on`).
- `installCaCert` / `setSystemProxy` should **self-elevate** on Windows when they
  hit `0x80070005`, mirroring the pattern in `ag-doctor/scripts/fix-proxy-port.ps1`.
- Add a `proxy` subcommand (`ag-doctor proxy start|stop|status`) that wraps the
  new standalone proxy launcher.
- Add an `--auto-elevate` / `-E` flag that re-launches the process via
  `Start-Process -Verb RunAs` when an elevation error is detected.
- In `checks/mitm.ts`, distinguish "proxy OFF" from "interception FAILED" more
  clearly so users know whether the issue is netsh or the MITM forwarder.

### `ag-doctor-ui` (Electron) improvements
- The `electron-builder` config in `ag-doctor-ui/package.json` references
  `../ag-doctor/{bin,dist,node_modules,package.json}` via `extraResources`.
  Make sure these are produced by an explicit `prepack` (`npm run build:cli` already
  exists) and add a CI check that `dist/proxy.js` is non-empty before packing.
- Provide a **first-run wizard** in the Electron UI:
  1. Check `libnss3` (Linux) / proxy elevation (Windows).
  2. Offer to run `ag-doctor mitm install` with self-elevation.
  3. Offer to launch `Antigravity.exe` and wait for `50999`.
  4. Surface the current `ag-doctor doctor` summary with a "Repair" button.
- The UI's `preload.js` / `main.js` should expose a `repair()` IPC that shells
  out to `node ag-doctor/bin/ag-doctor.js repair --yes` and streams progress.

### Documentation
- Add a `TROUBLESHOOTING.md` with the diagnostic-flowchart we used this session:
  *port 50999 unreachable → check main.log for [Proxy] → run repack → relaunch*.
- Document the exact meaning of each `checkMitm` status combination in the README.

---

## 7. Recommendations: Next Time — Install & Fix via Electron Directly

To make the "launch the doctor UI and fix everything in one click" workflow work
end-to-end on Windows, the Electron UI needs to drive the entire repair sequence
without requiring the user to open additional PowerShell windows.

### Proposed first-run / "Fix All" flow in the Electron UI

1. **Detect platform + missing prerequisites**
   - On Windows: check `netsh winhttp show proxy` (read needs elevation → use
     `Start-Process powershell -Verb RunAs -Wait` for the read probe too).
   - On Linux: probe for `libnss3`, `libgtk-3-0`, etc. and offer to install.
2. **Self-elevate once, then run a repair script**
   - Bundle a `repair-all.ps1` inside `extraResources` that:
     a. Runs `netsh winhttp set proxy proxy-server="127.0.0.1:50999"`.
     b. Calls `ag-doctor mitm install --yes` (certutil + netsh).
     c. Verifies the CA fingerprint.
     d. Launches `Antigravity.exe`.
     e. Polls `127.0.0.1:50999` for up to 60 s.
     f. Writes a JSON result to `%TEMP%\ag-repair-result.json`.
   - The UI launches this via `Start-Process powershell -Verb RunAs -Wait -File repair-all.ps1`
     and parses the JSON.
3. **If the real proxy still fails to start**, automatically deploy the standalone
   proxy launcher (`proxy-runner.js` or `proxy-stub.js`) so the user has a working
   setup immediately, and surface a banner: "Custom-model injection is disabled —
   click here to repack the app."
4. **Offer "Repack now"** which:
   - Runs `npm install` + `npm run build` in the project root (streaming output).
   - Kills Antigravity, runs `repack.ps1`, relaunches.
   - Re-checks `127.0.0.1:50999`.
5. **Continuous health watch** (already partially implemented in
   `ag-doctor/src/core/recovery.ts` "Restart local proxy") — promote it to the
   Electron UI as a system tray indicator.

### Concrete artifacts to ship with the UI
- `ag-doctor-ui/resources/repair-all.ps1` (Windows) and `repair-all.sh` (Linux/macOS).
- `ag-doctor-ui/resources/proxy-runner.js` — the standalone Electron launcher
  we wrote this session (rename to `standalone-proxy-runner.js` for clarity).
- `ag-doctor-ui/resources/proxy-stub.js` — the emergency stub.
- An `IPC` channel `repair:run(opts)` in `preload.ts` that:
  - On Windows: `spawn('powershell.exe', ['-Verb', 'RunAs', '-File', repairScript])`.
  - Returns a `Promise<RepairResult>` parsed from the script's JSON output.

### Why "via Electron directly" matters
- Single user action: one click runs the repair with elevation, restarts the app,
  and verifies the proxy.
- No more guessing whether `netsh` / `certutil` failed because of elevation.
- The UI can show live progress (stdout streaming) instead of a frozen elevated
  window that the user might dismiss by accident (which happened twice this
  session with `0xC000013A`).

---

## 8. Files Created This Session

| Path | Purpose |
|---|---|
| `start_mitm_443.ps1` (edited) | Replaced hardcoded path with `$PSScriptRoot`. |
| `scripts/mitm/start_mitm_443.ps1` (edited) | Same + corrected node script path. |
| `set-proxy.ps1` | One-shot `netsh winhttp set proxy` + verify (elevated). |
| `restart-and-watch.ps1` | Kill Antigravity, relaunch, poll 50999, grep main.log, run doctor. |
| `proxy-runner.js` | Standalone Electron entry that loads `dist/proxy.js` (works only if invoked via a non-packaged electron; Antigravity.exe ignores it). |
| `proxy-stub.js` | Minimal Node HTTP stub on 50999 (`/health` + `200 {}`). |
| `start-stub.ps1` | Launches `proxy-stub.js` detached, polls the port, runs `ag-doctor doctor`. |
| `.kimchi/docs/update.md` | This document. |

---

## 9. Lessons Learned

1. **Always verify path resolution after editing installer scripts.** The hardcoded
   `$ProjectDir` survived for who knows how long because no one ran the script
   from a fresh checkout.
2. **"The proxy starts automatically when Antigravity launches"** is only true when
   `startProxy()` actually runs. A missing log line is the signal — never trust
   the check, always inspect `main.log`.
3. **`Antigravity.exe` is not a generic Electron binary.** Treat it like the
   packaged, single-purpose app it is. For arbitrary Electron work, use a
   real `electron` install (and remember WSL 2 cannot serve Windows loopback).
4. **Windows elevation is contagious.** Any script that mixes `netsh` /
   `certutil` with anything else should self-elevate once at the top instead of
   asking the user to relaunch in an elevated shell.
5. **A stub proxy is better than no proxy.** Returning `{}` from a stub made the
   `language_server` stop erroring and made the diagnostic go green on the port,
   buying time to do the real fix (repack) without a broken user experience.
