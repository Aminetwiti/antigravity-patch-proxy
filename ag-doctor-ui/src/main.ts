/**
 * Electron main process.
 * Creates the BrowserWindow, registers IPC handlers, and spawns the ag-doctor CLI.
 *
 * Performance optimizations:
 *  - CLI Worker Pool: long-lived Node.js processes that handle multiple commands via
 *    JSON-over-stdin. Eliminates per-call process spawn cost (~150-300ms each).
 *  - Cached asset paths and tray icons.
 *  - Streaming batches chunks to avoid IPC flooding.
 *  - No console-message forwarding in production.
 */
import { app, BrowserWindow, ipcMain, shell, Tray, Menu, nativeImage, Notification, type NativeImage } from 'electron';
import path from 'path';
import { spawn, ChildProcess } from 'child_process';
import fs from 'fs';
import { getProxyManager } from './proxy-manager';

const isDev = !app.isPackaged;
let mainWindow: BrowserWindow | null = null;
let tray: Tray | null = null;
const activeStreams = new Map<string, ChildProcess>();

// Ports are env-driven so the UI never hardcodes a local bind address.
const MAIN_PROXY_PORT = parseInt(process.env.AG_PROXY_PORT || '51074', 10);
const STUB_PORT = parseInt(process.env.AG_PROXY_STUB_PORT || '51999', 10);

// ─────────────────────────────────────────────────────────────────────────────
// F-28 FIX — Single-instance lock: prevents two ag-doctor-ui windows from
// running simultaneously (which causes CliWorkerPool race conditions).
// ─────────────────────────────────────────────────────────────────────────────
// TEMPORARILY DISABLED FOR DEVELOPMENT
/*
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  // Another instance is already running — focus it and quit this one.
  app.quit();
} else {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.show();
      mainWindow.focus();
    }
  });
}
*/

// Disable GPU sandbox in packaged builds to avoid startup crashes on some Windows setups
app.commandLine.appendSwitch('disable-gpu');
app.commandLine.appendSwitch('no-sandbox');
app.commandLine.appendSwitch('disable-software-rasterizer');

// ─────────────────────────────────────────────────────────────────────────────
// Cached paths (computed once)
// ─────────────────────────────────────────────────────────────────────────────

let _assetsPath: string | null = null;
let _cliPath: string | null = null;
let _configPath: string | null = null;

function getAssetsPath(): string {
  if (_assetsPath === null) {
    _assetsPath = app.isPackaged
      ? path.join(process.resourcesPath, 'assets')
      : path.join(__dirname, '..', '..', 'assets');
  }
  return _assetsPath;
}

function getCliPath(): string {
  if (_cliPath === null) {
    if (app.isPackaged) {
      // In a packaged portable build, the CLI is bundled in extraResources
      // at <resources>/ag-doctor/bin/ag-doctor.js
      _cliPath = path.join(process.resourcesPath, 'ag-doctor', 'bin', 'ag-doctor.js');
    } else {
      _cliPath = path.join(__dirname, '..', '..', 'ag-doctor', 'bin', 'ag-doctor.js');
    }
  }
  return _cliPath;
}

function getConfigPath(): string {
  if (_configPath === null) {
    _configPath = path.join(app.getPath('home'), '.gemini', 'antigravity', 'config.json');
  }
  return _configPath;
}

// ─────────────────────────────────────────────────────────────────────────────
// Cached tray icons
// ─────────────────────────────────────────────────────────────────────────────

const trayIconCache = new Map<'ok' | 'warn' | 'err', NativeImage>();

function getTrayIcon(status: 'ok' | 'warn' | 'err'): NativeImage {
  const cached = trayIconCache.get(status);
  if (cached) return cached;
  const svgPath = path.join(getAssetsPath(), `tray-${status}.svg`);
  let img: NativeImage;
  if (fs.existsSync(svgPath)) {
    img = nativeImage.createFromPath(svgPath).resize({ width: 16, height: 16 });
  } else {
    const fallback = path.join(getAssetsPath(), 'icon.svg');
    if (fs.existsSync(fallback)) {
      img = nativeImage.createFromPath(fallback).resize({ width: 16, height: 16 });
    } else {
      img = nativeImage.createFromPath(svgPath);
    }
  }
  trayIconCache.set(status, img);
  return img;
}

// `info` is static for the session lifetime (platform/versions/CLI path don't change)
const infoCache = {
  platform: process.platform,
  arch: process.arch,
  versions: process.versions,
  electron: process.versions.electron,
  node: process.versions.node,
  chrome: process.versions.chrome,
  cliPath: '' as string,
};
let infoCacheReady = false;
function getInfoPayload() {
  if (!infoCacheReady) {
    infoCache.cliPath = getCliPath();
    infoCacheReady = true;
  }
  return infoCache;
}

// `config` is read from disk every call. Cache it; invalidate on theme change.
let configCache: Record<string, unknown> | null = null;
function getConfigPayload(): Record<string, unknown> {
  if (configCache) return configCache;
  try {
    const raw = fs.readFileSync(getConfigPath(), 'utf-8');
    configCache = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    configCache = { ui: { theme: 'dark' } };
  }
  return configCache;
}

function invalidateConfigCache(): void {
  configCache = null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tray + proxy-error bridge
// ─────────────────────────────────────────────────────────────────────────────

// Latest proxy error (most recent). Exposed to the tray menu and used to
// build the dynamic tooltip. Capped to a few KB so a noisy provider can't
// bloat the tooltip.
let lastProxyError: { title: string; provider: string; message: string; at: number; traceId: string } | null = null;
const TOOLTIP_TITLE_MAX = 60;
const TOOLTIP_MSG_MAX = 80;

// Ring buffer of the last N proxy errors. Lets the dashboard re-open an
// older modal without having to re-trigger the upstream failure. Capacity
// is small (50) so the in-memory footprint stays under a few KB.
const PROXY_ERROR_HISTORY_MAX = 50;
const proxyErrorHistory: Array<{
  traceId: string;
  provider: string;
  status?: number;
  errorType: string;
  rawError: string;
  title: string;
  message: string;
  suggestions: string[];
  actionUrl?: string;
  at: number;
}> = [];

function pushProxyErrorHistory(p: typeof proxyErrorHistory[number]): void {
  proxyErrorHistory.push(p);
  if (proxyErrorHistory.length > PROXY_ERROR_HISTORY_MAX) {
    proxyErrorHistory.splice(0, proxyErrorHistory.length - PROXY_ERROR_HISTORY_MAX);
  }
}

// Read the user preference for OS notifications. Default = true. The user
// can flip this off from the Settings UI; the renderer persists it via
// `ag:config:set-notify`. Returns false silently if the config file is
// unreadable — that's safer than crashing the listener.
function isNotifyEnabled(): boolean {
  try {
    const cfg = getConfigPayload();
    const ui = cfg.ui as Record<string, unknown> | undefined;
    if (ui && typeof ui.notifyEnabled === 'boolean') return ui.notifyEnabled;
  } catch {
    // fall through
  }
  return true;
}

// De-dup: the same proxy error payload (same traceId) firing repeatedly
// shouldn't spam the OS with a notification each time. We remember the last
// traceId+at combo we notified for. Reset on app boot.
let lastNotifiedTraceId: string | null = null;
let lastNotifiedAt = 0;
const NOTIFY_DEDUP_MS = 2000; // within 2 s, same traceId is collapsed

// Emit a native OS notification for an `err`-severity proxy error. Click
// brings the dashboard forward and replays the cached payload into the
// modal so the user sees the details without re-hitting the proxy.
function notifyProxyError(p: {
  traceId: string;
  provider: string;
  title: string;
  message: string;
}): void {
  if (!Notification.isSupported()) return;
  // Skip when the dashboard is already visible — the user already saw the
  // modal. This keeps the tray+modal pair quiet when the window is open.
  if (mainWindow && !mainWindow.isDestroyed() && mainWindow.isVisible() && mainWindow.isFocused()) return;
  // De-dup so a flapping provider doesn't blow up the notification center.
  if (p.traceId === lastNotifiedTraceId && Date.now() - lastNotifiedAt < NOTIFY_DEDUP_MS) return;
  lastNotifiedTraceId = p.traceId;
  lastNotifiedAt = Date.now();
  const n = new Notification({
    title: `${p.provider}: ${p.title}`.slice(0, 120),
    body: (p.message || '').slice(0, 180) || 'A provider request failed — open ag-doctor for details.',
    silent: false,
    urgency: 'critical' as const,
  });
  n.on('click', () => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.show();
      mainWindow.focus();
      mainWindow.webContents.send('proxy:error', {
        traceId: p.traceId || 'notify',
        provider: p.provider,
        errorType: 'notification-replay',
        rawError: p.message,
        title: p.title,
        message: p.message,
        suggestions: [],
      });
    }
  });
  n.show();
}

