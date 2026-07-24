// Ambient declarations for the renderer global window.ag bridge.
// Loaded as a script (no module). Types are erased at build time.

interface RunResult {
  code: number;
  stdout: string;
  stderr: string;
}

interface AgAPI {
  run(args: string[]): Promise<RunResult>;
  info(): Promise<{
    platform: string;
    arch: string;
    versions: NodeJS.ProcessVersions;
    electron: string;
    node: string;
    chrome: string;
    cliPath: string;
  }>;
  config(): Promise<Record<string, unknown>>;
  setTheme(theme: 'dark' | 'light'): Promise<boolean>;
  notify(title: string, body: string): Promise<void>;
  trayStatus(status: 'ok' | 'warn' | 'err'): Promise<void>;
  openExternal(url: string): Promise<void>;
  reveal(p: string): Promise<void>;
  
  // MITM Proxy Server Management
  proxyStart(): Promise<{ ok: boolean; message: string; pid?: number }>;
  proxyStop(): Promise<{ ok: boolean; message: string }>;
  proxyStatus(): Promise<{ ok: boolean; data?: { running: boolean; port: number; pid?: number; error?: string }; error?: string }>;
  proxyRestart(): Promise<{ ok: boolean; message: string }>;
  
  onRunDoctor(handler: () => void): () => void;
  onNavigate(handler: (view: string) => void): () => void;
  onCommandPalette(handler: () => void): () => void;
  onThemeChanged(handler: (theme: 'dark' | 'light') => void): () => void;
  startStream(args: string[], streamId: string): Promise<boolean>;
  cancelStream(streamId: string): Promise<boolean>;
  onStreamData(streamId: string, handler: (chunk: string) => void): () => void;
  onStreamClose(streamId: string, handler: (code: number) => void): () => void;
  onStreamError(streamId: string, handler: (err: string) => void): () => void;

  // Antigravity lifecycle
  antigravityStatus(): Promise<{ ok: boolean; data?: unknown; error?: string }>;
  antigravityVersion(): Promise<{ ok: boolean; data?: { version: string }; error?: string }>;
  antigravityLaunch(): Promise<{ ok: boolean; data?: { ok: boolean; pid?: number; message: string }; error?: string }>;
  antigravityKill(): Promise<{ ok: boolean; data?: { killed: number; message: string }; error?: string }>;
  antigravityRestart(): Promise<{ ok: boolean; data?: { ok: boolean; message: string; pid?: number }; error?: string }>;
  antigravityLaunchLogs(): Promise<string | null>;
  repairRun(): Promise<{ ok: boolean; proxy?: boolean; ca?: boolean; error?: string }>;

  // Proxy stub lifecycle — emergency fallback when Antigravity's bundled proxy fails
  proxyStartStub(): Promise<{ ok: boolean; pid?: number; note?: string; error?: string }>;
  proxyStubStatus(): Promise<{ ok: boolean; data?: { ok: boolean; stub: boolean; latencyMs: number; error?: string }; error?: string }>;
}

interface Window {
  ag: AgAPI;
}
