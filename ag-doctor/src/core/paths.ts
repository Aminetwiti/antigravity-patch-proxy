/**
 * Cross-platform path resolution for Antigravity installation and data dirs.
 */
import path from 'path';
import os from 'os';
import fs from 'fs';
import { getPlatform } from './platform';
import { getProfilePath } from './profile';

/** Detect if we are running inside Windows Subsystem for Linux. */
function isWsl(): boolean {
  try {
    const rel = fs.readFileSync('/proc/sys/kernel/osrelease', 'utf-8') ||
                fs.readFileSync('/proc/version', 'utf-8');
    return /microsoft|wsl/i.test(rel);
  } catch {
    return false;
  }
}

/** Resolve a Windows path to its WSL mount (e.g. C:\... -> /mnt/c/...). */
function winToWsl(winPath: string): string {
  const m = winPath.match(/^([A-Za-z]):\\(.*)$/);
  if (!m) return winPath;
  return path.join('/mnt', m[1].toLowerCase(), m[2].replace(/\\/g, '/'));
}

/** User data dir for the Antigravity app. */
export function getAntigravityDataDir(): string {
  return path.join(os.homedir(), '.gemini', 'antigravity');
}

/** Path to the custom_models.json file. Profile-aware. */
export function getCustomModelsPath(): string {
  return getProfilePath('models');
}

/** Path to the active port file (if any). */
export function getActivePortFile(): string {
  return path.join(getAntigravityDataDir(), 'active_port');
}

/**
 * Possible install locations for Antigravity, ordered by likelihood.
 * Returns the first one that exists on disk.
 */
export function findAntigravityInstallDir(): string | null {
  const platform = getPlatform();
  const candidates: string[] = [];

  if (platform === 'win32') {
    const local = process.env.LOCALAPPDATA;
    if (local) {
      candidates.push(path.join(local, 'Programs', 'antigravity'));
    }
    candidates.push(path.join(os.homedir(), 'AppData', 'Local', 'Programs', 'antigravity'));
  } else if (platform === 'darwin') {
    candidates.push('/Applications/Antigravity.app');
    candidates.push(path.join(os.homedir(), 'Applications', 'Antigravity.app'));
  } else if (platform === 'linux') {
    candidates.push(path.join(os.homedir(), '.local', 'share', 'Programs', 'antigravity'));
    candidates.push('/opt/antigravity');
    candidates.push('/usr/lib/antigravity');
    candidates.push('/opt/Antigravity');
    candidates.push(path.join(os.homedir(), 'antigravity'));

    // WSL: also check the Windows-side install directories
    if (isWsl()) {
      const localAppData = process.env.LOCALAPPDATA;
      if (localAppData) {
        candidates.push(winToWsl(path.join(localAppData, 'Programs', 'Antigravity')));
      }
      candidates.push('/mnt/c/Users/' + (process.env.USER || os.userInfo().username) + '/AppData/Local/Programs/Antigravity');
      candidates.push('/mnt/c/Program Files/Antigravity');
      candidates.push('/mnt/c/Program Files (x86)/Antigravity');
    }
  }

  for (const dir of candidates) {
    if (fs.existsSync(dir)) return dir;
  }
  return null;
}

/**
 * Path to the language_server binary inside the Antigravity install.
 */
export function getLanguageServerBinary(installDir?: string): string | null {
  const dir = installDir ?? findAntigravityInstallDir();
  if (!dir) return null;
  const platform = getPlatform();
  if (platform === 'win32') {
    return path.join(dir, 'resources', 'bin', 'language_server.exe');
  }
  return path.join(dir, 'resources', 'bin', 'language_server');
}

/** Path to the backup of the original (unpatched) language server binary. */
export function getLanguageServerBackup(installDir?: string): string | null {
  const binary = getLanguageServerBinary(installDir);
  if (!binary) return null;
  return binary + '.bak';
}

/** Path to the app.asar archive inside the Antigravity install. */
export function getAppAsarPath(installDir?: string): string | null {
  const dir = installDir ?? findAntigravityInstallDir();
  if (!dir) return null;
  return path.join(dir, 'resources', 'app.asar');
}

/** Path to the LS log file. */
export function getLsLogPath(): string {
  const platform = getPlatform();
  if (platform === 'win32') {
    return path.join(process.env.APPDATA ?? os.homedir(), 'Antigravity', 'logs', 'language_server.log');
  }
  if (platform === 'darwin') {
    return path.join(os.homedir(), 'Library', 'Logs', 'Antigravity', 'language_server.log');
  }
  if (isWsl()) {
    const username = process.env.USER || os.userInfo().username;
    return `/mnt/c/Users/${username}/AppData/Roaming/Antigravity/logs/language_server.log`;
  }
  return path.join(os.homedir(), '.config', 'Antigravity', 'logs', 'language_server.log');
}