function updateTray(status: 'ok' | 'warn' | 'err'): void {
  if (!tray) return;
  tray.setImage(getTrayIcon(status));
  // When the proxy has surfaced a real error, override the tooltip with the
  // provider + title so the user can see why the tray turned red even when
  // the dashboard is hidden.
  const tooltip = lastProxyError && status !== 'ok'
    ? `ag-doctor · ${status.toUpperCase()} · ${lastProxyError.provider}: ${lastProxyError.title.slice(0, TOOLTIP_TITLE_MAX)}`
    : `ag-doctor · ${status.toUpperCase()}`;
  tray.setToolTip(tooltip);
  // Rebuild the menu so the "Latest provider error" entry stays in sync.
  tray.setContextMenu(buildTrayMenu());
}

function buildTrayMenu(): Menu {
  // Dynamic "latest provider error" sub-entry. Always present so users have a
  // visible "what just happened" affordance; disabled when no error is known.
  const items: Electron.MenuItemConstructorOptions[] = [
    {
      label: 'Open dashboard',
      click: () => {
        if (mainWindow) {
          mainWindow.show();
          mainWindow.focus();
        } else {
          createWindow();
        }
      },
    },
    {
      label: 'Run doctor',
      click: () => {
        if (mainWindow) {
          mainWindow.show();
          mainWindow.focus();
          mainWindow.webContents.send('ag:run-doctor');
        }
      },
    },
    { type: 'separator' },
  ];

  if (lastProxyError) {
    items.push({
      label: `Last error: ${lastProxyError.provider} — ${lastProxyError.title.slice(0, TOOLTIP_TITLE_MAX)}`,
      enabled: false,
    });
    items.push({
      label: 'Show details',
      click: () => {
        if (mainWindow) {
          mainWindow.show();
          mainWindow.focus();
          // Surface the latest error to the dashboard so the modal renders.
          mainWindow.webContents.send('proxy:error', {
            traceId: 'tray',
            provider: lastProxyError!.provider,
            errorType: 'tray-replay',
            rawError: lastProxyError!.message,
            title: lastProxyError!.title,
            message: lastProxyError!.message.slice(0, TOOLTIP_MSG_MAX),
            suggestions: [],
          });
        }
      },
    });
    items.push({
      label: 'Clear error',
      click: () => {
        lastProxyError = null;
        updateTray('ok');
      },
    });
    items.push({ type: 'separator' });
  }

  items.push({
    label: 'Quit',
    click: () => {
      app.quit();
    },
  });

  return Menu.buildFromTemplate(items);
}

function createTray(): void {
  tray = new Tray(getTrayIcon('ok'));
  tray.setToolTip('ag-doctor');
  tray.setContextMenu(buildTrayMenu());
  tray.on('click', () => {
    if (mainWindow) {
      mainWindow.show();
      mainWindow.focus();
    } else {
      createWindow();
    }
  });
}

