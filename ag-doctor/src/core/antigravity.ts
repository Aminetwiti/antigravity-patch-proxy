/**
 * Antigravity lifecycle: version detection, process listing, launch & kill.
 *
 * Version sources (in priority order):
 *   1. app.asar/package.json `version` field (requires reading the asar archive)
 *   2. product.json (electron-builder metadata) next to app.asar
 *   3. app-update.yml (electron-updater channel metadata)
 *   4. Antigravity.exe file version (Windows resource info)
 *   5. "unknown"
 *
 * The asar reader is dependency-free: it parses the asar index table manually.
 */
import fs from 'fs';
import path from 'path';
import os from 'os';
import { execFile, spawn } from 'child_process';
import { promisify } from 'util';
import {
  findAntigravityInstallDir,
  getAppAsarPath,
  getCustomModelsPath,
  getLsLogPath,
} from './paths';
import { isWsl } from './platform';
import { findAntigravityProcesses, killAntigravityProcesses } from './process';

const execFileAsync = promisify(execFile);

export interface AntigravityVersion {
  version: string;
  channel?: string;
  source: 'asar' | 'product.json' | 'app-update.yml' | 'exe' | 'pak' | 'unknown';
  raw?: string;
}

export interface AntigravityStatus {
  installed: boolean;
  installDir: string | null;
  appAsar: string | null;
  /** Alias of `appAsar` for renderer compatibility. */
  appAsarPath: string | null;
  /** Path to Antigravity.exe (or Antigravity on POSIX). */
  binaryPath: string | null;
  /** Path to custom_models.json. */
  customModelsPath: string | null;
  /** Path to the language_server log file. */
  lsLogPath: string | null;
  /** Convenience string version (e.g. "2.0.1"). */
  version: string | null;
  /** Detailed version info (channel, source). */
  versionInfo: AntigravityVersion | null;
  /** Friendly display name (e.g. productName). */
  displayName: string | null;
  running: boolean;
  /** First PID if running (renderer convenience). */
  pid: number | null;
  pids: number[];
  languageServerRunning: boolean;
  languageServerPids: number[];
  proxyPort: number;
  proxyReachable: boolean;
  // System info (mirrors `ag-doctor info`)
  username: string;
  homedir: string;
  cpu: string;
  memory: string;
}

/** Read a Windows PE file's FileVersion resource (best-effort, no deps). */
function readWindowsFileVersion(exePath: string): string | null {
  try {
    const buf = fs.readFileSync(exePath);
    const sig = Buffer.from('VS_VERSION_INFO', 'binary');
    const idx = buf.indexOf(sig);
    if (idx === -1) return null;
    const fixedSig = Buffer.from([0xbd, 0x04, 0xef, 0xce]); // VS_FIXEDFILEINFO magic
    const fixedIdx = buf.indexOf(fixedSig, idx);
    if (fixedIdx === -1) return null;
    const ms = buf.readUInt32LE(fixedIdx + 8);
    const ls = buf.readUInt32LE(fixedIdx + 12);
    const major = (ms >>> 16) & 0xffff;
    const minor = ms & 0xffff;
    const build = (ls >>> 16) & 0xffff;
    const revision = ls & 0xffff;
    if (major === 0 && minor === 0 && build === 0 && revision === 0) return null;
    if (build > 0 && revision === 0) {
      return `${major}.${minor}`;
    }
    return `${major}.${minor}.${build}`;
  } catch {
    return null;
  }
}

/** Parse the asar archive to find package.json using @electron/asar. */
function readAsarPackageJson(asarPath: string): { version?: string; name?: string; productName?: string } | null {
  try {
    // Lazy-require so the rest of the module loads even if the native dep is missing
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const asar = require('@electron/asar');
    const pkgJsonText = asar.extractFile(asarPath, 'package.json');
    if (!pkgJsonText) return null;
    return JSON.parse(pkgJsonText.toString('utf-8')) as {
      version?: string;
      name?: string;
      productName?: string;
    };
  } catch {
    return null;
  }
}

/** Read product.json next to app.asar (electron-builder metadata). */
function readProductJson(installDir: string): { version?: string; name?: string; productName?: string } | null {
  try {
    const candidates = [
      path.join(installDir, 'resources', 'product.json'),
      path.join(installDir, 'product.json'),
    ];
    for (const p of candidates) {
      if (fs.existsSync(p)) {
        return JSON.parse(fs.readFileSync(p, 'utf-8')) as { version?: string; name?: string; productName?: string };
      }
    }
  } catch {
    // ignore
  }
  return null;
}

