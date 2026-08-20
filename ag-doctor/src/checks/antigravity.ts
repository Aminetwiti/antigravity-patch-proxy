/**
 * Doctor check: Antigravity install + version + running state.
 */
import type { CheckResult } from '../types';
import { getAntigravityStatus } from '../core/antigravity';
import { findAntigravityIdeInstallDir, getIdeExecutable } from '../core/paths';
import { getIdeVersion } from '../core/ide-patch';

export async function checkAntigravity(): Promise<CheckResult> {
  const status = await getAntigravityStatus();
  if (!status.installed) {
    return {
      id: 'antigravity.install',
      title: 'Antigravity installation',
      status: 'error',
      message: 'Antigravity executable not found in standard locations',
      fixable: false,
    };
  }

  const v = status.versionInfo?.version ?? status.version ?? 'unknown';
  const running = status.running ? 'running' : 'not running';
  const proxy = status.proxyReachable ? 'reachable' : 'unreachable';
  const parts = [`v${v}`, running, `proxy ${proxy}`];

  // The VS Code-based Antigravity IDE is the product the user actually runs;
  // surface it alongside the classic install state.
  const ideDir = findAntigravityIdeInstallDir();
  const ideExe = ideDir ? getIdeExecutable(ideDir) : null;
  if (ideExe) {
    const ideVersion = getIdeVersion(ideDir ?? undefined);
    parts.push(`IDE ${ideVersion ? `v${ideVersion}` : 'installed'}`);
  }

  // The system is operational when either the app is running OR the local
  // proxy answers (the proxy is what actually serves the custom models, and
  // it can keep running after the IDE window is closed or via the stub).
  // Only warn when the service is genuinely down — not running AND proxy
  // unreachable.
  const operational = status.running || status.proxyReachable;
  const overall: 'ok' | 'warn' | 'error' = operational ? 'ok' : 'warn';

  return {
    id: 'antigravity',
    title: 'Antigravity installation',
    status: overall,
    message: `${parts.join(' · ')}`,
    data: status,
  };
}
