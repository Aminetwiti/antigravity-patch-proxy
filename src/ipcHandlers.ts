import { app, BrowserWindow, dialog, ipcMain, Notification, shell } from 'electron';
import { autoUpdater } from 'electron-updater';
import { broadcastState, checkForUpdates } from './updater';
import log from 'electron-log/main';
import * as fs from 'fs/promises';
import * as path from 'path';
import * as http from 'http';
import * as https from 'https';
import { extensionAuthorities } from './customScheme';
import { updateTrayAgentCount } from './tray';
import { StorageManager } from './storage';

// eslint-disable-next-line @typescript-eslint/no-var-requires
const cryptoStore = require('./cryptoStore');
import * as customModelStore from './customModelStore';

/**
 * Registers all IPC handlers for the main process.
 */
export function registerIpcHandlers(storageManager: StorageManager): void {
  // Dialog
  ipcMain.handle('dialog:open-workspace', async () => {
    const result = await dialog.showOpenDialog({
      properties: ['openDirectory', 'createDirectory'],
      title: 'Open workspace',
    });
    if (result.canceled || result.filePaths.length === 0) {
      return undefined;
    }
    return result.filePaths[0];
  });

  // Auto-updater
  ipcMain.handle('updater:apply', async () => {
    broadcastState({ type: 'ready' });
  });
  ipcMain.handle('updater:quit-and-install', () => {
    if (!app.isPackaged) {
      console.log('[AutoUpdater] Skipping quitAndInstall (requires a packaged app).');
      return;
    }
    autoUpdater.quitAndInstall();
  });

  // Notifications
  ipcMain.handle(
    'notification:send',
    (_event, options: { title: string; body: string; silent?: boolean; payload?: unknown }) => {
      const notification = new Notification({
        title: options.title,
        body: options.body,
        silent: options.silent ?? false,
      });
      notification.on('click', () => {
        const win = BrowserWindow.getAllWindows()[0];
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
    },
  );

  // Note: copied from our desktop AGY implementation:
  // vs/platform/nativeNotification/electron-main/electronNotificationService.ts
  ipcMain.handle('notification:open-system-preferences', async () => {
    if (process.platform === 'darwin') {
      void shell.openExternal('x-apple.systempreferences:com.apple.preference.notifications');
    } else if (process.platform === 'win32') {
      void shell.openExternal('ms-settings:notifications');
    } else if (process.platform === 'linux') {
      const { exec } = await import('child_process');
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
        } catch {
          // Try next
        }
      }
    }
  });

  // Storage
  ipcMain.handle('storage:get-items', async () => {
    return storageManager.getItems();
  });
  ipcMain.handle('storage:update-items', async (_event, changes: Record<string, string | null>) => {
    await storageManager.updateItems(changes);
  });
  ipcMain.handle('storage:get-custom-models', async () => {
    // Unmasked version for preload.ts injection
    return await customModelStore.loadCustomModels();
  });

  ipcMain.handle('storage:get-providers', async () => {
    const providers = await customModelStore.loadProviders();
    return providers.map(p => ({
      ...p,
      apiKey: customModelStore.maskApiKey(p.apiKey)
    }));
  });

  ipcMain.handle('storage:save-provider', async (_event, newProvider: customModelStore.ProviderFileEntry) => {
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
      } else if (isMasked && existingIdx !== -1) {
        newProvider.apiKey = providers[existingIdx].apiKey;
        newProvider.encrypted = providers[existingIdx].encrypted;
      } else {
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
      } catch {
        return { success: false, error: 'Invalid API URL' };
      }

      if (existingIdx !== -1) {
        providers[existingIdx] = newProvider;
      } else {
        providers.push(newProvider);
      }

      await customModelStore.saveProviders(providers);
      return { success: true };
    } catch (err) {
      console.error('[IPC] Failed to save provider:', err);
      return { success: false, error: (err as Error).message };
    }
  });

  ipcMain.handle('storage:delete-provider', async (_event, providerId: string) => {
    try {
      const providers = await customModelStore.loadProviders();
      const filtered = providers.filter((p) => p.id !== providerId);
      await customModelStore.saveProviders(filtered);
      return { success: true };
    } catch (err) {
      console.error('[IPC] Failed to delete provider:', err);
      return { success: false, error: (err as Error).message };
    }
  });

  ipcMain.handle('storage:export-providers', async () => {
    try {
      const providers = await customModelStore.loadProviders();
      const saveResult = await (dialog as any).showSaveDialog({
        title: 'Export Provider Configuration',
        defaultPath: 'antigravity_providers.json',
        filters: [{ name: 'JSON Files', extensions: ['json'] }],
      });
      if (saveResult.canceled || !saveResult.filePath) {
        return { success: false, error: 'Cancelled' };
      }
      await fs.writeFile(saveResult.filePath, JSON.stringify({ providers }, null, 2), 'utf-8');
      return { success: true, count: providers.length };
    } catch (err) {
      return { success: false, error: (err as Error).message };
    }
  });

  ipcMain.handle('storage:get-doctor-diagnostics', async () => {
    try {
      const providers = await customModelStore.loadProviders();
      const customModels = await customModelStore.loadCustomModels();
      let activePort = 50999;
      try {
        const home = process.env.HOME || process.env.USERPROFILE || require('os').homedir();
        const portFile = path.join(home, '.gemini', 'antigravity', '.proxy_port');
        const content = await fs.readFile(portFile, 'utf-8');
        activePort = parseInt(content.trim(), 10) || 50999;
      } catch {
        /* default port */
      }
      const activeProviders = providers.filter((p) => p.enabled);
      const totalTokens = providers.reduce(
        (acc, p) => acc + (p.usage?.promptTokens || 0) + (p.usage?.completionTokens || 0),
        0,
      );
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
    } catch (err) {
      return { success: false, error: (err as Error).message };
    }
  });

  ipcMain.handle('storage:save-custom-model', async (_event, newModel: CustomModelFileEntry & { apiKey?: string }) => {
    try {
      const models = await customModelStore.loadCustomModels();
      const existingIdx = models.findIndex((m) => m.name === newModel.name);

      const isMasked =
        newModel.apiKey &&
        (newModel.apiKey.includes('...') || newModel.apiKey.startsWith('***') || newModel.apiKey === '********');
      if (isMasked && existingIdx !== -1) {
        newModel.apiKey = models[existingIdx].apiKey;
        newModel.encrypted = models[existingIdx].encrypted;
      } else if (newModel.apiKey && newModel.apiKey !== 'none') {
        newModel.apiKey = cryptoStore.encryptString(newModel.apiKey);
        newModel.encrypted = true;
      }

      if (existingIdx !== -1) {
        models[existingIdx] = newModel;
      } else {
        models.push(newModel);
      }

      await customModelStore.saveCustomModels(models);
      return { success: true };
    } catch (err) {
      console.error('[IPC] Failed to save custom model:', err);
      return { success: false, error: (err as Error).message };
    }
  });

  ipcMain.handle('storage:delete-custom-model', async (_event, modelName: string) => {
    try {
      await customModelStore.deleteCustomModel(modelName);
      return { success: true };
    } catch (err) {
      console.error('[IPC] Failed to delete custom model:', err);
      return { success: false, error: (err as Error).message };
    }
  });

  // P3-17: Test model connectivity — sends a lightweight HEAD/GET to the model endpoint
  ipcMain.handle('storage:test-model-connection', async (_event, model: TestModelParams) => {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const https = require('https');
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const http = require('http');

    return new Promise<ConnectionTestResult>((resolve) => {
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
            } else if (!urlStr.endsWith('/')) {
              urlStr += '/v1/chat/completions';
            } else {
              urlStr += 'v1/chat/completions';
            }
          }
        }

        const url = new URL(urlStr);
        const client = url.protocol === 'https:' ? https : http;

        interface RequestOptions {
          method: string;
          hostname: string;
          port: number;
          path: string;
          timeout: number;
          rejectUnauthorized: boolean;
          headers?: Record<string, string>;
        }

        const options: RequestOptions = {
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
          } catch {
            /* key might not be encrypted */
          }

          if (model.provider === 'anthropic') {
            options.headers = {
              'x-api-key': key,
              'anthropic-version': '2025-04-01',
            };
          } else if (model.provider === 'google') {
            options.headers = {
              'x-goog-api-key': key,
            };
          } else {
            options.headers = {
              Authorization: `Bearer ${key}`,
            };
          }
        }

        const startTime = Date.now();
        const getLatency = () => Math.round(Date.now() - startTime);

        const req = client.request(options);

        req.on('response', (res: http.IncomingMessage) => {
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
          res.on('data', (chunk: Buffer | string) => {
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

        req.on('error', (err: NodeJS.ErrnoException) => {
          let message = err.message;
          if (message.includes('ECONNREFUSED')) {
            message = 'Connection refused — server may not be running';
          } else if (message.includes('ENOTFOUND') || message.includes('getaddrinfo')) {
            message = 'Host not found — check the API URL';
          } else if (message.includes('CERT') || message.includes('certificate') || message.includes('SSL')) {
            message = 'SSL/TLS error — try enabling "allowUnauthorized" for self-signed certs';
          }
          resolve({ success: false, error: message, latencyMs: getLatency() });
        });

        req.end();
      } catch (err) {
        resolve({ success: false, error: `Invalid URL: ${(err as Error).message}` });
      }
    });
  });

  function isMaskedKey(key: string): boolean {
    return key.includes('...') || key.startsWith('***') || key === '********';
  };

  // ─── Fetch Models from /v1/models endpoint ──────────────────────────────────────
  // P3-18: Query a provider's /v1/models endpoint to discover available models
  ipcMain.handle('storage:fetch-models', async (_event, params: FetchModelsParams) => {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const https = require('https');
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const http = require('http');

    return new Promise<FetchModelsResult>((resolve) => {
      try {
        // Build the models list URL from the provider's base URL
        // e.g. https://api.openai.com/v1/chat/completions → /v1/models
        // e.g. https://api.anthropic.com/v1/messages → /v1/models
        // e.g. http://localhost:11434/v1/chat/completions → /v1/models
        let baseUrl = (typeof params?.apiUrl === 'string' && params.apiUrl) ? params.apiUrl : (typeof (params as any)?.baseUrl === 'string' ? (params as any).baseUrl : '');

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
        } else if (urlLower.includes('/messages')) {
          baseUrl = baseUrl.replace(/\/messages$/i, '');
        } else if (isGooglePath || urlLower.includes(':generatecontent') || urlLower.includes('/generatecontent') || urlLower.includes(':streamgeneratecontent') || urlLower.includes('/streamgeneratecontent')) {
          // Google: strip everything after /models/{modelName}
          baseUrl = baseUrl.replace(/\/models\/[^/]+.*$/i, '/models');
        }

        // Trim trailing slashes
        baseUrl = baseUrl.replace(/\/+$/, '');

        // For Google-style URLs that already end with /models, return as-is
        if (isGooglePath && baseUrl.endsWith('/models')) {
          // keep as-is
        } else if (baseUrl.endsWith('/v1')) {
          baseUrl += '/models';
        } else {
          baseUrl += '/v1/models';
        }

        const url = new URL(baseUrl);
        const client = url.protocol === 'https:' ? https : http;

        const options: https.RequestOptions = {
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
        const apiKey = (params as { apiKey?: string }).apiKey;
        if (apiKey && apiKey !== 'none' && !isMaskedKey(apiKey)) {
          let key = apiKey;
          try {
            key = cryptoStore.decryptString(apiKey);
          } catch {
            /* key might not be encrypted */
          }

          if (providerLower === 'anthropic') {
            (options.headers as Record<string, string>)['x-api-key'] = key;
            (options.headers as Record<string, string>)['anthropic-version'] = '2025-04-01';
          } else if (providerLower === 'google') {
            (options.headers as Record<string, string>)['x-goog-api-key'] = key;
          } else {
            (options.headers as Record<string, string>)['Authorization'] = `Bearer ${key}`;
          }
        }

        const req = client.request(options, (res: http.IncomingMessage) => {
          let body = '';
          let bytes = 0;
          const MAX_BODY = 4 * 1024 * 1024;

          res.on('data', (chunk: string | Buffer) => {
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
              const parsed = JSON.parse(body) as Record<string, unknown>;

              // Handle different response formats:
              // 1. OpenAI/OpenAI-compatible: { data: [{ id: 'gpt-4o', ... }] }
              // 2. Google: { models: [{ name: 'models/gemini-pro', ... }] }
              // 3. Anthropic: { data: [{ type: 'model', id: 'claude-3-5-sonnet-latest', ... }] }

              let models: { id: string; name: string }[] = [];

              if (Array.isArray(parsed.data)) {
                // OpenAI format
                models = (parsed.data as Array<Record<string, unknown>>).map((m) => ({
                  id: (m.id as string) || '',
                  name: (m.id as string) || (m.name as string) || '',
                }));
              } else if (Array.isArray(parsed.models)) {
                // Google format
                models = (parsed.models as Array<Record<string, unknown>>).map((m) => ({
                  id: (m.name as string) || '',
                  name: (m.displayName as string) || (m.name as string) || '',
                }));
              } else if (Array.isArray(parsed.model_ids)) {
                // Some providers use model_ids
                models = (parsed.model_ids as string[]).map((id) => ({
                  id,
                  name: id,
                }));
              }

              // Also check for nested data property
              if (models.length === 0 && parsed.data && typeof parsed.data === 'object') {
                const nestedData = (parsed.data as Record<string, unknown>).data;
                if (Array.isArray(nestedData)) {
                  models = (nestedData as Array<Record<string, unknown>>).map((m) => ({
                    id: (m.id as string) || '',
                    name: (m.id as string) || (m.name as string) || '',
                  }));
                }
              }

              resolve({
                success: true,
                models,
              });
            } catch (parseErr) {
              resolve({
                success: false,
                error: `Failed to parse response: ${(parseErr as Error).message}`,
              });
            }
          });
        });

        req.setTimeout(15000, () => {
          req.destroy();
          resolve({ success: false, error: 'Request timed out after 15 seconds' });
        });

        req.on('error', (err: NodeJS.ErrnoException) => {
          let message = err.message;
          if (message.includes('ECONNREFUSED')) {
            message = 'Connection refused — server may not be running';
          } else if (message.includes('ENOTFOUND') || message.includes('getaddrinfo')) {
            message = 'Host not found — check the API URL';
          } else if (message.includes('CERT') || message.includes('certificate') || message.includes('SSL')) {
            message = 'SSL/TLS error — try enabling "allowUnauthorized" for self-signed certs';
          }
          resolve({ success: false, error: message });
        });

        req.end();
      } catch (err) {
        resolve({ success: false, error: `Invalid URL: ${(err as Error).message}` });
      }
    });
  });

  // Logs
  ipcMain.handle('logs:electron', async () => {
    try {
      const logPath = log.transports.file.getFile().path;
      const contents = await fs.readFile(logPath, 'utf-8');
      return contents;
    } catch (err) {
      return `Failed to read logs: ${String(err)}`;
    }
  });

  // Sidecar extension custom scheme
  ipcMain.handle('extensions:send-authorities', async (_event, authorities: Record<string, string>) => {
    extensionAuthorities.clear();
    for (const [key, value] of Object.entries(authorities)) {
      extensionAuthorities.set(key, value);
    }
  });

  // Agent
  ipcMain.handle('agent:update-active-count', async (_event, count: number) => {
    updateTrayAgentCount(count);
  });

  // Window
  ipcMain.handle('window:set-title-bar-overlay', async (_event, options: { color: string; symbolColor: string }) => {
    const win = BrowserWindow.getFocusedWindow() || BrowserWindow.getAllWindows()[0];
    if (win && process.platform === 'win32') {
      win.setTitleBarOverlay({
        color: options.color,
        symbolColor: options.symbolColor,
        height: 30,
      });
    }
  });
  ipcMain.handle('window:minimize', async () => {
    const win = BrowserWindow.getFocusedWindow() || BrowserWindow.getAllWindows()[0];
    if (win) {
      win.minimize();
    }
  });
  ipcMain.handle('window:maximize', async () => {
    const win = BrowserWindow.getFocusedWindow() || BrowserWindow.getAllWindows()[0];
    if (win) {
      win.maximize();
    }
  });
  ipcMain.handle('window:unmaximize', async () => {
    const win = BrowserWindow.getFocusedWindow() || BrowserWindow.getAllWindows()[0];
    if (win) {
      win.unmaximize();
    }
  });
  ipcMain.handle('window:is-maximized', async () => {
    const win = BrowserWindow.getFocusedWindow() || BrowserWindow.getAllWindows()[0];
    return win ? win.isMaximized() : false;
  });
  ipcMain.handle('window:close', async () => {
    const win = BrowserWindow.getFocusedWindow() || BrowserWindow.getAllWindows()[0];
    if (win) {
      win.close();
    }
  });
  ipcMain.handle('window:toggle-devtools', async () => {
    const win = BrowserWindow.getFocusedWindow() || BrowserWindow.getAllWindows()[0];
    if (win) {
      win.webContents.toggleDevTools();
    }
  });

  // Auto-updater manual check
  ipcMain.handle('updater:get-state', () => ({ type: 'idle' }));
  ipcMain.handle('updater:check-for-updates', () => {
    checkForUpdates(true);
  });

  // Safe external shell launch
  ipcMain.handle('shell:open-external', async (_event, url: string) => {
    if (url.startsWith('https://') || url.startsWith('http://')) {
      await shell.openExternal(url);
    }
  });

  /**
   * IPC handler to fetch available models from a provider's API.
   * Supports OpenAI-compatible providers (GET /v1/models).
   */
  ipcMain.handle('storage:fetch-provider-models', async (_event, params: FetchModelsParams): Promise<FetchModelsResult> => {
    return new Promise((resolve) => {
      try {
        const parsedUrl = new URL(params.apiUrl);
        
        // Determine the base URL and construct /v1/models endpoint
        let modelsUrl = params.apiUrl;
        
        // If the URL ends with a specific endpoint like /chat/completions, extract base
        if (modelsUrl.includes('/chat/completions')) {
          modelsUrl = modelsUrl.replace(/\/chat\/completions.*$/, '/models');
        } else if (modelsUrl.includes('/v1/messages')) {
          // Anthropic doesn't have a /models endpoint, return error
          resolve({ success: false, error: 'Anthropic provider does not support model listing via API' });
          return;
        } else if (!modelsUrl.endsWith('/models')) {
          // Assume it's a base URL, append /v1/models
          modelsUrl = modelsUrl.replace(/\/$/, '') + '/v1/models';
        }
        
        const protocol = parsedUrl.protocol === 'https:' ? https : http;
        const headers: Record<string, string> = {
          'Content-Type': 'application/json',
        };
        
        if (params.apiKey && params.apiKey !== 'none') {
          const decryptedKey = cryptoStore.decryptString(params.apiKey) as string;
          headers['Authorization'] = `Bearer ${decryptedKey}`;
        }
        
        const reqOptions = {
          method: 'GET',
          headers,
          timeout: 10000,
          rejectUnauthorized: !params.allowUnauthorized,
        };
        
        log.info(`[IPC] Fetching models from: ${modelsUrl}`);
        
        const req = protocol.request(modelsUrl, reqOptions, (res) => {
          let body = '';
          res.on('data', (chunk) => (body += chunk));
          res.on('end', () => {
            if (res.statusCode === 200) {
              try {
                const parsed = JSON.parse(body) as { data?: Array<{ id: string; object?: string; input_modalities?: string[] }> };
                
                if (parsed.data && Array.isArray(parsed.data)) {
                  const models = parsed.data
                    .filter((m) => m.id && m.object === 'model')
                    .map((m) => ({
                      id: m.id,
                      name: m.id,
                      inputModalities: m.input_modalities || ['text'], // Default to text-only if not specified
                    }));
                  
                  resolve({ success: true, models });
                } else {
                  resolve({ success: false, error: 'Invalid response format from API' });
                }
              } catch (err) {
                resolve({ success: false, error: `Failed to parse response: ${(err as Error).message}` });
              }
            } else {
              resolve({ success: false, error: `HTTP ${res.statusCode}: ${body}` });
            }
          });
        });
        
        req.on('error', (err) => {
          let message = err.message;
          if (message.includes('ECONNREFUSED')) {
            message = 'Connection refused — is the server running?';
          } else if (message.includes('ENOTFOUND')) {
            message = 'Host not found — check the URL';
          } else if (message.includes('CERT') || message.includes('certificate') || message.includes('SSL')) {
            message = 'SSL/TLS error — try enabling "allowUnauthorized" for self-signed certs';
          }
          resolve({ success: false, error: message });
        });
        
        req.end();
      } catch (err) {
        resolve({ success: false, error: `Invalid URL: ${(err as Error).message}` });
      }
    });
  });
}

// ─── Local Types ──────────────────────────────────────────────────────────────

interface CustomModelFileEntry {
  name: string;
  displayName?: string;
  description?: string;
  provider: string;
  apiKey: string;
  apiUrl: string;
  externalModelName: string;
  allowUnauthorized?: boolean;
  encrypted?: boolean;
  /** Reasoning effort from /v1/models */
  reasoningEffort?: string;
  /** Thinking budget from /v1/models */
  thinkingBudget?: string;
  /** Mode from /v1/models */
  mode?: string;
  /** Input modalities (text, image, audio, video) */
  inputModalities?: string[];
  [key: string]: unknown;
}

interface TestModelParams {
  apiUrl: string;
  provider: string;
  apiKey?: string;
  allowUnauthorized?: boolean;
}

interface ConnectionTestResult {
  success: boolean;
  status?: number;
  message?: string;
  error?: string;
  latencyMs?: number;
}

// ─── Fetch Models Types ────────────────────────────────────────────────────────────

interface FetchModelsParams {
  apiUrl: string;
  provider: string;
  apiKey?: string;
  allowUnauthorized?: boolean;
}

interface FetchModelsResult {
  success: boolean;
  models?: { id: string; name: string; inputModalities?: string[] }[];
  error?: string;
}
