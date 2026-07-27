import { ipcMain } from 'electron';
import * as fs from 'fs/promises';
import * as path from 'path';
import * as os from 'os';
import * as customModelStore from '../../services/modelStore';

export function registerDoctorIpcHandlers(): void {
  ipcMain.handle('storage:get-doctor-diagnostics', async () => {
    try {
      const providers = await customModelStore.loadProviders();
      const customModels = await customModelStore.loadCustomModels();
      let activePort = 50999;
      try {
        const home = process.env.HOME || process.env.USERPROFILE || os.homedir();
        const portFile = path.join(home, '.gemini', 'antigravity', '.proxy_port');
        const content = await fs.readFile(portFile, 'utf-8');
        activePort = parseInt(content.trim(), 10) || 50999;
      } catch {
        /* default port fallback */
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
}
