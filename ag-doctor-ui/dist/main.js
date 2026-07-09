"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
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
const electron_1 = require("electron");
const path_1 = __importDefault(require("path"));
const child_process_1 = require("child_process");
const fs_1 = __importDefault(require("fs"));
const isDev = !electron_1.app.isPackaged;
const isProd = !isDev;
let mainWindow = null;
let tray = null;
const activeStreams = new Map();
// Disable GPU sandbox in packaged builds to avoid startup crashes on some Windows setups
electron_1.app.commandLine.appendSwitch('disable-gpu');
electron_1.app.commandLine.appendSwitch('no-sandbox');
electron_1.app.commandLine.appendSwitch('disable-software-rasterizer');
// ─────────────────────────────────────────────────────────────────────────────
// Cached paths (computed once)
// ─────────────────────────────────────────────────────────────────────────────
let _assetsPath = null;
let _cliPath = null;
let _configPath = null;
function getAssetsPath() {
    if (_assetsPath === null) {
        _assetsPath = electron_1.app.isPackaged
            ? path_1.default.join(process.resourcesPath, 'assets')
            : path_1.default.join(__dirname, '..', '..', 'assets');
    }
    return _assetsPath;
}
function getCliPath() {
    if (_cliPath === null) {
        if (electron_1.app.isPackaged) {
            // In a packaged portable build, the CLI is bundled in extraResources
            // at <resources>/ag-doctor/bin/ag-doctor.js
            _cliPath = path_1.default.join(process.resourcesPath, 'ag-doctor', 'bin', 'ag-doctor.js');
        }
        else {
            _cliPath = path_1.default.join(__dirname, '..', '..', 'ag-doctor', 'bin', 'ag-doctor.js');
        }
    }
    return _cliPath;
}
function getConfigPath() {
    if (_configPath === null) {
        _configPath = path_1.default.join(electron_1.app.getPath('home'), '.gemini', 'antigravity', 'config.json');
    }
    return _configPath;
}
// ─────────────────────────────────────────────────────────────────────────────
// Cached tray icons
// ─────────────────────────────────────────────────────────────────────────────
const trayIconCache = new Map();
function getTrayIcon(status) {
    const cached = trayIconCache.get(status);
    if (cached)
        return cached;
    const svgPath = path_1.default.join(getAssetsPath(), `tray-${status}.svg`);
    let img;
    if (fs_1.default.existsSync(svgPath)) {
        img = electron_1.nativeImage.createFromPath(svgPath).resize({ width: 16, height: 16 });
    }
    else {
        const fallback = path_1.default.join(getAssetsPath(), 'icon.svg');
        if (fs_1.default.existsSync(fallback)) {
            img = electron_1.nativeImage.createFromPath(fallback).resize({ width: 16, height: 16 });
        }
        else {
            img = electron_1.nativeImage.createFromPath(svgPath);
        }
    }
    trayIconCache.set(status, img);
    return img;
}
function readUiTheme() {
    try {
        const raw = fs_1.default.readFileSync(getConfigPath(), 'utf-8');
        const cfg = JSON.parse(raw);
        return cfg?.ui?.theme === 'light' ? 'light' : 'dark';
    }
    catch {
        return 'dark';
    }
}
// ─────────────────────────────────────────────────────────────────────────────
// Cached IPC payloads — eliminate redundant disk reads and object construction
// ─────────────────────────────────────────────────────────────────────────────
// `info` is static for the session lifetime (platform/versions/CLI path don't change)
const infoCache = {
    platform: process.platform,
    arch: process.arch,
    versions: process.versions,
    electron: process.versions.electron,
    node: process.versions.node,
    chrome: process.versions.chrome,
    cliPath: '', // populated lazily by getCliPath()
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
let configCache = null;
function getConfigPayload() {
    if (configCache)
        return configCache;
    try {
        const raw = fs_1.default.readFileSync(getConfigPath(), 'utf-8');
        configCache = JSON.parse(raw);
    }
    catch {
        configCache = { ui: { theme: 'dark' } };
    }
    return configCache;
}
function invalidateConfigCache() {
    configCache = null;
}
function updateTray(status) {
    if (!tray)
        return;
    tray.setImage(getTrayIcon(status));
    tray.setToolTip(`ag-doctor · ${status.toUpperCase()}`);
}
function buildTrayMenu() {
    return electron_1.Menu.buildFromTemplate([
        {
            label: 'Open dashboard',
            click: () => {
                if (mainWindow) {
                    mainWindow.show();
                    mainWindow.focus();
                }
                else {
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
        {
            label: 'Quit',
            click: () => {
                electron_1.app.quit();
            },
        },
    ]);
}
function createTray() {
    tray = new electron_1.Tray(getTrayIcon('ok'));
    tray.setToolTip('ag-doctor');
    tray.setContextMenu(buildTrayMenu());
    tray.on('click', () => {
        if (mainWindow) {
            mainWindow.show();
            mainWindow.focus();
        }
        else {
            createWindow();
        }
    });
}
function createWindow() {
    mainWindow = new electron_1.BrowserWindow({
        width: 1280,
        height: 820,
        minWidth: 960,
        minHeight: 640,
        backgroundColor: '#0a0e1a',
        titleBarStyle: 'hidden',
        titleBarOverlay: {
            color: '#0a0e1a',
            symbolColor: '#e8eef9',
            height: 36,
        },
        show: false,
        webPreferences: {
            preload: path_1.default.join(__dirname, 'preload.js'),
            contextIsolation: true,
            nodeIntegration: false,
            sandbox: false,
            spellcheck: false,
            backgroundThrottling: false,
        },
    });
    mainWindow.loadFile(path_1.default.join(__dirname, 'renderer', 'index.html'));
    mainWindow.once('ready-to-show', () => {
        mainWindow?.show();
    });
    setTimeout(() => {
        if (mainWindow && !mainWindow.isVisible()) {
            mainWindow.show();
        }
    }, 2000);
    mainWindow.webContents.on('did-fail-load', (_e, code, desc, url) => {
        console.error(`[main] did-fail-load: ${code} ${desc} ${url}`);
    });
    mainWindow.webContents.on('render-process-gone', (_e, details) => {
        console.error(`[main] render-process-gone: ${JSON.stringify(details)}`);
    });
    // Only forward console messages in dev mode (saves IPC overhead in prod)
    if (isDev) {
        mainWindow.webContents.on('console-message', (_e, level, message) => {
            console.log(`[renderer] ${message}`);
        });
    }
    mainWindow.webContents.setWindowOpenHandler(({ url }) => {
        electron_1.shell.openExternal(url);
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
class CliWorkerPool {
    workers = [];
    maxWorkers = 3;
    cliPath;
    nextId = 1;
    waitQueue = [];
    constructor(cliPath) {
        this.cliPath = cliPath;
    }
    spawnWorker() {
        if (!fs_1.default.existsSync(this.cliPath))
            return null;
        const proc = (0, child_process_1.spawn)(process.execPath, [this.cliPath, '--worker'], {
            env: { ...process.env, ELECTRON_RUN_AS_NODE: '1', AG_WORKER_ID: String(this.nextId++) },
            windowsHide: true,
            stdio: ['pipe', 'pipe', 'pipe'],
        });
        const worker = { proc, busy: false, pending: null, buffer: '', errBuffer: '' };
        proc.stdout?.on('data', (chunk) => this.handleData(worker, chunk));
        proc.stderr?.on('data', (chunk) => { worker.errBuffer += chunk.toString(); }); // don't mix into JSON protocol
        proc.on('close', () => this.handleClose(worker));
        proc.on('error', (err) => this.handleError(worker, err));
        this.workers.push(worker);
        return worker;
    }
    handleData(worker, chunk, _isStderr = false) {
        worker.buffer += chunk.toString();
        // Newline-delimited JSON protocol
        let idx;
        while ((idx = worker.buffer.indexOf('\n')) >= 0) {
            const line = worker.buffer.slice(0, idx);
            worker.buffer = worker.buffer.slice(idx + 1);
            if (!line)
                continue;
            if (worker.pending) {
                try {
                    const msg = JSON.parse(line);
                    worker.pending.resolve({
                        code: msg.code ?? 0,
                        stdout: msg.stdout ?? '',
                        stderr: msg.stderr ?? '',
                    });
                }
                catch {
                    worker.pending.resolve({ code: 0, stdout: line, stderr: '' });
                }
                worker.pending = null;
                worker.busy = false;
                this.dispatchNext();
            }
        }
    }
    handleClose(worker) {
        if (worker.pending) {
            worker.pending.reject(new Error('CLI worker closed unexpectedly'));
            worker.pending = null;
        }
        worker.busy = false;
        const idx = this.workers.indexOf(worker);
        if (idx >= 0)
            this.workers.splice(idx, 1);
        this.dispatchNext();
    }
    handleError(worker, err) {
        if (worker.pending) {
            worker.pending.reject(err);
            worker.pending = null;
        }
        worker.busy = false;
    }
    dispatchNext() {
        if (this.waitQueue.length === 0)
            return;
        const idle = this.workers.find((w) => !w.busy);
        if (!idle)
            return;
        const next = this.waitQueue.shift();
        this.runOn(idle, next.args).then(next.resolve).catch(next.reject);
    }
    async runOn(worker, args) {
        return new Promise((resolve, reject) => {
            worker.busy = true;
            worker.pending = { resolve, reject };
            try {
                worker.proc.stdin?.write(JSON.stringify({ args }) + '\n');
            }
            catch (err) {
                worker.pending = null;
                worker.busy = false;
                reject(err);
            }
        });
    }
    async run(args) {
        if (!fs_1.default.existsSync(this.cliPath)) {
            return { code: -1, stdout: '', stderr: `CLI not found: ${this.cliPath}` };
        }
        // Try to find an idle worker
        const idle = this.workers.find((w) => !w.busy);
        if (idle) {
            return this.runOn(idle, args);
        }
        // Spawn a new worker if under cap
        if (this.workers.length < this.maxWorkers) {
            const w = this.spawnWorker();
            if (w)
                return this.runOn(w, args);
        }
        // Queue
        return new Promise((resolve, reject) => {
            this.waitQueue.push({ args, resolve, reject });
        });
    }
    shutdown() {
        for (const w of this.workers) {
            try {
                w.proc.stdin?.end();
            }
            catch { /* ignore */ }
            try {
                w.proc.kill();
            }
            catch { /* ignore */ }
        }
        this.workers = [];
        this.waitQueue.length = 0;
    }
}
let cliPool = null;
function getCliPool() {
    if (!cliPool)
        cliPool = new CliWorkerPool(getCliPath());
    return cliPool;
}
// ──────────────────────────────────────────────���──────────────────────────────
// IPC handlers
// ─────────────────────────────────────────────────────────────────────────────
electron_1.ipcMain.handle('ag:run', async (_evt, args) => {
    return getCliPool().run(args);
});
electron_1.ipcMain.handle('ag:info', async () => {
    return getInfoPayload();
});
electron_1.ipcMain.handle('ag:config', async () => {
    return getConfigPayload();
});
electron_1.ipcMain.handle('ag:config:set-theme', async (_evt, theme) => {
    try {
        const cfgPath = getConfigPath();
        let cfg = {};
        if (fs_1.default.existsSync(cfgPath)) {
            cfg = JSON.parse(fs_1.default.readFileSync(cfgPath, 'utf-8'));
        }
        cfg.ui = { ...(typeof cfg.ui === 'object' && cfg.ui !== null ? cfg.ui : {}), theme };
        fs_1.default.mkdirSync(path_1.default.dirname(cfgPath), { recursive: true });
        fs_1.default.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2) + '\n');
        // Refresh cache so the next ag:config call returns the new theme immediately
        configCache = cfg;
        mainWindow?.webContents.send('ag:theme-changed', theme);
        return true;
    }
    catch {
        return false;
    }
});
electron_1.ipcMain.handle('ag:notify', async (_evt, title, body) => {
    if (electron_1.Notification.isSupported()) {
        new electron_1.Notification({ title, body }).show();
    }
});
electron_1.ipcMain.handle('ag:tray-status', async (_evt, status) => {
    updateTray(status);
});
electron_1.ipcMain.handle('ag:open-external', async (_evt, url) => {
    await electron_1.shell.openExternal(url);
});
electron_1.ipcMain.handle('ag:reveal', async (_evt, p) => {
    electron_1.shell.showItemInFolder(p);
});
// Antigravity lifecycle: thin wrappers around the CLI's `antigravity` subcommand.
// The CLI returns JSON when invoked with --json, so we forward the parsed payload.
electron_1.ipcMain.handle('ag:antigravity:status', async () => {
    const r = await getCliPool().run(['antigravity', 'status', '--json']);
    if (r.code !== 0 && r.code !== 1) {
        return { ok: false, error: r.stderr || r.stdout || `exit ${r.code}` };
    }
    try {
        return { ok: true, data: JSON.parse(r.stdout) };
    }
    catch (e) {
        return { ok: false, error: `parse failed: ${e.message}` };
    }
});
electron_1.ipcMain.handle('ag:antigravity:version', async () => {
    const r = await getCliPool().run(['antigravity', 'version', '--json']);
    try {
        return { ok: true, data: JSON.parse(r.stdout) };
    }
    catch {
        return { ok: true, data: { version: r.stdout.trim() } };
    }
});
electron_1.ipcMain.handle('ag:antigravity:launch', async () => {
    const r = await getCliPool().run(['antigravity', 'launch', '--json']);
    try {
        return { ok: true, data: JSON.parse(r.stdout) };
    }
    catch {
        return { ok: true, data: { ok: r.code === 0, message: r.stdout.trim() } };
    }
});
electron_1.ipcMain.handle('ag:antigravity:kill', async () => {
    const r = await getCliPool().run(['antigravity', 'kill', '--json']);
    try {
        return { ok: true, data: JSON.parse(r.stdout) };
    }
    catch {
        return { ok: true, data: { killed: 0, message: r.stdout.trim() } };
    }
});
electron_1.ipcMain.handle('ag:antigravity:restart', async () => {
    const r = await getCliPool().run(['antigravity', 'restart', '--json']);
    try {
        return { ok: true, data: JSON.parse(r.stdout) };
    }
    catch {
        return { ok: true, data: { ok: r.code === 0, message: r.stdout.trim() } };
    }
});
// ─────────────────────────────────────────────────────────────────────────────
// Proxy stub lifecycle — portable emergency proxy on 127.0.0.1:50999
// ─────────────────────────────────────────────────────────────────────────────
/**
 * Launch proxy-stub.js in a detached Node.js process.
 * Works on any machine (no hardcoded paths).
 * Returns { ok, pid?, error? }
 */
electron_1.ipcMain.handle('ag:proxy:start-stub', async () => {
    try {
        // Resolve the stub path relative to the project root (same dir as the CLI package.json)
        const stubPath = path_1.default.join(getCliPath(), '..', '..', '..', 'proxy-stub.js');
        const resolved = path_1.default.resolve(stubPath);
        if (!fs_1.default.existsSync(resolved)) {
            return { ok: false, error: `proxy-stub.js not found at ${resolved}` };
        }
        // Spawn detached so it survives if ag-doctor-ui is closed
        const child = (0, child_process_1.spawn)(process.execPath, [resolved], {
            env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' },
            detached: true,
            stdio: 'ignore',
            windowsHide: true,
        });
        child.unref();
        // Wait up to 3 s for the port to open
        const port = 50999;
        const deadline = Date.now() + 3000;
        while (Date.now() < deadline) {
            await new Promise((r) => setTimeout(r, 200));
            const alive = await new Promise((resolve) => {
                const req = require('http').request({ hostname: '127.0.0.1', port, path: '/health', method: 'GET', timeout: 1000 }, (res) => { res.resume(); resolve(true); });
                req.on('error', () => resolve(false));
                req.end();
            });
            if (alive)
                return { ok: true, pid: child.pid };
        }
        return { ok: true, pid: child.pid, note: 'started but port not yet open' };
    }
    catch (e) {
        return { ok: false, error: e.message };
    }
});
/**
 * Check proxy health and detect stub vs real proxy.
 */
electron_1.ipcMain.handle('ag:proxy:status', async () => {
    try {
        const port = 50999;
        const result = await new Promise((resolve) => {
            const started = Date.now();
            const req = require('http').request({ hostname: '127.0.0.1', port, path: '/health', method: 'GET', timeout: 2000 }, (res) => {
                res.resume();
                resolve({
                    ok: true,
                    stub: res.headers['x-proxy-stub'] === '1',
                    latencyMs: Date.now() - started,
                });
            });
            req.on('timeout', () => { req.destroy(); resolve({ ok: false, stub: false, latencyMs: Date.now() - Date.now(), error: 'timeout' }); });
            req.on('error', (err) => resolve({ ok: false, stub: false, latencyMs: 0, error: err.message }));
            req.end();
        });
        return { ok: true, data: result };
    }
    catch (e) {
        return { ok: false, error: e.message };
    }
});
/**
 * Run the repair-all script to self-elevate and fix the system proxy/CA.
 */
electron_1.ipcMain.handle('ag:repair:run', async () => {
    try {
        const isWin = process.platform === 'win32';
        const scriptName = isWin ? 'repair-all.ps1' : 'repair-all.sh';
        const scriptPath = electron_1.app.isPackaged
            ? path_1.default.join(process.resourcesPath, scriptName)
            : path_1.default.join(__dirname, '..', 'resources', scriptName);
        if (!fs_1.default.existsSync(scriptPath)) {
            return { ok: false, error: `Repair script not found at ${scriptPath}` };
        }
        const tempFile = isWin ? path_1.default.join(process.env.TEMP || '', 'ag-repair-result.json') : '/tmp/ag-repair-result.json';
        if (fs_1.default.existsSync(tempFile))
            fs_1.default.unlinkSync(tempFile);
        await new Promise((resolve, reject) => {
            let proc;
            if (isWin) {
                proc = (0, child_process_1.spawn)('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', `Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "${scriptPath}"' -Verb RunAs -Wait -WindowStyle Hidden`], {
                    windowsHide: true,
                    stdio: 'ignore'
                });
            }
            else {
                proc = (0, child_process_1.spawn)('bash', [scriptPath], {
                    stdio: 'ignore'
                });
            }
            proc.on('close', (code) => {
                if (code === 0)
                    resolve();
                else
                    reject(new Error(`Repair script exited with code ${code}`));
            });
            proc.on('error', reject);
        });
        if (fs_1.default.existsSync(tempFile)) {
            const data = JSON.parse(fs_1.default.readFileSync(tempFile, 'utf-8'));
            fs_1.default.unlinkSync(tempFile);
            return { ok: true, ...data };
        }
        return { ok: true, proxy: false, ca: false, error: 'Result file not found' };
    }
    catch (e) {
        return { ok: false, error: e.message };
    }
});
// Streaming for `logs -f` — uses one-shot spawn (long-lived process), with
// chunk batching to avoid IPC flooding the renderer.
electron_1.ipcMain.handle('ag:stream:start', (evt, args, streamId) => {
    const cli = getCliPath();
    if (!fs_1.default.existsSync(cli)) {
        evt.sender.send(`ag:stream:${streamId}:error`, `CLI not found: ${cli}`);
        return false;
    }
    const proc = (0, child_process_1.spawn)(process.execPath, [cli, ...args], {
        env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' },
        windowsHide: true,
    });
    activeStreams.set(streamId, proc);
    // Batch chunks: flush at most every 50ms to avoid IPC storm
    let pending = null;
    let flushTimer = null;
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
        if (!flushTimer)
            flushTimer = setTimeout(flush, 50);
    };
    proc.stdout?.on('data', (d) => {
        if (!pending)
            pending = { stdout: '', stderr: '' };
        pending.stdout += d.toString();
        schedule();
    });
    proc.stderr?.on('data', (d) => {
        if (!pending)
            pending = { stdout: '', stderr: '' };
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
electron_1.ipcMain.handle('ag:stream:cancel', (_evt, streamId) => {
    const proc = activeStreams.get(streamId);
    if (proc) {
        proc.kill();
        activeStreams.delete(streamId);
        return true;
    }
    return false;
});
// ─────────────────────────────────────────────────────────────────────────────
electron_1.app.whenReady().then(() => {
    createWindow();
    createTray();
    // Global shortcuts
    mainWindow?.webContents.on('before-input-event', (_e, input) => {
        if (input.control && input.key.toLowerCase() === 'r') {
            mainWindow?.webContents.send('ag:run-doctor');
        }
        else if (input.control && input.key.toLowerCase() === 'l') {
            mainWindow?.webContents.send('ag:navigate', 'logs');
        }
        else if (input.control && input.key.toLowerCase() === 'k') {
            mainWindow?.webContents.send('ag:command-palette');
        }
        else if (input.control && input.key.toLowerCase() === ',') {
            mainWindow?.webContents.send('ag:navigate', 'settings');
        }
    });
    electron_1.app.on('activate', () => {
        if (electron_1.BrowserWindow.getAllWindows().length === 0)
            createWindow();
        else
            mainWindow?.show();
    });
});
electron_1.app.on('window-all-closed', () => {
    for (const proc of activeStreams.values())
        proc.kill();
    activeStreams.clear();
    cliPool?.shutdown();
    if (process.platform !== 'darwin')
        electron_1.app.quit();
});
electron_1.app.on('web-contents-created', (_e, contents) => {
    contents.on('will-navigate', (event, url) => {
        const parsed = new URL(url);
        if (parsed.protocol !== 'file:') {
            event.preventDefault();
            electron_1.shell.openExternal(url);
        }
    });
});
//# sourceMappingURL=main.js.map