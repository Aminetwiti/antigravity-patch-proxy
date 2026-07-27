/**
 * Antigravity Preload Entry Point.
 *
 * Lightweight, secure contextBridge exposure for renderer processes.
 * Delegates API surface bindings to `src/preload/api.ts` and Doctor UI to `src/preload/doctor-ui.ts`.
 */

import { registerApiBridge } from './preload/api';
import { createLogger } from './shared/logger';

const preloadLog = createLogger('Preload');
preloadLog.debug('Preload script initialized');

// Expose secure Electron APIs to renderer window
registerApiBridge();

export * from './preload/types';
