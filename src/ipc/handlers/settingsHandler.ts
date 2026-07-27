import { dialog, ipcMain } from 'electron';
import { StorageManager } from '../../storage';

export function registerSettingsIpcHandlers(storageManager: StorageManager): void {
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

  ipcMain.handle('storage:get-items', async () => {
    return storageManager.getItems();
  });

  ipcMain.handle('storage:update-items', async (_event, changes: Record<string, string | null>) => {
    return storageManager.updateItems(changes);
  });
}