function createWindow(): void {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 960,
    minHeight: 640,
    icon: path.join(getAssetsPath(), 'icon.png'),
    backgroundColor: '#0a0e1a',
    titleBarStyle: 'hidden',
    titleBarOverlay: {
      color: '#0a0e1a',
      symbolColor: '#e8eef9',
      height: 36,
    },
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
      spellcheck: false,
      // PERF: allow Chromium to throttle timers/rAF in backgrounded windows.
      // Disabling this kept the proxy poller (1.5 s) and the uptime ticker
      // (1 s) running at full cadence when the user minimized the window,
      // burning ~10-30 % idle CPU on Windows.
      backgroundThrottling: true,
    },
  });

  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));

  // PERF: cancel the unconditional 2 s fallback when ready-to-show fires so
  // we don't run a no-op show() check on every successful launch.
  const showFallback = setTimeout(() => {
    if (mainWindow && !mainWindow.isVisible()) {
      mainWindow.show();
    }
  }, 2000);

  mainWindow.once('ready-to-show', () => {
    clearTimeout(showFallback);
    mainWindow?.show();
  });

  mainWindow.webContents.on('did-fail-load', (_e, code, desc, url) => {
    console.error(`[main] did-fail-load: ${code} ${desc} ${url}`);
  });
  mainWindow.webContents.on('render-process-gone', (_e, details) => {
    console.error(`[main] render-process-gone: ${JSON.stringify(details)}`);
  });

  // Only forward console messages in dev mode (saves IPC overhead in prod)
  if (isDev) {
    mainWindow.webContents.on('console-message', (_e, _level, message) => {
      console.log(`[renderer] ${message}`);
    });
  }

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });

  if (isDev && process.env.OPEN_DEVTOOLS === '1') {
    mainWindow.webContents.openDevTools({ mode: 'detach' });
  }

  mainWindow.on('close', (e) => {
    if (process.platform === 'darwin') {
      e.preventDefault();
      mainWindow?.hide();
    }
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// CLI Worker Pool — keeps long-lived Node.js processes that handle commands
// via JSON-over-stdin. Avoids the 150-300ms cost of spawning a new process
// for every IPC call.
// ─────────────────────────────────────────────────────────────────────────────

interface CliWorker {
  proc: ChildProcess;
  busy: boolean;
  pending: {
    resolve: (val: { code: number; stdout: string; stderr: string }) => void;
    reject: (err: Error) => void;
  } | null;
  buffer: string;      // stdout buffer (JSON protocol)
  errBuffer: string;   // stderr accumulator (diagnostics only)
}

// IPC command timeout — renderer-side should also have a fallback, but this
// ensures no promise leaks even if the renderer is destroyed.
//
// 60s instead of the old 15s for two reasons:
//   1. `ag-doctor repair --yes` orchestrates a binary patch, process kill,
//      proxy start (5s + 3s polling) and CA generation — easily 10-15s on
//      a healthy machine and much longer on slow disks.
//   2. `ag-doctor mitm install` / `mitm proxy-on` may block on a UAC
//      consent dialog waiting for the user to click "Yes".
// Fast commands like `mitm status` and `patch status` are bounded by
// renderer-side `withTimeout(..., 12_000)` wrappers, so the larger worker
// timeout does not delay their perceived failure.
const WORKER_CMD_TIMEOUT_MS = 60_000;

class CliWorkerPool {
  private workers: CliWorker[] = [];
  private readonly maxWorkers = 3;
  private readonly cliPath: string;
  private nextId = 1;
  private readonly waitQueue: Array<{
    args: string[];
    resolve: (val: { code: number; stdout: string; stderr: string }) => void;
    reject: (err: Error) => void;
    timer: NodeJS.Timeout; // F-14: every queued command has a timeout
  }> = [];

  constructor(cliPath: string) {
    this.cliPath = cliPath;
  }

  private spawnWorker(): CliWorker | null {
    if (!fs.existsSync(this.cliPath)) return null;
    const proc = spawn(process.execPath, [this.cliPath, '--worker'], {
      env: { ...process.env, ELECTRON_RUN_AS_NODE: '1', AG_WORKER_ID: String(this.nextId++) },
      windowsHide: true,
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    const worker: CliWorker = { proc, busy: false, pending: null, buffer: '', errBuffer: '' };
    proc.stdout?.on('data', (chunk: Buffer) => this.handleData(worker, chunk));
    // F-03/F-15: stderr goes to errBuffer only — never mixed into JSON protocol
    proc.stderr?.on('data', (chunk: Buffer) => {
      worker.errBuffer += chunk.toString();
      // Surface non-empty stderr in development so silent crashes are visible
      if (isDev && worker.errBuffer.trim()) {
        console.warn(`[pool:worker-${worker.proc.pid}] stderr:`, worker.errBuffer.slice(-500));
      }
    });
    proc.on('close', () => this.handleClose(worker));
    proc.on('error', (err) => this.handleError(worker, err));
    this.workers.push(worker);
    return worker;
  }

  private handleData(worker: CliWorker, chunk: Buffer): void {
    worker.buffer += chunk.toString();
    // Newline-delimited JSON protocol
    let idx: number;
    while ((idx = worker.buffer.indexOf('\n')) >= 0) {
      const line = worker.buffer.slice(0, idx);
      worker.buffer = worker.buffer.slice(idx + 1);
      if (!line) continue;
      if (worker.pending) {
        try {
          const msg = JSON.parse(line);
          worker.pending.resolve({
            code: msg.code ?? 0,
            stdout: msg.stdout ?? '',
            stderr: msg.stderr ?? '',
          });
        } catch {
          worker.pending.resolve({ code: 0, stdout: line, stderr: '' });
        }
        worker.pending = null;
        worker.busy = false;
        this.dispatchNext();
      }
    }
  }

  private handleClose(worker: CliWorker): void {
    if (worker.pending) {
      worker.pending.reject(new Error('CLI worker closed unexpectedly'));
      worker.pending = null;
    }
    worker.busy = false;
    const idx = this.workers.indexOf(worker);
    if (idx >= 0) this.workers.splice(idx, 1);

    // F-14 FIX: if there are queued commands but no live workers left and we
    // can't spawn more (e.g. cliPath gone), drain the queue with rejections
    // so no promise hangs indefinitely.
    if (this.waitQueue.length > 0 && this.workers.length === 0 && !fs.existsSync(this.cliPath)) {
      const err = new Error('CLI worker pool exhausted — no workers available');
      for (const item of this.waitQueue) {
        clearTimeout(item.timer);
        item.reject(err);
      }
      this.waitQueue.length = 0;
      return;
    }
    this.dispatchNext();
  }

  private handleError(worker: CliWorker, err: Error): void {
    if (worker.pending) {
      worker.pending.reject(err);
      worker.pending = null;
    }
    worker.busy = false;
  }

  private dispatchNext(): void {
    if (this.waitQueue.length === 0) return;
    const idle = this.workers.find((w) => !w.busy);
    if (!idle) {
      // F-14 FIX: try to spawn a new worker for the queued item
      if (this.workers.length < this.maxWorkers) {
        const w = this.spawnWorker();
        if (w) {
          const next = this.waitQueue.shift()!;
          clearTimeout(next.timer);
          this.runOn(w, next.args).then(next.resolve).catch(next.reject);
        }
      }
      return;
    }
    const next = this.waitQueue.shift()!;
    clearTimeout(next.timer);
    this.runOn(idle, next.args).then(next.resolve).catch(next.reject);
  }

  private async runOn(
    worker: CliWorker,
    args: string[],
  ): Promise<{ code: number; stdout: string; stderr: string }> {
    return new Promise((resolve, reject) => {
      worker.busy = true;

      // F-14 FIX: per-command timeout — if worker stops responding (hung/zombie)
      // the promise still resolves within WORKER_CMD_TIMEOUT_MS milliseconds.
      const timer = setTimeout(() => {
        if (worker.pending) {
          worker.pending = null;
          worker.busy = false;
          // Kill the stuck worker so handleClose can respawn
          try { worker.proc.kill(); } catch { /* ignore */ }
          reject(new Error(`CLI worker timed out after ${WORKER_CMD_TIMEOUT_MS / 1000}s running: ${args.join(' ')}`));
        }
      }, WORKER_CMD_TIMEOUT_MS);

      worker.pending = {
        resolve: (val) => { clearTimeout(timer); resolve(val); },
        reject:  (err) => { clearTimeout(timer); reject(err); },
      };

      try {
        worker.proc.stdin?.write(JSON.stringify({ args }) + '\n');
      } catch (err) {
        clearTimeout(timer);
        worker.pending = null;
        worker.busy = false;
        reject(err as Error);
      }
    });
  }

  async run(args: string[]): Promise<{ code: number; stdout: string; stderr: string }> {
    if (!fs.existsSync(this.cliPath)) {
      return { code: -1, stdout: '', stderr: `CLI not found: ${this.cliPath}` };
    }
    // Try to find an idle worker
    const idle = this.workers.find((w) => !w.busy);
    if (idle) return this.runOn(idle, args);

    // Spawn a new worker if under cap
    if (this.workers.length < this.maxWorkers) {
      const w = this.spawnWorker();
      if (w) return this.runOn(w, args);
    }

    // F-14 FIX: queue the command with a hard timeout so it never hangs forever
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        const idx = this.waitQueue.findIndex((q) => q.timer === timer);
        if (idx >= 0) this.waitQueue.splice(idx, 1);
        reject(new Error(`CLI command timed out in queue after ${WORKER_CMD_TIMEOUT_MS / 1000}s: ${args.join(' ')}`));
      }, WORKER_CMD_TIMEOUT_MS);
      this.waitQueue.push({ args, resolve, reject, timer });
    });
  }

  shutdown(): void {
    // F-14 FIX: drain queue with rejections before killing workers
    const shutdownErr = new Error('Worker pool is shutting down');
    for (const item of this.waitQueue) {
      clearTimeout(item.timer);
      item.reject(shutdownErr);
    }
    this.waitQueue.length = 0;
    for (const w of this.workers) {
      try { w.proc.stdin?.end(); } catch { /* ignore */ }
      try { w.proc.kill(); } catch { /* ignore */ }
    }
    this.workers = [];
  }
}

let cliPool: CliWorkerPool | null = null;
function getCliPool(): CliWorkerPool {
  if (!cliPool) cliPool = new CliWorkerPool(getCliPath());
  return cliPool;
}