/** Read app-update.yml — extract updater channel/version hints. */
function readAppUpdateYml(installDir: string): { channel?: string } | null {
  try {
    const p = path.join(installDir, 'resources', 'app-update.yml');
    if (!fs.existsSync(p)) return null;
    const raw = fs.readFileSync(p, 'utf-8');
    const channel = raw.match(/channel:\s*(\S+)/i)?.[1];
    return { channel };
  } catch {
    return null;
  }
}

/**
 * Detect the installed Antigravity version using multiple sources.
 * Returns null if Antigravity is not installed.
 */
export function detectAntigravityVersion(installDir?: string): AntigravityVersion | null {
  const dir = installDir ?? findAntigravityInstallDir();
  if (!dir) return null;

  // 1. app.asar/package.json (most reliable)
  const asarPath = getAppAsarPath(dir);
  if (asarPath && fs.existsSync(asarPath)) {
    const pkg = readAsarPackageJson(asarPath);
    if (pkg?.version) {
      return {
        version: pkg.version,
        channel: pkg.productName && pkg.productName !== pkg.name ? pkg.productName : undefined,
        source: 'asar',
        raw: JSON.stringify({ name: pkg.name, productName: pkg.productName }),
      };
    }
  }

  // 2. product.json
  const product = readProductJson(dir);
  if (product?.version) {
    return {
      version: product.version,
      channel: product.productName,
      source: 'product.json',
    };
  }

  // 3. app-update.yml channel
  const upd = readAppUpdateYml(dir);
  if (upd?.channel) {
    return {
      version: upd.channel,
      channel: upd.channel,
      source: 'app-update.yml',
    };
  }

  // 4. Windows PE FileVersion on Antigravity.exe
  if (process.platform === 'win32') {
    const exe = path.join(dir, 'Antigravity.exe');
    if (fs.existsSync(exe)) {
      const v = readWindowsFileVersion(exe);
      if (v) {
        return { version: v, source: 'exe' };
      }
    }
  }

  return { version: 'unknown', source: 'unknown' };
}

/** Check if a TCP port is reachable on localhost. */
async function isPortReachable(port: number, host = '127.0.0.1'): Promise<boolean> {
  const net = await import('net');
  return new Promise((resolve) => {
    const sock = net.createConnection({ port, host });
    const timer = setTimeout(() => {
      sock.destroy();
      resolve(false);
    }, 1500);
    sock.once('connect', () => {
      clearTimeout(timer);
      sock.destroy();
      resolve(true);
    });
    sock.once('error', () => {
      clearTimeout(timer);
      resolve(false);
    });
  });
}

/** Find language_server processes (Windows + Unix). */
async function findLanguageServerProcesses(): Promise<Array<{ pid: number; command: string }>> {
  try {
    if (process.platform === 'win32') {
      const { stdout } = await execFileAsync('tasklist', [
        '/FI',
        'IMAGENAME eq language_server.exe',
        '/FO',
        'CSV',
        '/NH',
      ]);
      const out: Array<{ pid: number; command: string }> = [];
      for (const line of stdout.split(/\r?\n/)) {
        const m = line.match(/^"language_server\.exe","(\d+)"/);
        if (m) out.push({ pid: parseInt(m[1]!, 10), command: 'language_server.exe' });
      }
      return out;
    }
    const { stdout } = await execFileAsync('pgrep', ['-af', 'language_server']);
    return stdout
      .split(/\r?\n/)
      .map((l) => l.match(/^(\d+)\s+(.*)$/))
      .filter((m): m is RegExpMatchArray => Boolean(m))
      .map((m) => ({ pid: parseInt(m[1]!, 10), command: m[2]! }));
  } catch {
    return [];
  }
}

/** Get the full status of Antigravity: install, version, running PIDs, proxy, paths, system info. */
export async function getAntigravityStatus(proxyPort = 50999): Promise<AntigravityStatus> {
  const installDir = findAntigravityInstallDir();
  const appAsar = getAppAsarPath();
  const version = detectAntigravityVersion();
  const agProcs = await findAntigravityProcesses();
  const lsProcs = await findLanguageServerProcesses();
  const proxyReachable = await isPortReachable(proxyPort);

  // Binary path
  let binaryPath: string | null = null;
  if (installDir) {
    const isWindowsExe = process.platform === 'win32' || installDir.includes('/mnt/') || installDir.includes(':\\\\');
    const exeName = isWindowsExe ? 'Antigravity.exe' : 'Antigravity';
    const candidate = path.join(installDir, exeName);
    if (fs.existsSync(candidate)) binaryPath = candidate;
  }

  // System info
  const username = os.userInfo().username;
  const homedir = os.homedir();
  const cpus = os.cpus();
  const cpu = `${cpus[0]?.model ?? 'unknown'} × ${cpus.length}`;
  const memory = `${(os.totalmem() / 1024 / 1024 / 1024).toFixed(1)} GB`;

  return {
    installed: Boolean(installDir),
    installDir,
    appAsar,
    appAsarPath: appAsar,
    binaryPath,
    customModelsPath: getCustomModelsPath(),
    lsLogPath: getLsLogPath(),
    version: version?.version ?? null,
    versionInfo: version,
    displayName: version?.channel ?? null,
    running: agProcs.length > 0,
    pid: agProcs[0]?.pid ?? null,
    pids: agProcs.map((p) => p.pid),
    languageServerRunning: lsProcs.length > 0,
    languageServerPids: lsProcs.map((p) => p.pid),
    proxyPort,
    proxyReachable,
    username,
    homedir,
    cpu,
    memory,
  };
}

