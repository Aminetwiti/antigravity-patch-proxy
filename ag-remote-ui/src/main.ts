import { app, BrowserWindow, ipcMain, shell } from 'electron';
import * as path from 'path';
import * as fs from 'fs';
import * as os from 'os';
import { spawn, execSync, ChildProcess } from 'child_process';
import qrcode from 'qrcode';

let mainWindow: BrowserWindow | null = null;
let daemonProcess: ChildProcess | null = null;

function resolveDaemonPath(): string {
  // Candidate paths (dev mode vs packaged app)
  const candidates = [
    path.join(__dirname, '..', '..', 'remote', 'daemon', 'daemon.exe'),
    path.join(__dirname, '..', 'remote', 'daemon', 'daemon.exe'),
    path.join(process.resourcesPath || '', 'remote', 'daemon', 'daemon.exe'),
    path.join(app.getAppPath(), '..', 'remote', 'daemon', 'daemon.exe'),
    path.join(__dirname, '..', '..', 'remote', 'daemon', 'daemon'),
  ];

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }

  // Fallback to relative standard dev location
  return path.join(__dirname, '..', '..', 'remote', 'daemon', 'daemon.exe');
}

function killOrphanDaemonProcesses(): void {
  try {
    if (process.platform === 'win32') {
      execSync('taskkill /F /IM daemon.exe /T 2>nul & taskkill /F /IM cloudflared.exe /T 2>nul', {
        stdio: 'ignore',
        windowsHide: true,
      });
    } else {
      execSync('pkill -f "remote/daemon/daemon" || true', { stdio: 'ignore' });
    }
  } catch {
    /* ignore cleanup errors */
  }
}

function createWindow(): void {
  const iconPath = path.join(__dirname, 'assets', 'icon.png');

  mainWindow = new BrowserWindow({
    width: 1040,
    height: 780,
    minWidth: 880,
    minHeight: 650,
    backgroundColor: '#09090b',
    title: 'Antigravity Remote Server',
    icon: fs.existsSync(iconPath) ? iconPath : undefined,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: false,
    },
  });

  mainWindow.setMenuBarVisibility(false);

  const indexPath = path.join(__dirname, 'renderer', 'index.html');
  mainWindow.loadFile(indexPath);

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

// ──────────────────────────────────────────
// IPC Handlers
// ──────────────────────────────────────────

ipcMain.handle('remote:getLocalIp', async () => {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    const list = interfaces[name];
    if (!list) continue;
    for (const iface of list) {
      if (iface.family === 'IPv4' && !iface.internal) {
        return iface.address;
      }
    }
  }
  return '127.0.0.1';
});

ipcMain.handle('remote:generateQr', async (_event, text: string) => {
  try {
    const dataUrl = await qrcode.toDataURL(text, {
      width: 260,
      margin: 2,
      color: { dark: '#000000FF', light: '#FFFFFFFF' },
    });
    return dataUrl;
  } catch (e: any) {
    throw new Error('Failed to generate QR code: ' + e.message);
  }
});

ipcMain.handle('remote:getDaemonStatus', async (_event, customPort?: number, token?: string) => {
  const port = customPort || 8090;
  const authToken = token || '11';
  let running = false;
  let diagData: any = {};
  let healthData: any = {};

  try {
    const res = await fetch(`http://127.0.0.1:${port}/health/diagnostic?token=${encodeURIComponent(authToken)}`, {
      signal: AbortSignal.timeout(1500),
    });
    if (res.ok) {
      diagData = await res.json();
      running = true;
    }
  } catch {
    /* offline */
  }

  try {
    const hRes = await fetch(`http://127.0.0.1:${port}/health`, {
      headers: { Authorization: `Bearer ${authToken}` },
      signal: AbortSignal.timeout(1500),
    });
    if (hRes.ok) {
      healthData = await hRes.json();
      running = true;
    }
  } catch {
    /* ignore */
  }

  return { running, port, ...diagData, telemetry: healthData };
});