// ──────────────────────────────────────────────���──────────────────────────────
// IPC handlers
// ─────────────────────────────────────────────────────────────────────────────


  function getCustomModelsPath(): string {
    return path.join(app.getPath('home'), '.gemini', 'antigravity', 'custom_models.json');
  }

  // Real-time File Watcher: Synchronize Provider changes between Antigravity and Doctor UI
  let watcherDebounce: NodeJS.Timeout | null = null;
  try {
    const customModelsPath = getCustomModelsPath();
    const customModelsDir = path.dirname(customModelsPath);
    if (!fs.existsSync(customModelsDir)) {
      fs.mkdirSync(customModelsDir, { recursive: true });
    }
    fs.watch(customModelsDir, (_eventType, filename) => {
      if (filename && filename.includes('custom_models.json')) {
        if (watcherDebounce) clearTimeout(watcherDebounce);
        watcherDebounce = setTimeout(() => {
          if (mainWindow && !mainWindow.isDestroyed()) {
            mainWindow.webContents.send('ag:providers:changed');
          }
        }, 300);
      }
    });
  } catch { /* ignore watcher errors */ }

  // Secure External Link IPC Handler
  ipcMain.handle('ag:open-external', async (_event, url: string) => {
    try {
      if (typeof url === 'string' && (url.startsWith('https://') || url.startsWith('http://'))) {
        await shell.openExternal(url);
      } else {
        console.warn(`[IPC] Blocked unsafe external URL opening attempt: ${url}`);
      }
    } catch (err) {
      console.error('[IPC] Failed to open external URL:', err);
    }
  });

  // --- Provider Management IPCs ---
  ipcMain.handle('ag:providers:get', async () => {
    try {
      const p = getCustomModelsPath();
      const c = await fs.promises.readFile(p, 'utf8');
      const parsed = JSON.parse(c.replace(/^\uFEFF/, ''));
      if (parsed.providers) return parsed.providers;
      
      // Fallback for legacy models array
      if (parsed.models && parsed.models.length > 0) {
        const pm = new Map();
        let pid = 1;
        for (const m of parsed.models) {
          const k = m.apiUrl + '|' + m.provider + '|' + m.apiKey;
          if (!pm.has(k)) {
            pm.set(k, {
              id: 'provider-' + Date.now() + '-' + (pid++),
              name: 'Legacy ' + m.provider,
              provider: m.provider,
              apiUrl: m.apiUrl,
              apiKey: m.apiKey,
              enabled: true,
              models: []
            });
          }
          pm.get(k).models.push({
            id: m.externalModelName || m.name,
            displayName: m.displayName || m.name,
            enabled: m.enabled !== false
          });
        }
        return Array.from(pm.values());
      }
      return [];
    } catch(e) {
      return [];
    }
  });

  ipcMain.handle('ag:providers:save', async (_, p) => {
    try {
      const fp = getCustomModelsPath();
      let parsed: { providers: any[]; models: any[] } = { providers: [], models: [] };
      try {
        const c = await fs.promises.readFile(fp, 'utf8');
        parsed = JSON.parse(c.replace(/^\uFEFF/, ''));
      } catch(e) {}

      if (!parsed.providers) parsed.providers = [];
      const idx = parsed.providers.findIndex((x: any) => x.id === p.id);
      if (idx !== -1) parsed.providers[idx] = p;
      else parsed.providers.push(p);

      if (Array.isArray(parsed.models) && Array.isArray(p.models)) {
        for (const pm of p.models) {
          const pmId = pm.id || pm.displayName;
          if (!pmId) continue;
          const cleanId = pmId.startsWith('models/') ? pmId.slice(7) : pmId;
          const mIdx = parsed.models.findIndex(m => {
            const mClean = (m.name || '').startsWith('models/') ? (m.name || '').slice(7) : (m.name || '');
            const urlMatch = !p.apiUrl || !m.apiUrl || p.apiUrl.toLowerCase() === m.apiUrl.toLowerCase();
            return (m.name === pmId || m.name === `models/${pmId}` || mClean === cleanId) && urlMatch;
          });
          if (mIdx !== -1) {
            parsed.models[mIdx].enabled = pm.enabled !== false && p.enabled !== false;
          }
        }
      }

      await fs.promises.writeFile(fp, JSON.stringify(parsed, null, 2), 'utf8');
      if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send('ag:providers:changed');
      return { success: true };
    } catch(e) {
      return { success: false, error: (e as Error).message };
    }
  });

  ipcMain.handle('ag:providers:delete', async (_, id) => {
    try {
      const fp = getCustomModelsPath();
      const c = await fs.promises.readFile(fp, 'utf8');
      const parsed = JSON.parse(c.replace(/^\uFEFF/, ''));
      if (parsed.providers) {
        parsed.providers = parsed.providers.filter((x: any) => x.id !== id);
        await fs.promises.writeFile(fp, JSON.stringify(parsed, null, 2), 'utf8');
        if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send('ag:providers:changed');
      }
      return { success: true };
    } catch(e) {
      return { success: false, error: (e as Error).message };
    }
  });

  ipcMain.handle('ag:providers:fetch-models', async (_evt, params: { apiUrl: string; apiKey: string }) => {
    try {
      const { net } = require('electron') as typeof import('electron');
      const baseUrl = params.apiUrl.replace(/\/+$/, '');
      const url = baseUrl.endsWith('/models') ? baseUrl : `${baseUrl}/models`;

      return new Promise((resolve) => {
        const req = net.request({ url, method: 'GET' });
        if (params.apiKey && !params.apiKey.startsWith('enc:')) {
          req.setHeader('Authorization', 'Bearer ' + params.apiKey);
        }
        req.on('response', (res: Electron.IncomingMessage) => {
          let data = '';
          res.on('data', (chunk: Buffer) => { data += chunk.toString(); });
          res.on('end', () => {
            if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
              try {
                const parsed = JSON.parse(data);
                let rawList: any[] = [];
                if (Array.isArray(parsed.data)) rawList = parsed.data;
                else if (Array.isArray(parsed.models)) rawList = parsed.models;
                else if (Array.isArray(parsed)) rawList = parsed;

                const models = rawList.map((m: any) => {
                  const id = typeof m === 'string' ? m : (m.id || m.name || 'unknown');
                  const displayName = typeof m === 'string' ? m : (m.displayName || m.name || m.id || 'unknown');
                  return { id, displayName, enabled: true };
                });
                resolve({ success: true, models });
              } catch (e) {
                resolve({ success: false, error: 'Invalid JSON response from /models endpoint' });
              }
            } else {
              resolve({ success: false, error: `HTTP ${res.statusCode}: ${data ? data.slice(0, 150) : 'Failed to fetch models'}` });
            }
          });
        });
        req.on('error', (err: Error) => resolve({ success: false, error: err.message }));
        req.end();
      });
    } catch(e) {
      return { success: false, error: (e as Error).message };
    }
  });


  ipcMain.handle('ag:providers:test', async (_evt: Electron.IpcMainInvokeEvent, params: { apiUrl: string; apiKey: string; id?: string; modelId?: string }) => {
     try {
       const { net } = require('electron') as typeof import('electron');
       const startTime = Date.now();

       // Helper to perform an HTTP request via Electron's net module
       const doRequest = (targetUrl: string, method: string, body?: string): Promise<{ statusCode: number; data: string; latencyMs: number }> => {
         return new Promise((resolve, reject) => {
           const req = net.request({ url: targetUrl, method });
           if (params.apiKey && !params.apiKey.startsWith('enc:')) {
             req.setHeader('Authorization', 'Bearer ' + params.apiKey);
           }
           if (body) {
             req.setHeader('Content-Type', 'application/json');
           }
           req.on('response', (res: Electron.IncomingMessage) => {
             let data = '';
             res.on('data', (chunk: Buffer) => { data += chunk.toString(); });
             res.on('end', () => {
               resolve({ statusCode: res.statusCode ?? 500, data, latencyMs: Date.now() - startTime });
             });
           });
           req.on('error', (err: Error) => reject(err));
           if (body) req.write(body);
           req.end();
         });
       };

       const baseUrl = params.apiUrl.replace(/\/+$/, '');
       let statusCode = 500;
       let responseData = '';
       let latencyMs = 0;

       // If modelId is explicitly supplied, test that specific model directly via /chat/completions
       if (params.modelId) {
         try {
           const postBody = JSON.stringify({
             model: params.modelId,
             messages: [{ role: 'user', content: 'ping' }],
             max_tokens: 1
           });
           const postRes = await doRequest(`${baseUrl}/chat/completions`, 'POST', postBody);
           statusCode = postRes.statusCode;
           responseData = postRes.data;
           latencyMs = postRes.latencyMs;
         } catch (err) {
           responseData = (err as Error).message;
         }
       } else {
         // 1. Try GET /models first for general provider connectivity
         try {
           const res = await doRequest(`${baseUrl}/models`, 'GET');
           statusCode = res.statusCode;
           responseData = res.data;
           latencyMs = res.latencyMs;
         } catch (err) {
           responseData = (err as Error).message;
         }

         // 2. Fallback to POST /chat/completions if GET /models failed or returned non-200
         if (statusCode < 200 || statusCode >= 300) {
           // Find a candidate model ID to test
           let testModel: string | undefined = undefined;
           if (params.id) {
             try {
               const fp = getCustomModelsPath();
               const c = await fs.promises.readFile(fp, 'utf8');
               const parsed = JSON.parse(c.replace(/^\uFEFF/, ''));
               const prov = (parsed.providers || []).find((x: any) => x.id === params.id);
               if (prov && prov.models && prov.models.length > 0) {
                 testModel = prov.models[0].id || prov.models[0].name;
               }
             } catch { /* ignore */ }
           }
           if (!testModel) testModel = 'MiniMax-M3';

           try {
             const postBody = JSON.stringify({
               model: testModel,
               messages: [{ role: 'user', content: 'ping' }],
               max_tokens: 1
             });
             const postRes = await doRequest(`${baseUrl}/chat/completions`, 'POST', postBody);
             // If POST returns 200, or a model parameter error (400), authentication worked!
             if (postRes.statusCode >= 200 && postRes.statusCode < 300) {
               statusCode = postRes.statusCode;
               responseData = postRes.data;
               latencyMs = postRes.latencyMs;
             } else if (postRes.statusCode === 401 || postRes.statusCode === 403) {
               // Auth failed on chat completions — report exact auth failure
               statusCode = postRes.statusCode;
               responseData = postRes.data;
               latencyMs = postRes.latencyMs;
             }
           } catch { /* keep original GET result if POST fails completely */ }
         }
       }

       const isSuccess = statusCode >= 200 && statusCode < 300;
       const healthStatus = isSuccess
         ? (latencyMs >= 1500 ? 'degraded' : 'healthy')
         : (statusCode === 429 ? 'degraded' : 'offline');

       const result = {
         success: isSuccess,
         status: statusCode,
         latencyMs,
         healthStatus,
         error: isSuccess ? undefined : (responseData || `HTTP ${statusCode}`)
       };

       // Persist health metadata back to custom_models.json if provider ID is supplied
       if (params.id) {
         try {
           const fp = getCustomModelsPath();
           const c = await fs.promises.readFile(fp, 'utf8');
           const parsed = JSON.parse(c.replace(/^\uFEFF/, ''));
           if (parsed.providers && Array.isArray(parsed.providers)) {
             const idx = parsed.providers.findIndex((x: any) => x.id === params.id);
             if (idx !== -1) {
               parsed.providers[idx].status = result.healthStatus;
               parsed.providers[idx].latencyMs = result.latencyMs;
               parsed.providers[idx].lastTestedAt = new Date().toISOString();
               parsed.providers[idx].lastError = result.error;
               await fs.promises.writeFile(fp, JSON.stringify(parsed, null, 2), 'utf8');
             }
           }
         } catch { /* ignore disk persist errors */ }
       }

       return result;
     } catch(e) {
       const err = e as Error;
       return { success: false, healthStatus: 'offline' as const, error: err.message };
     }
  });
  
