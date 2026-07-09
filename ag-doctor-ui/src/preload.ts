/**
 * Preload script — exposes a strictly whitelisted IPC bridge to the renderer.
 */
import { contextBridge, ipcRenderer } from 'electron';

export interface RunResult {
  code: number;
  stdout: string;
  stderr: string;
}

const api = {
  run: (args: string[]): Promise<RunResult> => ipcRenderer.invoke('ag:run', args),
  info: (): Promise<{
    platform: string;
    arch: string;
    versions: NodeJS.ProcessVersions;
    electron: string;
    node: string;
    chrome: string;
    cliPath: string;
  }> => ipcRenderer.invoke('ag:info'),
  config: (): Promise<Record<string, unknown>> => ipcRenderer.invoke('ag:config'),
  setTheme: (theme: 'dark' | 'light'): Promise<boolean> => ipcRenderer.invoke('ag:config:set-theme', theme),
  notify: (title: string, body: string): Promise<void> => ipcRenderer.invoke('ag:notify', title, body),
  trayStatus: (status: 'ok' | 'warn' | 'err'): Promise<void> => ipcRenderer.invoke('ag:tray-status', status),
  openExternal: (url: string): Promise<void> => ipcRenderer.invoke('ag:open-external', url),
  reveal: (p: string): Promise<void> => ipcRenderer.invoke('ag:reveal', p),

  // Antigravity lifecycle (version, status, launch, kill, restart)
  antigravityStatus: (): Promise<{ ok: boolean; data?: unknown; error?: string }> =>
    ipcRenderer.invoke('ag:antigravity:status'),
  antigravityVersion: (): Promise<{ ok: boolean; data?: { version: string }; error?: string }> =>
    ipcRenderer.invoke('ag:antigravity:version'),
  antigravityLaunch: (): Promise<{ ok: boolean; data?: { ok: boolean; pid?: number; message: string }; error?: string }> =>
    ipcRenderer.invoke('ag:antigravity:launch'),
  antigravityKill: (): Promise<{ ok: boolean; data?: { killed: number; message: string }; error?: string }> =>
    ipcRenderer.invoke('ag:antigravity:kill'),
  antigravityRestart: (): Promise<{ ok: boolean; data?: { ok: boolean; message: string; pid?: number }; error?: string }> =>
    ipcRenderer.invoke('ag:antigravity:restart'),

  // Proxy stub lifecycle — emergency fallback when Antigravity's bundled proxy fails
  proxyStartStub: (): Promise<{ ok: boolean; pid?: number; note?: string; error?: string }> =>
    ipcRenderer.invoke('ag:proxy:start-stub'),
  proxyStatus: (): Promise<{ ok: boolean; data?: { ok: boolean; stub: boolean; latencyMs: number; error?: string }; error?: string }> =>
    ipcRenderer.invoke('ag:proxy:status'),

  repairRun: (): Promise<{ ok: boolean; proxy?: boolean; ca?: boolean; error?: string }> =>
    ipcRenderer.invoke('ag:repair:run'),

  onRunDoctor: (handler: () => void): (() => void) => {
    const listener = () => handler();
    ipcRenderer.on('ag:run-doctor', listener);
    return () => ipcRenderer.removeListener('ag:run-doctor', listener);
  },
  onNavigate: (handler: (view: string) => void): (() => void) => {
    const listener = (_: unknown, view: string) => handler(view);
    ipcRenderer.on('ag:navigate', listener);
    return () => ipcRenderer.removeListener('ag:navigate', listener);
  },
  onCommandPalette: (handler: () => void): (() => void) => {
    const listener = () => handler();
    ipcRenderer.on('ag:command-palette', listener);
    return () => ipcRenderer.removeListener('ag:command-palette', listener);
  },
  onThemeChanged: (handler: (theme: 'dark' | 'light') => void): (() => void) => {
    const listener = (_: unknown, theme: 'dark' | 'light') => handler(theme);
    ipcRenderer.on('ag:theme-changed', listener);
    return () => ipcRenderer.removeListener('ag:theme-changed', listener);
  },

  startStream: (args: string[], streamId: string): Promise<boolean> =>
    ipcRenderer.invoke('ag:stream:start', args, streamId),
  cancelStream: (streamId: string): Promise<boolean> =>
    ipcRenderer.invoke('ag:stream:cancel', streamId),
  onStreamData: (streamId: string, handler: (chunk: string) => void): (() => void) => {
    const channel = `ag:stream:${streamId}:data`;
    const listener = (_: unknown, chunk: string) => handler(chunk);
    ipcRenderer.on(channel, listener);
    return () => ipcRenderer.removeListener(channel, listener);
  },
  onStreamClose: (streamId: string, handler: (code: number) => void): (() => void) => {
    const channel = `ag:stream:${streamId}:close`;
    const listener = (_: unknown, code: number) => handler(code);
    ipcRenderer.on(channel, listener);
    return () => ipcRenderer.removeListener(channel, listener);
  },
  onStreamError: (streamId: string, handler: (err: string) => void): (() => void) => {
    const channel = `ag:stream:${streamId}:error`;
    const listener = (_: unknown, err: string) => handler(err);
    ipcRenderer.on(channel, listener);
    return () => ipcRenderer.removeListener(channel, listener);
  },
};

contextBridge.exposeInMainWorld('ag', api);

export type AgAPI = typeof api;