ipcMain.handle('remote:startDaemon', async (event, options: { port: number; tunnel: string; token: string; allowFirstAdmin?: boolean }) => {
  const port = options.port || 8090;
  const token = options.token && options.token.trim().length > 0 ? options.token.trim() : '11';

  // Check if daemon is already active on this port
  try {
    const res = await fetch(`http://127.0.0.1:${port}/health/diagnostic?token=${encodeURIComponent(token)}`, {
      signal: AbortSignal.timeout(1500),
    });
    if (res.ok) {
      const data: any = await res.json();
      event.sender.send('remote:daemonLog', `> Daemon déjà actif et opérationnel sur le port ${port} (PID ${data.pid || 'actif'})\n`);
      if (data.publicUrl) {
        event.sender.send('remote:daemonLog', `🚀 Tunnel public actif : ${data.publicUrl}\n`);
      }
      return { success: true, alreadyRunning: true, port, token, ...data };
    }
  } catch {
    /* not running, proceed to launch */
  }

  if (daemonProcess) {
    try {
      daemonProcess.kill();
    } catch { /* ignore */ }
    daemonProcess = null;
  }

  killOrphanDaemonProcesses();

  const daemonExePath = resolveDaemonPath();
  const args = ['--port', port.toString()];

  if (options.tunnel && options.tunnel !== 'none') {
    args.push('--tunnel', options.tunnel);
  }
  args.push('--auth-token', token);
  if (options.allowFirstAdmin) {
    args.push('--allow-first-admin');
  }

  const daemonDir = path.dirname(daemonExePath);
  const daemonBinDir = path.join(daemonDir, 'bin');
  const envPath = `${daemonDir}${path.delimiter}${daemonBinDir}${path.delimiter}${process.env.PATH || ''}`;

  event.sender.send('remote:daemonLog', `[Lancement du daemon : ${daemonExePath} ${args.join(' ')}]\n`);

  daemonProcess = spawn(daemonExePath, args, {
    cwd: daemonDir,
    windowsHide: true,
    env: {
      ...process.env,
      PATH: envPath,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  daemonProcess.stdout?.on('data', (data: Buffer) => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('remote:daemonLog', data.toString());
    }
  });

  daemonProcess.stderr?.on('data', (data: Buffer) => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('remote:daemonLog', data.toString());
    }
  });

  daemonProcess.on('close', (code: number) => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('remote:daemonLog', `\n[Daemon terminé avec le code ${code}]\n`);
    }
    daemonProcess = null;
  });

  daemonProcess.on('error', (err: Error) => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('remote:daemonLog', `\n[Erreur de lancement : ${err.message}]\n`);
    }
  });

  return { success: true, alreadyRunning: false, port, token };
});

ipcMain.handle('remote:stopDaemon', async (event) => {
  if (daemonProcess) {
    try {
      daemonProcess.kill();
    } catch { /* ignore */ }
    daemonProcess = null;
  }
  killOrphanDaemonProcesses();
  event.sender.send('remote:daemonLog', `> Daemon arrêté manuellement.\n`);
  return { success: true };
});

ipcMain.handle('remote:openExternal', async (_event, url: string) => {
  try {
    if (typeof url === 'string' && (url.startsWith('https://') || url.startsWith('http://') || url.startsWith('ws://') || url.startsWith('wss://'))) {
      await shell.openExternal(url);
    }
  } catch (err) {
    console.error('Failed to open URL externally:', err);
  }
});

// ──────────────────────────────────────────
// App Lifecycle
// ──────────────────────────────────────────

app.whenReady().then(() => {
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on('window-all-closed', () => {
  if (daemonProcess) {
    try {
      daemonProcess.kill();
    } catch { /* ignore */ }
    daemonProcess = null;
  }
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('before-quit', () => {
  if (daemonProcess) {
    try {
      daemonProcess.kill();
    } catch { /* ignore */ }
    daemonProcess = null;
  }
});
