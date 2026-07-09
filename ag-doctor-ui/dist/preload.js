"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
/**
 * Preload script — exposes a strictly whitelisted IPC bridge to the renderer.
 */
const electron_1 = require("electron");
const api = {
    run: (args) => electron_1.ipcRenderer.invoke('ag:run', args),
    info: () => electron_1.ipcRenderer.invoke('ag:info'),
    config: () => electron_1.ipcRenderer.invoke('ag:config'),
    setTheme: (theme) => electron_1.ipcRenderer.invoke('ag:config:set-theme', theme),
    notify: (title, body) => electron_1.ipcRenderer.invoke('ag:notify', title, body),
    trayStatus: (status) => electron_1.ipcRenderer.invoke('ag:tray-status', status),
    openExternal: (url) => electron_1.ipcRenderer.invoke('ag:open-external', url),
    reveal: (p) => electron_1.ipcRenderer.invoke('ag:reveal', p),
    // Antigravity lifecycle (version, status, launch, kill, restart)
    antigravityStatus: () => electron_1.ipcRenderer.invoke('ag:antigravity:status'),
    antigravityVersion: () => electron_1.ipcRenderer.invoke('ag:antigravity:version'),
    antigravityLaunch: () => electron_1.ipcRenderer.invoke('ag:antigravity:launch'),
    antigravityKill: () => electron_1.ipcRenderer.invoke('ag:antigravity:kill'),
    antigravityRestart: () => electron_1.ipcRenderer.invoke('ag:antigravity:restart'),
    // Proxy stub lifecycle — emergency fallback when Antigravity's bundled proxy fails
    proxyStartStub: () => electron_1.ipcRenderer.invoke('ag:proxy:start-stub'),
    proxyStatus: () => electron_1.ipcRenderer.invoke('ag:proxy:status'),
    repairRun: () => electron_1.ipcRenderer.invoke('ag:repair:run'),
    onRunDoctor: (handler) => {
        const listener = () => handler();
        electron_1.ipcRenderer.on('ag:run-doctor', listener);
        return () => electron_1.ipcRenderer.removeListener('ag:run-doctor', listener);
    },
    onNavigate: (handler) => {
        const listener = (_, view) => handler(view);
        electron_1.ipcRenderer.on('ag:navigate', listener);
        return () => electron_1.ipcRenderer.removeListener('ag:navigate', listener);
    },
    onCommandPalette: (handler) => {
        const listener = () => handler();
        electron_1.ipcRenderer.on('ag:command-palette', listener);
        return () => electron_1.ipcRenderer.removeListener('ag:command-palette', listener);
    },
    onThemeChanged: (handler) => {
        const listener = (_, theme) => handler(theme);
        electron_1.ipcRenderer.on('ag:theme-changed', listener);
        return () => electron_1.ipcRenderer.removeListener('ag:theme-changed', listener);
    },
    startStream: (args, streamId) => electron_1.ipcRenderer.invoke('ag:stream:start', args, streamId),
    cancelStream: (streamId) => electron_1.ipcRenderer.invoke('ag:stream:cancel', streamId),
    onStreamData: (streamId, handler) => {
        const channel = `ag:stream:${streamId}:data`;
        const listener = (_, chunk) => handler(chunk);
        electron_1.ipcRenderer.on(channel, listener);
        return () => electron_1.ipcRenderer.removeListener(channel, listener);
    },
    onStreamClose: (streamId, handler) => {
        const channel = `ag:stream:${streamId}:close`;
        const listener = (_, code) => handler(code);
        electron_1.ipcRenderer.on(channel, listener);
        return () => electron_1.ipcRenderer.removeListener(channel, listener);
    },
    onStreamError: (streamId, handler) => {
        const channel = `ag:stream:${streamId}:error`;
        const listener = (_, err) => handler(err);
        electron_1.ipcRenderer.on(channel, listener);
        return () => electron_1.ipcRenderer.removeListener(channel, listener);
    },
};
electron_1.contextBridge.exposeInMainWorld('ag', api);
//# sourceMappingURL=preload.js.map