/** Launch Antigravity. Returns the spawned PID or null on failure. */
export async function launchAntigravity(): Promise<{ ok: boolean; pid?: number; message: string }> {
  const dir = findAntigravityInstallDir();
  if (!dir) return { ok: false, message: 'Antigravity not found on disk' };

  const isWindowsExe = process.platform === 'win32' || isWsl() || dir.includes('/mnt/') || dir.includes(':\\\\');
  const exeName = isWindowsExe ? 'Antigravity.exe' : 'Antigravity';
  const exe = path.join(dir, exeName);
  if (!fs.existsSync(exe)) {
    return { ok: false, message: `Executable not found: ${exe}` };
  }

  const existing = await findAntigravityProcesses();
  if (existing.length > 0) {
    return { ok: true, pid: existing[0]!.pid, message: 'Already running' };
  }

  // Convert a WSL path back to a Windows path for cmd.exe / start
  const wslLaunch = isWsl();
  const winExe = wslLaunch ? exe.replace(/^\/mnt\/([a-z])\//i, '$1:/').replace(/\//g, '\\') : exe;

  try {
    if (process.platform === 'win32') {
      // Windows native: use cmd.exe /c start to open the GUI window reliably
      const { exec } = await import('child_process');
      const { promisify } = await import('util');
      const execAsync = promisify(exec);
      execAsync(`cmd.exe /c start "" "${winExe}"`, {
        cwd: dir,
        windowsHide: false,
      }).catch(() => {
        // Ignore errors - process is already launched
      });
    } else if (wslLaunch) {
      // WSL: spawn Windows binary through cmd.exe detached; GUI appears on the Windows host
      const child = spawn('/mnt/c/Windows/System32/cmd.exe', ['/c', 'start', '', winExe], {
        detached: true,
        stdio: 'ignore',
        cwd: dir,
      });
      child.unref();
    } else {
      // Unix: original behavior
      const child = spawn(exe, [], {
        detached: true,
        stdio: 'ignore',
        cwd: dir,
        env: { ...process.env },
      });
      child.unref();
    }

    // Poll for the process a few times (Electron apps can be slow to show up)
    for (let attempt = 0; attempt < 6; attempt++) {
      await new Promise((r) => setTimeout(r, 1000));
      const procs = await findAntigravityProcesses();
      const pid = procs[0]?.pid;
      if (pid) {
        return { ok: true, pid, message: `Launched (pid=${pid})` };
      }
    }

    return {
      ok: false,
      message: wslLaunch
        ? 'Process launched but not visible from WSL; launch Antigravity directly from Windows if needed'
        : 'Process started but not detected after 6s',
    };
  } catch (e) {
    return { ok: false, message: `Failed to launch: ${(e as Error).message}` };
  }
}

/** Kill all Antigravity processes. */
export async function closeAntigravity(): Promise<{ ok: boolean; killed: number; message: string }> {
  const procs = await findAntigravityProcesses();
  if (procs.length === 0) {
    return { ok: true, killed: 0, message: 'No running processes' };
  }
  const r = await killAntigravityProcesses();
  return { ok: true, killed: r.killed, message: `Killed ${r.killed} process(es)` };
}

/** Restart Antigravity: kill then launch. */
export async function restartAntigravity(): Promise<{ ok: boolean; message: string; pid?: number }> {
  const killRes = await closeAntigravity();
  await new Promise((r) => setTimeout(r, 1200));
  const launchRes = await launchAntigravity();
  return {
    ok: launchRes.ok,
    message: `${killRes.message} → ${launchRes.message}`,
    pid: launchRes.pid,
  };
}

/** Get the data directory used by ag-doctor. */
export function getDataDir(): string {
  return path.join(os.homedir(), '.gemini', 'antigravity');
}