ipcMain.handle('ag:run', async (_evt, args: string[]) => {
  return getCliPool().run(args);
});

ipcMain.handle('ag:info', async () => {
  return getInfoPayload();
});

ipcMain.handle('ag:config', async () => {
  return getConfigPayload();
});

ipcMain.handle('ag:config:set-theme', async (_evt, theme: 'dark' | 'light') => {
  try {
    const cfgPath = getConfigPath();
    let cfg: Record<string, unknown> = {};
    if (fs.existsSync(cfgPath)) {
      cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf-8'));
    }
    cfg.ui = { ...(typeof cfg.ui === 'object' && cfg.ui !== null ? cfg.ui : {}), theme };
    fs.mkdirSync(path.dirname(cfgPath), { recursive: true });
    fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2) + '\n');
    // Refresh cache so the next ag:config call returns the new theme immediately
    configCache = cfg;
    mainWindow?.webContents.send('ag:theme-changed', theme);
    return true;
  } catch {
    return false;
  }
});

// Persists the user's "Do not notify" preference. Mirrors set-theme so the
// Settings UI toggle survives app restart.
ipcMain.handle('ag:config:set-notify', async (_evt, enabled: boolean) => {
  try {
    const cfgPath = getConfigPath();
    let cfg: Record<string, unknown> = {};
    if (fs.existsSync(cfgPath)) {
      cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf-8'));
    }
    cfg.ui = { ...(typeof cfg.ui === 'object' && cfg.ui !== null ? cfg.ui : {}), notifyEnabled: !!enabled };
    fs.mkdirSync(path.dirname(cfgPath), { recursive: true });
    fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2) + '\n');
    configCache = cfg;
    return true;
  } catch {
    return false;
  }
});

ipcMain.handle('ag:config:restore-backup', async () => {
  try {
    const customModelsPath = path.join(app.getPath('home'), '.gemini', 'antigravity', 'custom_models.json');
    const bakPath = `${customModelsPath}.bak`;
    if (!fs.existsSync(bakPath)) {
      return { success: false, error: 'No backup file (.bak) found' };
    }
    const content = fs.readFileSync(bakPath, 'utf8');
    JSON.parse(content); // Validate JSON before restoring
    fs.copyFileSync(bakPath, customModelsPath);
    invalidateConfigCache();
    return { success: true };
  } catch (err: any) {
    return { success: false, error: err.message || 'Failed to restore backup (invalid JSON format)' };
  }
});

// Snapshot of the proxy-error ring buffer (read-only, most-recent first).
ipcMain.handle('ag:proxy-error-history', async () => {
  return proxyErrorHistory.slice().reverse();
});

// ─────────────────────────────────────────────────────────────────────────────
// Proxy-error channel listener — turns the tray red and updates lastProxyError
// (set by buildProxyErrorPayload() in src/proxy.ts and broadcast by
// ipcHandlers.ts over the `proxy:error` IPC channel). We also re-broadcast
// to every BrowserWindow in case the renderer was added after boot.
// ─────────────────────────────────────────────────────────────────────────────
ipcMain.on('proxy:error', (_evt, payload: {
  traceId: string;
  provider: string;
  status?: number;
  errorType: string;
  rawError: string;
  title: string;
  message: string;
  suggestions: string[];
  actionUrl?: string;
}) => {
  if (!payload || !payload.title) return;
  // Severity: 4xx other than 429 is "warn"; 5xx/timeout/auth/quota are "err".
  const sev: 'warn' | 'err' = payload.status && payload.status >= 500
    || payload.errorType === 'auth_401' || payload.errorType === 'auth_403'
    || payload.errorType === 'quota_429' || payload.errorType === 'timeout'
    ? 'err'
    : 'warn';
  lastProxyError = {
    title: payload.title,
    provider: payload.provider,
    message: payload.message || payload.rawError,
    at: Date.now(),
    traceId: payload.traceId,
  };
  updateTray(sev);
  // Push every payload into the ring buffer so the dashboard can re-open
  // any historical error. Cap is enforced inside pushProxyErrorHistory.
  pushProxyErrorHistory({
    traceId: payload.traceId,
    provider: payload.provider,
    status: payload.status,
    errorType: payload.errorType,
    rawError: payload.rawError,
    title: payload.title,
    message: payload.message,
    suggestions: payload.suggestions ?? [],
    actionUrl: payload.actionUrl,
    at: Date.now(),
  });
  // Fire a native OS notification for `err`-severity only. De-duped inside
  // notifyProxyError() so flapping providers stay quiet. Honors the user's
  // "Do not notify" preference from the Settings UI.
  if (sev === 'err' && isNotifyEnabled()) {
    notifyProxyError({
      traceId: payload.traceId,
      provider: payload.provider,
      title: payload.title,
      message: payload.message || payload.rawError,
    });
  }
});

ipcMain.handle('ag:notify', async (_evt, title: string, body: string) => {
  if (Notification.isSupported()) {
    new Notification({ title, body }).show();
  }
});

