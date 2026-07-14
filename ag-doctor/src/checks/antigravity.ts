/**
 * Doctor check: Antigravity install + version + running state.
 */
import type { CheckResult } from '../types';
import { getAntigravityStatus } from '../core/antigravity';

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
