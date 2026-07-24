"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.registerIpcHandlers = registerIpcHandlers;
const electron_1 = require("electron");
const electron_updater_1 = require("electron-updater");
const updater_1 = require("./updater");
const main_1 = __importDefault(require("electron-log/main"));
const fs = __importStar(require("fs/promises"));
const path = __importStar(require("path"));
const http = __importStar(require("http"));
const https = __importStar(require("https"));
const customScheme_1 = require("./customScheme");
const tray_1 = require("./tray");
// eslint-disable-next-line @typescript-eslint/no-var-requires
const cryptoStore = require('./cryptoStore');
const customModelStore = __importStar(require("./customModelStore"));
/**
 * Registers all IPC handlers for the main process.
 */
function registerIpcHandlers(storageManager) {
    // Dialog
    electron_1.ipcMain.handle('dialog:open-workspace', async () => {
        const result = await electron_1.dialog.showOpenDialog({
            properties: ['openDirectory', 'createDirectory'],
            title: 'Open workspace',
        });
        if (result.canceled || result.filePaths.length === 0) {
            return undefined;
        }
        return result.filePaths[0];
    });
    // Auto-updater
    electron_1.ipcMain.handle('updater:apply', async () => {
        (0, updater_1.broadcastState)({ type: 'ready' });
    });
    electron_1.ipcMain.handle('updater:quit-and-install', () => {
        if (!electron_1.app.isPackaged) {
            console.log('[AutoUpdater] Skipping quitAndInstall (requires a packaged app).');
            return;
        }
        electron_updater_1.autoUpdater.quitAndInstall();
    });
    // Notifications
    electron_1.ipcMain.handle('notification:send', (_event, options) => {
        const notification = new electron_1.Notification({
            title: options.title,
            body: options.body,
            silent: options.silent ?? false,
        });
        notification.on('click', () => {
            const win = electron_1.BrowserWindow.getAllWindows()[0];
            if (win) {
                if (win.isMinimized()) {
                    win.restore();
                }
                win.show();
                win.focus();
                if (options.payload) {
                    win.webContents.send('notification:clicked', options.payload);
                }
            }
        });
        notification.show();
    });
    // Note: copied from our desktop AGY implementation:
    // vs/platform/nativeNotification/electron-main/electronNotificationService.ts
    electron_1.ipcMain.handle('notification:open-system-preferences', async () => {
        if (process.platform === 'darwin') {
            void electron_1.shell.openExternal('x-apple.systempreferences:com.apple.preference.notifications');
        }
        else if (process.platform === 'win32') {
            void electron_1.shell.openExternal('ms-settings:notifications');
        }
        else if (process.platform === 'linux') {
            const { exec } = await Promise.resolve().then(() => __importStar(require('child_process')));
            const commands = [
                'gnome-control-center notifications',
                'systemsettings kcm_notifications',
                'xfce4-notifyd-config',
                'gnome-control-center',
                'systemsettings',
            ];
            for (const command of commands) {
                try {
                    exec(command);
                    return; // If one command executes without immediate error, assume success for now
                }
                catch {
                    // Try next
                }
            }
        }
    });
    // Storage
    electron_1.ipcMain.handle('storage:get-items', async () => {
        return storageManager.getItems();
    });
    electron_1.ipcMain.handle('storage:update-items', async (_event, changes) => {
        await storageManager.updateItems(changes);
    });
    electron_1.ipcMain.handle('storage:get-custom-models', async () => {
        // Unmasked version for preload.ts injection
        return await customModelStore.loadCustomModels();
    });
    electron_1.ipcMain.handle('storage:get-providers', async () => {
        const providers = await customModelStore.loadProviders();
        return providers.map(p => ({
            ...p,
            apiKey: customModelStore.maskApiKey(p.apiKey)
        }));
    });
    electron_1.ipcMain.handle('storage:save-provider', async (_event, newProvider) => {
        try {
            const providers = await customModelStore.loadProviders();
            const existingIdx = providers.findIndex((p) => p.id === newProvider.id);
            // Decide the effective API key value to persist.
            // - 'none' or empty means the user explicitly cleared the key.
            // - Anything matching a masked shape means the field is untouched; preserve existing.
            // - Otherwise treat as a new plaintext value and encrypt.
            const rawKey = newProvider.apiKey;
            const isExplicitClear = !rawKey || rawKey === 'none' || rawKey === '';
            const isMasked = !isExplicitClear && (rawKey.includes('...') || rawKey.startsWith('***') || rawKey === '********');
            if (isExplicitClear) {
                newProvider.apiKey = 'none';
                newProvider.encrypted = false;
            }
            else if (isMasked && existingIdx !== -1) {
                newProvider.apiKey = providers[existingIdx].apiKey;
                newProvider.encrypted = providers[existingIdx].encrypted;
            }
            else {
                const enc = customModelStore.encryptApiKeyIfNeeded(rawKey);
                newProvider.apiKey = enc.apiKey;
                newProvider.encrypted = enc.encrypted;
            }
            // Validate URL
            try {
                const u = new URL(newProvider.apiUrl);
                if (!/^https?:$/.test(u.protocol)) {
                    return { success: false, error: 'API URL must use http or https' };
                }
            }
            catch {
                return { success: false, error: 'Invalid API URL' };
            }
            if (existingIdx !== -1) {
                providers[existingIdx] = newProvider;
            }
            else {
                providers.push(newProvider);
            }
            await customModelStore.saveProviders(providers);
            return { success: true };
        }
        catch (err) {
            console.error('[IPC] Failed to save provider:', err);
            return { success: false, error: err.message };
        }
    });
    electron_1.ipcMain.handle('storage:delete-provider', async (_event, providerId) => {
        try {
            const providers = await customModelStore.loadProviders();
            const filtered = providers.filter((p) => p.id !== providerId);
            await customModelStore.saveProviders(filtered);
            return { success: true };
        }
        catch (err) {
            console.error('[IPC] Failed to delete provider:', err);
            return { success: false, error: err.message };
        }
    });
    electron_1.ipcMain.handle('storage:export-providers', async () => {
        try {
            const providers = await customModelStore.loadProviders();
            const saveResult = await electron_1.dialog.showSaveDialog({
                title: 'Export Provider Configuration',
                defaultPath: 'antigravity_providers.json',
                filters: [{ name: 'JSON Files', extensions: ['json'] }],
            });
            if (saveResult.canceled || !saveResult.filePath) {
                return { success: false, error: 'Cancelled' };
            }
            await fs.writeFile(saveResult.filePath, JSON.stringify({ providers }, null, 2), 'utf-8');
            return { success: true, count: providers.length };
        }
        catch (err) {
            return { success: false, error: err.message };
        }
    });
    electron_1.ipcMain.handle('storage:get-doctor-diagnostics', async () => {
        try {
            const providers = await customModelStore.loadProviders();
            const customModels = await customModelStore.loadCustomModels();
            let activePort = 50999;
            try {
                const home = process.env.HOME || process.env.USERPROFILE || require('os').homedir();
                const portFile = path.join(home, '.gemini', 'antigravity', '.proxy_port');
                const content = await fs.readFile(portFile, 'utf-8');
                activePort = parseInt(content.trim(), 10) || 50999;
            }
            catch {
                /* default port */
            }
            const activeProviders = providers.filter((p) => p.enabled);
            const totalTokens = providers.reduce((acc, p) => acc + (p.usage?.promptTokens || 0) + (p.usage?.completionTokens || 0), 0);
            const totalRequests = providers.reduce((acc, p) => acc + (p.usage?.totalRequests || 0), 0);
            return {
                success: true,
                proxyPort: activePort,
                providersCount: providers.length,
                activeProvidersCount: activeProviders.length,
                customModelsCount: customModels.length,
                totalTokens,
                totalRequests,
                providers: providers.map((p) => ({
                    id: p.id,
                    name: p.name,
                    provider: p.provider,
                    enabled: p.enabled,
                    modelCount: p.models.length,
                    enabledModelCount: p.models.filter((m) => m.enabled).length,
                    usage: p.usage,
                })),
            };
        }
        catch (err) {
            return { success: false, error: err.message };
        }
    });
    electron_1.ipcMain.handle('storage:save-custom-model', async (_event, newModel) => {
        try {
            const models = await customModelStore.loadCustomModels();
            const existingIdx = models.findIndex((m) => m.name === newModel.name);
            const isMasked = newModel.apiKey &&
                (newModel.apiKey.includes('...') || newModel.apiKey.startsWith('***') || newModel.apiKey === '********');
            if (isMasked && existingIdx !== -1) {
                newModel.apiKey = models[existingIdx].apiKey;
                newModel.encrypted = models[existingIdx].encrypted;
            }
            else if (newModel.apiKey && newModel.apiKey !== 'none') {
                newModel.apiKey = cryptoStore.encryptString(newModel.apiKey);
                newModel.encrypted = true;
            }
            if (existingIdx !== -1) {
                models[existingIdx] = newModel;
            }
            else {
                models.push(newModel);
            }
            await customModelStore.saveCustomModels(models);
            return { success: true };
        }
        catch (err) {
            console.error('[IPC] Failed to save custom model:', err);
            return { success: false, error: err.message };
        }
    });
    electron_1.ipcMain.handle('storage:delete-custom-model', async (_event, modelName) => {
        try {
            await customModelStore.deleteCustomModel(modelName);
            return { success: true };
        }
        catch (err) {
            console.error('[IPC] Failed to delete custom model:', err);
            return { success: false, error: err.message };
        }
    });
    // P3-17: Test model connectivity — sends a lightweight HEAD/GET to the model endpoint
    electron_1.ipcMain.handle('storage:test-model-connection', async (_event, model) => {
        // eslint-disable-next-line @typescript-eslint/no-var-requires
        const https = require('https');
        // eslint-disable-next-line @typescript-eslint/no-var-requires
        const http = require('http');
        return new Promise((resolve) => {
            try {
                let urlStr = model.apiUrl || '';
                if (!urlStr) {
                    resolve({ success: false, error: 'No API URL provided' });
                    return;
                }
                const providerLower = (model.provider || '').toLowerCase();
                // Normalize URL for chat API endpoints
                if (providerLower === 'openai' || providerLower === 'custom' || providerLower === 'ollama') {
                    const urlLower = urlStr.toLowerCase();
                    if (!urlLower.includes('/chat/completions') && !urlLower.includes('/completions')) {
                        if (urlStr.endsWith('/v1')) {
                            urlStr += '/chat/completions';
                        }
                        else if (!urlStr.endsWith('/')) {
                            urlStr += '/v1/chat/completions';
                        }
                        else {
                            urlStr += 'v1/chat/completions';
                        }
                    }
                }
                const url = new URL(urlStr);
                const client = url.protocol === 'https:' ? https : http;
                const options = {
                    method: 'HEAD',
                    hostname: url.hostname,
                    port: parseInt(url.port || (url.protocol === 'https:' ? '443' : '80'), 10),
                    path: url.pathname + url.search,
                    timeout: 10000,
                    rejectUnauthorized: !model.allowUnauthorized,
                };
                // Add auth header
                if (model.apiKey && model.apiKey !== 'none') {
                    let key = model.apiKey;
                    try {
                        key = cryptoStore.decryptString(model.apiKey);
                    }
                    catch {
                        /* key might not be encrypted */
                    }
                    if (model.provider === 'anthropic') {
                        options.headers = {
                            'x-api-key': key,
                            'anthropic-version': '2025-04-01',
                        };
                    }
                    else if (model.provider === 'google') {
                        options.headers = {
                            'x-goog-api-key': key,
                        };
                    }
                    else {
                        options.headers = {
                            Authorization: `Bearer ${key}`,
                        };
                    }
                }
                const startTime = Date.now();
                const getLatency = () => Math.round(Date.now() - startTime);
                const req = client.request(options);
                req.on('response', (res) => {
                    // Distinguish auth failures (401/403) from network reachable.
                    if (res.statusCode === 401 || res.statusCode === 403) {
                        res.resume();
                        resolve({ success: false, status: res.statusCode, error: `Authentication failed (HTTP ${res.statusCode})`, latencyMs: getLatency() });
                        return;
                    }
                    if (!res.statusCode || res.statusCode < 200 || res.statusCode >= 500) {
                        res.resume();
                        resolve({ success: false, status: res.statusCode, error: `HTTP ${res.statusCode}`, latencyMs: getLatency() });
                        return;
                    }
                    let body = '';
                    let bytes = 0;
                    const MAX_BODY = 256 * 1024;
                    res.on('data', (chunk) => {
                        bytes += chunk.length;
                        if (bytes > MAX_BODY) {
                            req.destroy();
                            resolve({ success: false, error: 'Response too large', latencyMs: getLatency() });
                            return;
                        }
                        body += chunk.toString();
                    });
                    res.on('end', () => {
                        const ok = res.statusCode !== undefined && res.statusCode >= 200 && res.statusCode < 400;
                        resolve({ success: ok, status: res.statusCode, message: `HTTP ${res.statusCode}`, latencyMs: getLatency() });
                    });
                });
                req.setTimeout(10000, () => {
                    req.destroy();
                    resolve({ success: false, error: 'Request timed out', latencyMs: getLatency() });
                });
                req.on('error', (err) => {
                    let message = err.message;
                    if (message.includes('ECONNREFUSED')) {
                        message = 'Connection refused — server may not be running';
                    }
                    else if (message.includes('ENOTFOUND') || message.includes('getaddrinfo')) {
                        message = 'Host not found — check the API URL';
                    }
                    else if (message.includes('CERT') || message.includes('certificate') || message.includes('SSL')) {
                        message = 'SSL/TLS error — try enabling "allowUnauthorized" for self-signed certs';
                    }
                    resolve({ success: false, error: message, latencyMs: getLatency() });
                });
                req.end();
            }
            catch (err) {
                resolve({ success: false, error: `Invalid URL: ${err.message}` });
            }
        });
    });
    function isMaskedKey(key) {
        return key.includes('...') || key.startsWith('***') || key === '********';
    }
    ;
    // ─── Fetch Models from /v1/models endpoint ──────────────────────────────────────
    // P3-18: Query a provider's /v1/models endpoint to discover available models
    electron_1.ipcMain.handle('storage:fetch-models', async (_event, params) => {
        // eslint-disable-next-line @typescript-eslint/no-var-requires
        const https = require('https');
        // eslint-disable-next-line @typescript-eslint/no-var-requires
        const http = require('http');
        return new Promise((resolve) => {
            try {
                // Build the models list URL from the provider's base URL
                // e.g. https://api.openai.com/v1/chat/completions → /v1/models
                // e.g. https://api.anthropic.com/v1/messages → /v1/models
                // e.g. http://localhost:11434/v1/chat/completions → /v1/models
                let baseUrl = (typeof params?.apiUrl === 'string' && params.apiUrl) ? params.apiUrl : (typeof params?.baseUrl === 'string' ? params.baseUrl : '');
                if (!baseUrl || typeof baseUrl !== 'string') {
                    resolve({ success: false, error: 'No API URL provided' });
                    return;
                }
                // Strip the chat/completions or /messages path to get the base
                const urlLower = baseUrl.toLowerCase();
                // Detect Google AI Studio URLs (e.g. .../v1beta/models/...)
                const isGooglePath = /\/v\d+beta\/models/i.test(baseUrl) || /\/v\d+\/models/i.test(baseUrl);
                if (urlLower.includes('/chat/completions') || urlLower.includes('/completions')) {
                    baseUrl = baseUrl.replace(/\/chat\/completions|\/completions$/i, '');
                }
                else if (urlLower.includes('/messages')) {
                    baseUrl = baseUrl.replace(/\/messages$/i, '');
                }
                else if (isGooglePath || urlLower.includes(':generatecontent') || urlLower.includes('/generatecontent') || urlLower.includes(':streamgeneratecontent') || urlLower.includes('/streamgeneratecontent')) {
                    // Google: strip everything after /models/{modelName}
                    baseUrl = baseUrl.replace(/\/models\/[^/]+.*$/i, '/models');
                }
                // Trim trailing slashes
                baseUrl = baseUrl.replace(/\/+$/, '');
                // For Google-style URLs that already end with /models, return as-is
                if (isGooglePath && baseUrl.endsWith('/models')) {
                    // keep as-is
                }
                else if (baseUrl.endsWith('/v1')) {
                    baseUrl += '/models';
                }
                else {
                    baseUrl += '/v1/models';
                }
                const url = new URL(baseUrl);
                const client = url.protocol === 'https:' ? https : http;
                const options = {
                    method: 'GET',
                    hostname: url.hostname,
                    port: parseInt(url.port || (url.protocol === 'https:' ? '443' : '80'), 10),
                    path: url.pathname + url.search,
                    timeout: 15000,
                    rejectUnauthorized: !params.allowUnauthorized,
                    headers: {
                        'Content-Type': 'application/json',
                    },
                };
                const providerLower = (params.provider || '').toLowerCase();
                // Add auth header
                const apiKey = params.apiKey;
                if (apiKey && apiKey !== 'none' && !isMaskedKey(apiKey)) {
                    let key = apiKey;
                    try {
                        key = cryptoStore.decryptString(apiKey);
                    }
                    catch {
                        /* key might not be encrypted */
                    }
                    if (providerLower === 'anthropic') {
                        options.headers['x-api-key'] = key;
                        options.headers['anthropic-version'] = '2025-04-01';
                    }
                    else if (providerLower === 'google') {
                        options.headers['x-goog-api-key'] = key;
                    }
                    else {
                        options.headers['Authorization'] = `Bearer ${key}`;
                    }
                }
                const req = client.request(options, (res) => {
                    let body = '';
                    let bytes = 0;
                    const MAX_BODY = 4 * 1024 * 1024;
                    res.on('data', (chunk) => {
                        bytes += chunk.length;
                        if (bytes > MAX_BODY) {
                            req.destroy();
                            resolve({ success: false, error: 'Response too large' });
                            return;
                        }
                        body += chunk.toString();
                    });
                    res.on('end', () => {
                        if (!res.statusCode || res.statusCode < 200 || res.statusCode >= 300) {
                            resolve({ success: false, error: `HTTP ${res.statusCode}: ${body.slice(0, 200)}` });
                            return;
                        }
                        try {
                            const parsed = JSON.parse(body);
                            // Handle different response formats:
                            // 1. OpenAI/OpenAI-compatible: { data: [{ id: 'gpt-4o', ... }] }
                            // 2. Google: { models: [{ name: 'models/gemini-pro', ... }] }
                            // 3. Anthropic: { data: [{ type: 'model', id: 'claude-3-5-sonnet-latest', ... }] }
                            let models = [];
                            if (Array.isArray(parsed.data)) {
                                // OpenAI format
                                models = parsed.data.map((m) => ({
                                    id: m.id || '',
                                    name: m.id || m.name || '',
                                }));
                            }
                            else if (Array.isArray(parsed.models)) {
                                // Google format
                                models = parsed.models.map((m) => ({
                                    id: m.name || '',
                                    name: m.displayName || m.name || '',
                                }));
                            }
                            else if (Array.isArray(parsed.model_ids)) {
                                // Some providers use model_ids
                                models = parsed.model_ids.map((id) => ({
                                    id,
                                    name: id,
                                }));
                            }
                            // Also check for nested data property
                            if (models.length === 0 && parsed.data && typeof parsed.data === 'object') {
                                const nestedData = parsed.data.data;
                                if (Array.isArray(nestedData)) {
                                    models = nestedData.map((m) => ({
                                        id: m.id || '',
                                        name: m.id || m.name || '',
                                    }));
                                }
                            }
                            resolve({
                                success: true,
                                models,
                            });
                        }
                        catch (parseErr) {
                            resolve({
                                success: false,
                                error: `Failed to parse response: ${parseErr.message}`,
                            });
                        }
                    });
                });
                req.setTimeout(15000, () => {
                    req.destroy();
                    resolve({ success: false, error: 'Request timed out after 15 seconds' });
                });
                req.on('error', (err) => {
                    let message = err.message;
                    if (message.includes('ECONNREFUSED')) {
                        message = 'Connection refused — server may not be running';
                    }
                    else if (message.includes('ENOTFOUND') || message.includes('getaddrinfo')) {
                        message = 'Host not found — check the API URL';
                    }
                    else if (message.includes('CERT') || message.includes('certificate') || message.includes('SSL')) {
                        message = 'SSL/TLS error — try enabling "allowUnauthorized" for self-signed certs';
                    }
                    resolve({ success: false, error: message });
                });
                req.end();
            }
            catch (err) {
                resolve({ success: false, error: `Invalid URL: ${err.message}` });
            }
        });
    });
    // Logs
    electron_1.ipcMain.handle('logs:electron', async () => {
        try {
            const logPath = main_1.default.transports.file.getFile().path;
            const contents = await fs.readFile(logPath, 'utf-8');
            return contents;
        }
        catch (err) {
            return `Failed to read logs: ${String(err)}`;
        }
    });
    // Sidecar extension custom scheme
    electron_1.ipcMain.handle('extensions:send-authorities', async (_event, authorities) => {
        customScheme_1.extensionAuthorities.clear();
        for (const [key, value] of Object.entries(authorities)) {
            customScheme_1.extensionAuthorities.set(key, value);
        }
    });
    // Agent
    electron_1.ipcMain.handle('agent:update-active-count', async (_event, count) => {
        (0, tray_1.updateTrayAgentCount)(count);
    });
    // Window
    electron_1.ipcMain.handle('window:set-title-bar-overlay', async (_event, options) => {
        const win = electron_1.BrowserWindow.getFocusedWindow() || electron_1.BrowserWindow.getAllWindows()[0];
        if (win && process.platform === 'win32') {
            win.setTitleBarOverlay({
                color: options.color,
                symbolColor: options.symbolColor,
                height: 30,
            });
        }
    });
    electron_1.ipcMain.handle('window:minimize', async () => {
        const win = electron_1.BrowserWindow.getFocusedWindow() || electron_1.BrowserWindow.getAllWindows()[0];
        if (win) {
            win.minimize();
        }
    });
    electron_1.ipcMain.handle('window:maximize', async () => {
        const win = electron_1.BrowserWindow.getFocusedWindow() || electron_1.BrowserWindow.getAllWindows()[0];
        if (win) {
            win.maximize();
        }
    });
    electron_1.ipcMain.handle('window:unmaximize', async () => {
        const win = electron_1.BrowserWindow.getFocusedWindow() || electron_1.BrowserWindow.getAllWindows()[0];
        if (win) {
            win.unmaximize();
        }
    });
    electron_1.ipcMain.handle('window:is-maximized', async () => {
        const win = electron_1.BrowserWindow.getFocusedWindow() || electron_1.BrowserWindow.getAllWindows()[0];
        return win ? win.isMaximized() : false;
    });
    electron_1.ipcMain.handle('window:close', async () => {
        const win = electron_1.BrowserWindow.getFocusedWindow() || electron_1.BrowserWindow.getAllWindows()[0];
        if (win) {
            win.close();
        }
    });
    electron_1.ipcMain.handle('window:toggle-devtools', async () => {
        const win = electron_1.BrowserWindow.getFocusedWindow() || electron_1.BrowserWindow.getAllWindows()[0];
        if (win) {
            win.webContents.toggleDevTools();
        }
    });
    // Auto-updater manual check
    electron_1.ipcMain.handle('updater:get-state', () => ({ type: 'idle' }));
    electron_1.ipcMain.handle('updater:check-for-updates', () => {
        (0, updater_1.checkForUpdates)(true);
    });
    // Safe external shell launch
    electron_1.ipcMain.handle('shell:open-external', async (_event, url) => {
        if (url.startsWith('https://') || url.startsWith('http://')) {
            await electron_1.shell.openExternal(url);
        }
    });
    /**
     * IPC handler to fetch available models from a provider's API.
     * Supports OpenAI-compatible providers (GET /v1/models).
     */
    electron_1.ipcMain.handle('storage:fetch-provider-models', async (_event, params) => {
        return new Promise((resolve) => {
            try {
                const parsedUrl = new URL(params.apiUrl);
                // Determine the base URL and construct /v1/models endpoint
                let modelsUrl = params.apiUrl;
                // If the URL ends with a specific endpoint like /chat/completions, extract base
                if (modelsUrl.includes('/chat/completions')) {
                    modelsUrl = modelsUrl.replace(/\/chat\/completions.*$/, '/models');
                }
                else if (modelsUrl.includes('/v1/messages')) {
                    // Anthropic doesn't have a /models endpoint, return error
                    resolve({ success: false, error: 'Anthropic provider does not support model listing via API' });
                    return;
                }
                else if (!modelsUrl.endsWith('/models')) {
                    // Assume it's a base URL, append /v1/models
                    modelsUrl = modelsUrl.replace(/\/$/, '') + '/v1/models';
                }
                const protocol = parsedUrl.protocol === 'https:' ? https : http;
                const headers = {
                    'Content-Type': 'application/json',
                };
                if (params.apiKey && params.apiKey !== 'none') {
                    const decryptedKey = cryptoStore.decryptString(params.apiKey);
                    headers['Authorization'] = `Bearer ${decryptedKey}`;
                }
                const reqOptions = {
                    method: 'GET',
                    headers,
                    timeout: 10000,
                    rejectUnauthorized: !params.allowUnauthorized,
                };
                main_1.default.info(`[IPC] Fetching models from: ${modelsUrl}`);
                const req = protocol.request(modelsUrl, reqOptions, (res) => {
                    let body = '';
                    res.on('data', (chunk) => (body += chunk));
                    res.on('end', () => {
                        if (res.statusCode === 200) {
                            try {
                                const parsed = JSON.parse(body);
                                if (parsed.data && Array.isArray(parsed.data)) {
                                    const models = parsed.data
                                        .filter((m) => m.id && m.object === 'model')
                                        .map((m) => ({
                                        id: m.id,
                                        name: m.id,
                                        inputModalities: m.input_modalities || ['text'], // Default to text-only if not specified
                                    }));
                                    resolve({ success: true, models });
                                }
                                else {
                                    resolve({ success: false, error: 'Invalid response format from API' });
                                }
                            }
                            catch (err) {
                                resolve({ success: false, error: `Failed to parse response: ${err.message}` });
                            }
                        }
                        else {
                            resolve({ success: false, error: `HTTP ${res.statusCode}: ${body}` });
                        }
                    });
                });
                req.on('error', (err) => {
                    let message = err.message;
                    if (message.includes('ECONNREFUSED')) {
                        message = 'Connection refused — is the server running?';
                    }
                    else if (message.includes('ENOTFOUND')) {
                        message = 'Host not found — check the URL';
                    }
                    else if (message.includes('CERT') || message.includes('certificate') || message.includes('SSL')) {
                        message = 'SSL/TLS error — try enabling "allowUnauthorized" for self-signed certs';
                    }
                    resolve({ success: false, error: message });
                });
                req.end();
            }
            catch (err) {
                resolve({ success: false, error: `Invalid URL: ${err.message}` });
            }
        });
    });
}
//# sourceMappingURL=ipcHandlers.js.map