ipcMain.handle('ag:tray-status', async (_evt, status: 'ok' | 'warn' | 'err') => {
  updateTray(status);
});

ipcMain.handle('ag:reveal', async (_evt, p: string) => {
  shell.showItemInFolder(p);
});

// ─────────────────────────────────────────────────────────────────────────────
// MITM Proxy Server Management
// ─────────────────────────────────────────────────────────────────────────────

ipcMain.handle('ag:proxy:start', async () => {
  console.log('[IPC] ag:proxy:start called');
  try {
    const proxyManager = getProxyManager();
    const result = await proxyManager.start();
    console.log('[IPC] ag:proxy:start result:', result);
    return result;
  } catch (err) {
    console.error('[IPC] ag:proxy:start error:', err);
    return { ok: false, message: `Failed to start proxy: ${(err as Error).message}` };
  }
});

ipcMain.handle('ag:proxy:stop', async () => {
  console.log('[IPC] ag:proxy:stop called');
  try {
    const proxyManager = getProxyManager();
    const result = await proxyManager.stop();
    console.log('[IPC] ag:proxy:stop result:', result);
    return result;
  } catch (err) {
    console.error('[IPC] ag:proxy:stop error:', err);
    return { ok: false, message: `Failed to stop proxy: ${(err as Error).message}` };
  }
});

ipcMain.handle('ag:proxy:status', async () => {
  try {
    const proxyManager = getProxyManager();
    const status = await proxyManager.getStatus();
    return { ok: true, data: status };
  } catch (err) {
    console.error('[IPC] ag:proxy:status error:', err);
    return { ok: false, error: (err as Error).message };
  }
});

ipcMain.handle('ag:proxy:restart', async () => {
  console.log('[IPC] ag:proxy:restart called');
  try {
    const proxyManager = getProxyManager();
    const result = await proxyManager.restart();
    console.log('[IPC] ag:proxy:restart result:', result);
    return result;
  } catch (err) {
    console.error('[IPC] ag:proxy:restart error:', err);
    return { ok: false, message: `Failed to restart proxy: ${(err as Error).message}` };
  }
});


// Antigravity lifecycle: thin wrappers around the CLI's `antigravity` subcommand.
// The CLI returns JSON when invoked with --json, so we forward the parsed payload.
ipcMain.handle('ag:antigravity:status', async () => {
  const r = await getCliPool().run(['antigravity', 'status', '--json']);
  if (r.code !== 0 && r.code !== 1) {
    return { ok: false, error: r.stderr || r.stdout || `exit ${r.code}` };
  }
  try {
    return { ok: true, data: JSON.parse(r.stdout) };
  } catch (e) {
    return { ok: false, error: `parse failed: ${(e as Error).message}` };
  }
});

ipcMain.handle('ag:antigravity:version', async () => {
  const r = await getCliPool().run(['antigravity', 'version', '--json']);
  try {
    return { ok: true, data: JSON.parse(r.stdout) };
  } catch {
    return { ok: true, data: { version: r.stdout.trim() } };
  }
});

ipcMain.handle('ag:antigravity:launch', async () => {
  const r = await getCliPool().run(['antigravity', 'launch', '--json']);
  try {
    return { ok: true, data: JSON.parse(r.stdout) };
  } catch {
    return { ok: true, data: { ok: r.code === 0, message: r.stdout.trim() } };
  }
});

ipcMain.handle('ag:antigravity:kill', async () => {
  const r = await getCliPool().run(['antigravity', 'kill', '--json']);
  try {
    return { ok: true, data: JSON.parse(r.stdout) };
  } catch {
    return { ok: true, data: { killed: 0, message: r.stdout.trim() } };
  }
});

ipcMain.handle('ag:antigravity:restart', async () => {
  const r = await getCliPool().run(['antigravity', 'restart', '--json']);
  try {
    return { ok: true, data: JSON.parse(r.stdout) };
  } catch {
    return { ok: true, data: { ok: r.code === 0, message: r.stdout.trim() } };
  }
});

// Launch Antigravity and immediately start streaming its language_server logs.
// Returns a unique streamId the renderer can use to receive log chunks.
ipcMain.handle('ag:antigravity:launch-logs', async (evt) => {
  const streamId = `launch-logs-${Date.now()}`;
  const cli = getCliPath();
  if (!fs.existsSync(cli)) {
    evt.sender.send(`ag:stream:${streamId}:error`, `CLI not found: ${cli}`);
    return streamId;
  }
  const proc = spawn(process.execPath, [cli, 'antigravity', 'launch-logs'], {
    env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' },
    windowsHide: true,
  });
  activeStreams.set(streamId, proc);

  let pending: { stdout: string; stderr: string } | null = null;
  let flushTimer: NodeJS.Timeout | null = null;
  const flush = () => {
    if (pending && (pending.stdout || pending.stderr)) {
      if (!evt.sender.isDestroyed()) {
        evt.sender.send(`ag:stream:${streamId}:data`, pending.stdout + pending.stderr);
      }
    }
    pending = null;
    flushTimer = null;
  };
  const schedule = () => {
    if (!flushTimer) flushTimer = setTimeout(flush, 50);
  };

  proc.stdout?.on('data', (d: Buffer) => {
    if (!pending) pending = { stdout: '', stderr: '' };
    pending.stdout += d.toString();
    schedule();
  });
  proc.stderr?.on('data', (d: Buffer) => {
    if (!pending) pending = { stdout: '', stderr: '' };
    pending.stderr += d.toString();
    schedule();
  });
  proc.on('close', (code) => {
    flush();
    if (!evt.sender.isDestroyed()) {
      evt.sender.send(`ag:stream:${streamId}:close`, code ?? 0);
    }
    activeStreams.delete(streamId);
  });
  proc.on('error', (err) => {
    if (!evt.sender.isDestroyed()) {
      evt.sender.send(`ag:stream:${streamId}:error`, err.message);
    }
    activeStreams.delete(streamId);
  });
  return streamId;
});

// ─────────────────────────────────────────────────────────────────────────────
// Installation Detector — scans for Antigravity binaries (v1.x vs v2.0+)
// Returns structured info about each installation found + process ownership
// ─────────────────────────────────────────────────────────────────────────────

interface InstallationCandidate {
  path: string;
  version: 'v1.x' | 'v2.0+' | 'unknown';
  exists: boolean;
  size?: number;
  modified?: string;
  process?: { pid: number; name: string } | null;
  portInUse?: { port: number; by: string } | null;
  recommended?: boolean;
  reason?: string;
}

