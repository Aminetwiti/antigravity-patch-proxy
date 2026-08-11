"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
/**
 * Preload script — exposes a strictly whitelisted IPC bridge to the renderer.
 */
const electron_1 = require("electron");
const api = {
    run: (args) => electron_1.ipcRenderer.invoke('ag:run', args),
    // Provider Management APIs
    providers: {
        get: () => electron_1.ipcRenderer.invoke('ag:providers:get'),
        save: (p) => electron_1.ipcRenderer.invoke('ag:providers:save', p),
        delete: (id) => electron_1.ipcRenderer.invoke('ag:providers:delete', id),
        fetchModels: (params) => electron_1.ipcRenderer.invoke('ag:providers:fetch-models', params),
        test: (params) => electron_1.ipcRenderer.invoke('ag:providers:test', params),
        onChanged: (handler) => {
            const listener = () => handler();
            electron_1.ipcRenderer.on('ag:providers:changed', listener);
            return () => electron_1.ipcRenderer.removeListener('ag:providers:changed', listener);
        },
    },
    info: () => electron_1.ipcRenderer.invoke('ag:info'),
    config: () => electron_1.ipcRenderer.invoke('ag:config'),
    setTheme: (theme) => electron_1.ipcRenderer.invoke('ag:config:set-theme', theme),
    setNotifyEnabled: (enabled) => electron_1.ipcRenderer.invoke('ag:config:set-notify', enabled),
    restoreBackup: () => electron_1.ipcRenderer.invoke('ag:config:restore-backup'),
    getProxyErrorHistory: () => electron_1.ipcRenderer.invoke('ag:proxy-error-history'),
    notify: (title, body) => electron_1.ipcRenderer.invoke('ag:notify', title, body),
    trayStatus: (status) => electron_1.ipcRenderer.invoke('ag:tray-status', status),
    openExternal: (url) => electron_1.ipcRenderer.invoke('ag:open-external', url),
    reveal: (p) => electron_1.ipcRenderer.invoke('ag:reveal', p),
    // MITM Proxy Server Management
    proxyStart: () => electron_1.ipcRenderer.invoke('ag:proxy:start'),
    proxyStop: () => electron_1.ipcRenderer.invoke('ag:proxy:stop'),
    proxyStatus: () => electron_1.ipcRenderer.invoke('ag:proxy:status'),
    proxyRestart: () => electron_1.ipcRenderer.invoke('ag:proxy:restart'),
    // Network Utils
    getLocalIp: () => electron_1.ipcRenderer.invoke('ag:network:getLocalIp'),
    generateQr: (text) => electron_1.ipcRenderer.invoke('ag:network:generateQr', text),
    startDaemon: (options) => electron_1.ipcRenderer.invoke('ag:network:startDaemon', options),
    stopDaemon: () => electron_1.ipcRenderer.invoke('ag:network:stopDaemon'),
    onDaemonLog: (callback) => {
        const handler = (_event, data) => callback(data);
        electron_1.ipcRenderer.on('ag:network:daemonLog', handler);
        return () => electron_1.ipcRenderer.removeListener('ag:network:daemonLog', handler);
    },
    // Antigravity lifecycle (version, status, launch, kill, restart)
    antigravityStatus: () => electron_1.ipcRenderer.invoke('ag:antigravity:status'),
    antigravityVersion: () => electron_1.ipcRenderer.invoke('ag:antigravity:version'),
    antigravityLaunch: () => electron_1.ipcRenderer.invoke('ag:antigravity:launch'),
    antigravityKill: () => electron_1.ipcRenderer.invoke('ag:antigravity:kill'),
    antigravityRestart: () => electron_1.ipcRenderer.invoke('ag:antigravity:restart'),
    antigravityLaunchLogs: () => electron_1.ipcRenderer.invoke('ag:antigravity:launch-logs'),
    // Proxy stub lifecycle — emergency fallback when Antigravity's bundled proxy fails
    proxyStartStub: () => electron_1.ipcRenderer.invoke('ag:proxy:start-stub'),
    proxyStubStatus: () => electron_1.ipcRenderer.invoke('ag:proxy:stub-status'),
    proxyStats: () => electron_1.ipcRenderer.invoke('ag:proxy-stats'),
    // Installation Detector — scans for Antigravity binaries (v1.x vs v2.0+)
    detectInstallation: () => electron_1.ipcRenderer.invoke('ag:detect-installation'),
    // Model testing — tests a single model's connection
    testModel: (name) => electron_1.ipcRenderer.invoke('ag:test-model', name),
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
    // MITM traffic fan-out — emitted once per intercepted request when the
    // proxy (mitm_443.js) writes a `mitm:traffic` JSON line on stdout.
    // payload.id is unique per call; payload.ts is Date.now() at the proxy.
    onMitmTraffic: (handler) => {
        const listener = (_, payload) => handler(payload);
        electron_1.ipcRenderer.on('mitm:traffic', listener);
        return () => electron_1.ipcRenderer.removeListener('mitm:traffic', listener);
    },
    // Real-time proxy error fan-out from the main process. The renderer
    // receives a ProxyErrorPayload (see src/proxy.ts) and renders the matching
    // native quota/error card via NativeQuotaCardRenderer.
    onProxyError: (handler) => {
        const listener = (_, payload) => handler(payload);
        electron_1.ipcRenderer.on('proxy:error', listener);
        return () => electron_1.ipcRenderer.removeListener('proxy:error', listener);
    },
};
electron_1.contextBridge.exposeInMainWorld('ag', api);
//# sourceMappingURL=preload.js.map