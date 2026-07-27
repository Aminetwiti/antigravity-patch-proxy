import { StorageManager } from '../storage';
import { registerSettingsIpcHandlers } from './handlers/settingsHandler';
import { registerModelIpcHandlers } from './handlers/modelHandler';
import { registerDoctorIpcHandlers } from './handlers/doctorHandler';
import { registerSystemIpcHandlers } from './handlers/systemHandler';
import { registerIpcHandlers as registerLegacyIpcHandlers } from '../ipcHandlers';

export function registerAllIpcHandlers(storageManager: StorageManager): void {
  registerSettingsIpcHandlers(storageManager);
  registerModelIpcHandlers();
  registerDoctorIpcHandlers();
  registerSystemIpcHandlers();
  registerLegacyIpcHandlers(storageManager);
}