ipcMain.handle('ag:detect-installation', async () => {
  const candidates: InstallationCandidate[] = [];
  const isWin = process.platform === 'win32';

  // Common locations to scan
  const searchPaths: { path: string; version: 'v1.x' | 'v2.0+' }[] = isWin
    ? [
        { path: 'C:\\Program Files\\antigravity\\Antigravity.exe', version: 'v1.x' },
        { path: 'C:\\Program Files\\Antigravity\\Antigravity.exe', version: 'v2.0+' },
        { path: path.join(process.env.LOCALAPPDATA || '', 'Programs', 'antigravity', 'Antigravity.exe'), version: 'v1.x' },
        { path: path.join(process.env.LOCALAPPDATA || '', 'Programs', 'Antigravity', 'Antigravity.exe'), version: 'v2.0+' },
        { path: path.join(process.env.USERPROFILE || '', 'AppData', 'Local', 'Programs', 'antigravity', 'Antigravity.exe'), version: 'v1.x' },
        { path: path.join(process.env.USERPROFILE || '', 'AppData', 'Local', 'Programs', 'Antigravity', 'Antigravity.exe'), version: 'v2.0+' },
      ]
    : [
        { path: '/usr/local/bin/antigravity', version: 'v1.x' },
        { path: '/opt/Antigravity/Antigravity', version: 'v2.0+' },
        { path: path.join(process.env.HOME || '', '.local', 'bin', 'antigravity'), version: 'v1.x' },
      ];

  for (const sp of searchPaths) {
    try {
      if (!fs.existsSync(sp.path)) continue;
      const stat = fs.statSync(sp.path);
      candidates.push({
        path: sp.path,
        version: sp.version,
        exists: true,
        size: stat.size,
        modified: stat.mtime.toISOString(),
      });
    } catch { /* skip */ }
  }

  // Identify running processes on Windows via tasklist
  if (isWin) {
    try {
      const { execSync } = require('child_process') as typeof import('child_process');
      const out = execSync('tasklist /FI "IMAGENAME eq Antigravity.exe" /FO CSV /NH', { encoding: 'utf-8' });
      const lines = out.trim().split('\n').filter((l) => l.includes('Antigravity'));
      for (const line of lines) {
        const m = line.match(/^"([^"]+)","(\d+)"/);
        if (m) {
          const pid = parseInt(m[2], 10);
          const cand = candidates.find((c) => c.path.toLowerCase().includes('antigravity\\antigravity.exe'));
          if (cand) cand.process = { pid, name: m[1] };
        }
      }
    } catch { /* best effort */ }
  }

  // Check main proxy port ownership
  try {
    const inUse = await isPortInUse(MAIN_PROXY_PORT);
    if (inUse) {
      const { execSync } = require('child_process') as typeof import('child_process');
      const out = execSync(`netstat -ano | findstr :${MAIN_PROXY_PORT}`, { encoding: 'utf-8' });
      const line = out.trim().split('\n')[0] || '';
      const m = line.match(/\s(\d+)\s*$/);
      const pid = m ? m[1] : 'unknown';
      // Attach to first candidate that has a process, or create a generic note
      const target = candidates.find((c) => c.process) || candidates[0];
      if (target) target.portInUse = { port: MAIN_PROXY_PORT, by: `PID ${pid}` };
    }
  } catch { /* best effort */ }

  // Recommendation: prefer v2.0+ (uppercase) since that's the user's target
  const v2 = candidates.find((c) => c.version === 'v2.0+');
  if (v2) {
    v2.recommended = true;
    v2.reason = 'Latest Antigravity 2.0+ (uppercase)';
  }
  const v1 = candidates.find((c) => c.version === 'v1.x');
  if (v1 && !v2) {
    v1.recommended = true;
    v1.reason = 'Only v1.x installation found';
  }

  return {
    ok: true,
    data: {
      candidates,
      hasConflict: candidates.length > 1,
      summary: candidates.length === 0
        ? 'No Antigravity installation detected'
        : candidates.length === 1
        ? `Single installation: ${candidates[0].version}`
        : `Multiple installations detected (${candidates.length}) — possible confusion source`,
    },
  };
});

// ─────────────────────────────────────────────────────────────────────────────
// Proxy Stats — lightweight polling endpoint for the Real-time Proxy Monitor
// ─────────────────────────────────────────────────────────────────────────────

const proxyStatsHistory: Array<{ ts: number; latencyMs: number; ok: boolean }> = [];
const PROXY_STATS_MAX = 60;

ipcMain.handle('ag:proxy-stats', async () => {
  const start = Date.now();
  try {
    const result = await new Promise<{ ok: boolean; latencyMs: number; stub: boolean; error?: string }>((resolve) => {
      const req = require('http').request(
        { hostname: '127.0.0.1', port: STUB_PORT, path: '/health', method: 'GET', timeout: 2000 },
        (res: { statusCode: number; headers: Record<string, string>; resume: () => void }) => {
          res.resume();
          resolve({
            ok: true,
            latencyMs: Date.now() - start,
            stub: res.headers['x-proxy-stub'] === '1',
          });
        },
      );
      req.on('timeout', () => { req.destroy(); resolve({ ok: false, latencyMs: 0, stub: false, error: 'timeout' }); });
      req.on('error', (err: Error) => resolve({ ok: false, latencyMs: 0, stub: false, error: err.message }));
      req.end();
    });

    proxyStatsHistory.push({ ts: Date.now(), latencyMs: result.latencyMs, ok: result.ok });
    if (proxyStatsHistory.length > PROXY_STATS_MAX) proxyStatsHistory.shift();

    return {
      ok: true,
      data: {
        current: result,
        history: [...proxyStatsHistory],
        uptime: proxyStatsHistory.length > 0 ? Date.now() - proxyStatsHistory[0].ts : 0,
      },
    };
  } catch (e) {
    return { ok: false, error: (e as Error).message };
  }
});

// ──────────────────────────────────────────���──────────────────────────────────
// Model Test — tests a single model's connection from the main process
// ─────────────────────────────────────────────────────────────────────────────

