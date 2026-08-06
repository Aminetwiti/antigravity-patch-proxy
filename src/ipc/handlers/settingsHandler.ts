import { ipcMain } from 'electron';
import { StorageManager } from '../../storage';

/**
 * Registers IPC handlers for application storage and user settings.
 */
export function registerSettingsIpcHandlers(storageManager: StorageManager): void {
  ipcMain.handle('storage:get-items', async () => {
    return storageManager.getItems();
  });

  ipcMain.handle('storage:update-items', async (_event, changes: Record<string, string | null>) => {
    return storageManager.updateItems(changes);
  });
}
