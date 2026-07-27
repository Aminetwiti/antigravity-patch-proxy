/**
 * Preload script — runs in every BrowserWindow before the page loads.
 * Exposes a minimal, secure API via contextBridge so the renderer can
 * communicate with the main-process auto-updater without nodeIntegration.
 */
import type { StorageAPI } from './preload/types';
export declare const storageAPI: StorageAPI;
export * from './preload/types';
//# sourceMappingURL=preload.d.ts.map