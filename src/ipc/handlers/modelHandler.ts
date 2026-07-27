import { dialog, ipcMain } from 'electron';
import * as fs from 'fs/promises';
import * as customModelStore from '../../services/modelStore';
import { WELL_KNOWN_PRESETS } from '../../presets';
import * as configExchange from '../../configExchange';

export function registerModelIpcHandlers(): void {
  ipcMain.handle('storage:get-custom-models', async () => {
    return await customModelStore.loadCustomModels();
  });

  ipcMain.handle('storage:get-providers', async () => {
    const providers = await customModelStore.loadProviders();
    return providers.map((p) => ({
      ...p,
      apiKey: customModelStore.maskApiKey(p.apiKey),
    }));
  });

  ipcMain.handle('storage:get-well-known-presets', async () => {
    return WELL_KNOWN_PRESETS;
  });

  ipcMain.handle('storage:test-provider-health', async (_event, params: customModelStore.TestModelParams) => {
    return customModelStore.testProviderHealth(params);
  });

  ipcMain.handle('storage:export-providers-base64', async () => {
    try {
      const providers = await customModelStore.loadProviders();
      const base64 = configExchange.exportProvidersToBase64(providers);
      return { success: true, base64, count: providers.length };
    } catch (err) {
      return { success: false, error: (err as Error).message };
    }
  });

  ipcMain.handle(
    'storage:import-providers-base64',
    async (_event, base64Str: string, strategy: configExchange.MergeStrategy = 'merge') => {
      try {
        const incoming = configExchange.parseProvidersFromBase64(base64Str);
        const existing = await customModelStore.loadProviders();
        const res = configExchange.mergeProviderConfigs(existing, incoming, strategy);
        await customModelStore.saveProviders(res.providers);
        return res;
      } catch (err) {
        return { success: false, error: (err as Error).message };
      }
    },
  );

  ipcMain.handle('storage:save-provider', async (_event, newProvider: customModelStore.ProviderFileEntry) => {
    try {
      const providers = await customModelStore.loadProviders();
      const existingIdx = providers.findIndex((p) => p.id === newProvider.id);

      const rawKey = newProvider.apiKey;
      const isExplicitClear = !rawKey || rawKey === 'none' || rawKey === '';
      const isMasked =
        !isExplicitClear && (rawKey.includes('...') || rawKey.startsWith('***') || rawKey === '********');

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
}
