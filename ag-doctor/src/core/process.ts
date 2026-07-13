/**
 * Process management: find / kill / spawn Antigravity.
 *
 * Improvements over the original:
 *   - `isPortInUse` now has a hard timeout so it never hangs on firewalled hosts.
 *   - `killAntigravityProcesses` escalates to SIGKILL after a grace period on
 *     non-Windows platforms (Windows has no equivalent graceful signal).
 */
import { execFile, spawn } from 'child_process';
import { promisify } from 'util';
import { getPlatform, isWsl } from './platform';

const execFileAsync = promisify(execFile);

export interface ProcessInfo {
  pid: number;
  command: string;
}

/** Find running Antigravity processes. */
export async function findAntigravityProcesses(): Promise<ProcessInfo[]> {
  const platform = getPlatform();
  try {
    if (platform === 'win32') {
      const { stdout } = await execFileAsync('tasklist', ['/FI', 'IMAGENAME eq Antigravity.exe', '/FO', 'CSV', '/NH']);
      return parseWindowsTasklist(stdout);
    }
    if (isWsl()) {
      // WSL can see Windows processes through tasklist.exe
      try {
        const { stdout } = await execFileAsync('/mnt/c/Windows/System32/tasklist.exe', ['/FI', 'IMAGENAME eq Antigravity.exe', '/FO', 'CSV', '/NH']);
        return parseWindowsTasklist(stdout);
      } catch {
        // fall through to pgrep
      }
    }
    if (platform === 'darwin' || platform === 'linux') {
      const { stdout } = await execFileAsync('pgrep', ['-af', 'Antigravity']);
      return parsePgrep(stdout);
    }
  } catch {
    // pgrep/tasklist exit 1 when nothing matches
  }
  return [];
}

function parseWindowsTasklist(stdout: string): ProcessInfo[] {
  const out: ProcessInfo[] = [];
  const lines = stdout.split(/\r?\n/);
  for (const line of lines) {
    const m = line.match(/^"Antigravity\.exe","(\d+)"/);
    if (m) out.push({ pid: parseInt(m[1], 10), command: 'Antigravity.exe' });
  }
  return out;
}

function parsePgrep(stdout: string): ProcessInfo[] {
  const out: ProcessInfo[] = [];
  const lines = stdout.split(/\r?\n/);
  for (const line of lines) {
    const m = line.match(/^(\d+)\s+(.*)$/);
    if (m) out.push({ pid: parseInt(m[1], 10), command: m[2] });
  }
  return out;
}

/**
 * Kill all Antigravity processes.
 *
 * On non-Windows: send SIGTERM, wait briefly, then SIGKILL anything still alive.
 * On Windows: taskkill /T /F (tree + force) to ensure child processes die too.
 */
export async function killAntigravityProcesses(): Promise<{ killed: number }> {
  const procs = await findAntigravityProcesses();
  const platform = getPlatform();
  if (platform === 'win32' || isWsl()) {
    const taskkill = platform === 'win32' ? 'taskkill' : '/mnt/c/Windows/System32/taskkill.exe';
    for (const p of procs) {
      try {
        await execFileAsync(taskkill, ['/PID', String(p.pid), '/T', '/F'], platform === 'win32' ? { windowsHide: true } : undefined);
      } catch {
        // ignore — process may have already exited
      }
    }
    return { killed: procs.length };
  }
  for (const p of procs) {
    try {
      process.kill(p.pid, 'SIGTERM');
    } catch {
      // ignore
    }
  }
  // Grace period, then escalate.
  await new Promise((r) => setTimeout(r, 1500));
  const stillAlive = await findAntigravityProcesses();
  for (const p of stillAlive) {
    try {
      process.kill(p.pid, 'SIGKILL');
    } catch {
      // ignore
    }
  }
  return { killed: procs.length };
}

/**
 * Check if a TCP port is in use.
 *
 * Has a hard timeout (default 1500ms) so callers never hang on firewalled hosts.
 */
export async function isPortInUse(port: number, host = '127.0.0.1', timeoutMs = 1500): Promise<boolean> {
  const net = await import('net');
  return new Promise((resolve) => {
    const sock = net.createConnection({ port, host });
    let done = false;
    const finish = (result: boolean) => {
      if (done) return;
      done = true;
      sock.destroy();
      resolve(result);
    };
    const timer = setTimeout(() => finish(false), timeoutMs);
    sock.once('connect', () => {
      clearTimeout(timer);
      finish(true);
    });
    sock.once('error', () => {
      clearTimeout(timer);
      finish(false);
    });
  });
}

/** Spawn a child process, inheriting stdio. */
export function spawnInherit(cmd: string, args: string[]): Promise<number> {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { stdio: 'inherit' });
    child.on('exit', (code) => resolve(code ?? 0));
    child.on('error', reject);
  });
}