ipcMain.handle('ag:test-model', async (_evt, name: string) => {
  try {
    const r = await getCliPool().run(['models', 'test', name, '--json']);
    try {
      return { ok: true, data: JSON.parse(r.stdout) };
    } catch {
      return { ok: r.code === 0, data: { ok: r.code === 0, message: r.stdout.trim() || r.stderr.trim() } };
    }
  } catch (e) {
    return { ok: false, error: (e as Error).message };
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Proxy stub lifecycle — portable emergency proxy on 127.0.0.1:<STUB_PORT>
// (Separate from main Antigravity proxy on <MAIN_PROXY_PORT> to avoid port conflicts)
// ───────────────────────────────────────────────────────────────────────��─────

const STUB_PORT = parseInt(process.env.AG_PROXY_STUB_PORT || '51999', 10);

/**
 * Check if the main Antigravity proxy port is already in use.
 * Used to warn the user when ag-doctor-ui stub might conflict.
 */
async function isPortInUse(port: number, host = '127.0.0.1'): Promise<boolean> {
  return new Promise((resolve) => {
    const net = require('net') as typeof import('net');
    const tester = net.createServer()
      .once('error', () => resolve(true))
      .once('listening', () => tester.close(() => resolve(false)))
      .listen(port, host);
  });
}

/**
 * Launch proxy-stub.js in a detached Node.js process.
 * Works on any machine (no hardcoded paths).
 * Returns { ok, pid?, error? }
 */
ipcMain.handle('ag:proxy:start-stub', async () => {
  try {
    // Resolve the stub path relative to the project root (same dir as the CLI package.json)
    const stubPath = path.join(getCliPath(), '..', '..', '..', 'proxy-stub.js');
    const resolved = path.resolve(stubPath);
    if (!fs.existsSync(resolved)) {
      return { ok: false, error: `proxy-stub.js not found at ${resolved}` };
    }
    // Spawn detached so it survives if ag-doctor-ui is closed
    const child = spawn(process.execPath, [resolved], {
      env: { ...process.env, ELECTRON_RUN_AS_NODE: '1', AG_STUB_PORT: String(STUB_PORT) },
      detached: true,
      stdio: 'ignore',
      windowsHide: true,
    });
    child.unref();
    // Wait up to 3 s for the port to open
    const deadline = Date.now() + 3000;
    while (Date.now() < deadline) {
      await new Promise<void>((r) => setTimeout(r, 200));
      const alive = await new Promise<boolean>((resolve) => {
        const req = require('http').request(
          { hostname: '127.0.0.1', port: STUB_PORT, path: '/health', method: 'GET', timeout: 1000 },
          (res: { resume: () => void }) => { res.resume(); resolve(true); },
        );
        req.on('error', () => resolve(false));
        req.end();
      });
      if (alive) return { ok: true, pid: child.pid, port: STUB_PORT };
    }
    return { ok: true, pid: child.pid, port: STUB_PORT, note: 'started but port not yet open' };
  } catch (e) {
    return { ok: false, error: (e as Error).message };
  }
});

// NOTE: 'ag:proxy:status' handler is already registered above (line ~591) via proxyManager.getStatus().

 * Check if the main Antigravity proxy port is occupied.
 * Useful to detect conflicts when launching Antigravity.
 */
ipcMain.handle('ag:proxy:check-main-port', async () => {
  try {
    const inUse = await isPortInUse(MAIN_PROXY_PORT);
    if (inUse) {
      // Try to identify which process is using the port
      let processInfo = 'unknown';
      try {
        if (process.platform === 'win32') {
          const { execSync } = require('child_process') as typeof import('child_process');
          const out = execSync(`netstat -ano | findstr :${MAIN_PROXY_PORT}`, { encoding: 'utf-8' });
          processInfo = out.trim().split('\n')[0] || 'unknown';
        } else {
          const { execSync } = require('child_process') as typeof import('child_process');
          const out = execSync(`lsof -i :${MAIN_PROXY_PORT} -P -n 2>/dev/null | tail -n +2 | head -n 1`, { encoding: 'utf-8' });
          processInfo = out.trim() || 'unknown';
        }
      } catch {
        /* best effort */
      }
      return { ok: true, inUse: true, port: MAIN_PROXY_PORT, process: processInfo };
    }
    return { ok: true, inUse: false, port: MAIN_PROXY_PORT };
  } catch (e) {
    return { ok: false, error: (e as Error).message };
  }
});

/**
 * Kill the process occupying the main Antigravity proxy port.
 * Use with caution — only kills processes we believe are conflicting.
 */
ipcMain.handle('ag:proxy:kill-main-port', async () => {
  try {
    const { exec } = require('child_process') as typeof import('child_process');
    return await new Promise<{ ok: boolean; killed?: string; error?: string }>((resolve) => {
      let cmd: string;
      if (process.platform === 'win32') {
        cmd = `for /f "tokens=5" %a in ('netstat -ano ^| findstr :${MAIN_PROXY_PORT}') do taskkill /F /PID %a`;
      } else {
        cmd = `lsof -ti :${MAIN_PROXY_PORT} | xargs -r kill -9`;
      }
      exec(cmd, (err: Error | null, stdout: string) => {
        if (err) {
          resolve({ ok: false, error: err.message });
        } else {
          resolve({ ok: true, killed: stdout.trim() || 'no process found' });
        }
      });
    });
  } catch (e) {
    return { ok: false, error: (e as Error).message };
  }
});

/**
 * Run the repair-all script to self-elevate and fix the system proxy/CA.
 */
ipcMain.handle('ag:repair:run', async () => {
  try {
    const isWin = process.platform === 'win32';
    const scriptName = isWin ? 'repair-all.ps1' : 'repair-all.sh';
    const scriptPath = app.isPackaged
      ? path.join(process.resourcesPath, scriptName)
      : path.join(__dirname, '..', 'resources', scriptName);

    if (!fs.existsSync(scriptPath)) {
      return { ok: false, error: `Repair script not found at ${scriptPath}` };
    }

    const tempFile = isWin ? path.join(process.env.TEMP || '', 'ag-repair-result.json') : '/tmp/ag-repair-result.json';
    if (fs.existsSync(tempFile)) fs.unlinkSync(tempFile);

    await new Promise<void>((resolve, reject) => {
      let proc;
      if (isWin) {
        proc = spawn('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', `Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "${scriptPath}"' -Verb RunAs -Wait -WindowStyle Hidden`], {
          windowsHide: true,
          stdio: 'ignore'
        });
      } else {
        proc = spawn('bash', [scriptPath], {
          stdio: 'ignore'
        });
      }

      proc.on('close', (code) => {
        if (code === 0) resolve();
        else reject(new Error(`Repair script exited with code ${code}`));
      });
      proc.on('error', reject);
    });

    if (fs.existsSync(tempFile)) {
      const data = JSON.parse(fs.readFileSync(tempFile, 'utf-8'));
      fs.unlinkSync(tempFile);
      return { ok: true, ...data };
    }
    return { ok: true, proxy: false, ca: false, error: 'Result file not found' };
  } catch (e) {
    return { ok: false, error: (e as Error).message };
  }
});


// Streaming for `logs -f` — uses one-shot spawn (long-lived process), with
// chunk batching to avoid IPC flooding the renderer.
ipcMain.handle('ag:stream:start', (evt, args: string[], streamId: string) => {
  const cli = getCliPath();
  if (!fs.existsSync(cli)) {
    evt.sender.send(`ag:stream:${streamId}:error`, `CLI not found: ${cli}`);
    return false;
  }
  const proc = spawn(process.execPath, [cli, ...args], {
    env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' },
    windowsHide: true,
  });
  activeStreams.set(streamId, proc);

  // Batch chunks: flush at most every 50ms to avoid IPC storm
  let pending: { stdout: string; stderr: string } | null = null;
  let flushTimer: NodeJS.Timeout | null = null;
  const flush = () => {
    if (pending && (pending.stdout || pending.stderr)) {
      if (!evt.sender.isDestroyed()) {
        evt.sender.send(`ag:stream:${streamId}:data`, pending.stdout + pending.stderr);
      }
    }
    pending = null;
    flushTimer = null;
  };
  const schedule = () => {
    if (!flushTimer) flushTimer = setTimeout(flush, 50);
  };

  proc.stdout?.on('data', (d: Buffer) => {
    if (!pending) pending = { stdout: '', stderr: '' };
    pending.stdout += d.toString();
    schedule();
  });
  proc.stderr?.on('data', (d: Buffer) => {
    if (!pending) pending = { stdout: '', stderr: '' };
    pending.stderr += d.toString();
    schedule();
  });
  proc.on('close', (code) => {
    flush();
    if (!evt.sender.isDestroyed()) {
      evt.sender.send(`ag:stream:${streamId}:close`, code ?? 0);
    }
    activeStreams.delete(streamId);
  });
  proc.on('error', (err) => {
    if (!evt.sender.isDestroyed()) {
      evt.sender.send(`ag:stream:${streamId}:error`, err.message);
    }
    activeStreams.delete(streamId);
  });
  return true;
});

ipcMain.handle('ag:stream:cancel', (_evt, streamId: string) => {
  const proc = activeStreams.get(streamId);
  if (proc) {
    proc.kill();
    activeStreams.delete(streamId);
    return true;
  }
  return false;
});

// ─────────────────────────────────────────────────────────────────────────────

// F-28: only proceed if we own the single-instance lock
// DISABLED FOR DEVELOPMENT - app will start without lock check
app.whenReady().then(() => {
  createWindow();
  createTray();

  // Global shortcuts
  mainWindow?.webContents.on('before-input-event', (_e, input) => {
    if (input.control && input.key.toLowerCase() === 'r') {
      mainWindow?.webContents.send('ag:run-doctor');
    } else if (input.control && input.key.toLowerCase() === 'l') {
      mainWindow?.webContents.send('ag:navigate', 'logs');
    } else if (input.control && input.key.toLowerCase() === 'k') {
      mainWindow?.webContents.send('ag:command-palette');
    } else if (input.control && input.key.toLowerCase() === ',') {
      mainWindow?.webContents.send('ag:navigate', 'settings');
    }
  });

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
    else mainWindow?.show();
  });
});


app.on('window-all-closed', () => {
  for (const proc of activeStreams.values()) proc.kill();
  activeStreams.clear();
  cliPool?.shutdown();
  
  // Cleanup proxy server
  try {
    getProxyManager().cleanup();
  } catch (err) {
    console.error('[App] Failed to cleanup proxy manager:', err);
  }
  
  if (process.platform !== 'darwin') app.quit();
});

app.on('web-contents-created', (_e, contents) => {
  contents.on('will-navigate', (event, url) => {
    const parsed = new URL(url);
    if (parsed.protocol !== 'file:') {
      event.preventDefault();
      shell.openExternal(url);
    }
  });
});
