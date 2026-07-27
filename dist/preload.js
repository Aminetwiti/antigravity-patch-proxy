"use strict";
/**
 * Antigravity Preload Entry Point.
 *
 * Lightweight, secure contextBridge exposure for renderer processes.
 * Delegates API surface bindings to `src/preload/api.ts` and Doctor UI to `src/preload/doctor-ui.ts`.
 */
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
var __exportStar = (this && this.__exportStar) || function(m, exports) {
    for (var p in m) if (p !== "default" && !Object.prototype.hasOwnProperty.call(exports, p)) __createBinding(exports, m, p);
};
Object.defineProperty(exports, "__esModule", { value: true });
const api_1 = require("./preload/api");
const logger_1 = require("./shared/logger");
const preloadLog = (0, logger_1.createLogger)('Preload');
preloadLog.debug('Preload script initialized');
// Expose secure Electron APIs to renderer window
(0, api_1.registerApiBridge)();
__exportStar(require("./preload/types"), exports);
//# sourceMappingURL=preload.js.map