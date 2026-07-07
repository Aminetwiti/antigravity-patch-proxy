/**
 * Proxy check — verifies the local proxy is reachable on port 50999.
 */
import type { CheckResult } from '../types';
import { probe } from '../core/probe';

export async function checkProxy(port = 50999): Promise<CheckResult> {
  const result = await probe(`http://127.0.0.1:${port}/health`, 2000);
  if (result.ok) {
    return {
      id: 'proxy',
      title: 'Local proxy',
      status: 'ok',
      message: `Reachable on http://127.0.0.1:${port} (${result.latencyMs}ms)`,
      data: result,
    };
  }
  return {
    id: 'proxy',
    title: 'Local proxy',
    status: 'warn',
    message: `Not reachable on port ${port}: ${result.error ?? 'unknown'}`,
    details: 'The proxy starts automatically when Antigravity launches',
    fixable: false,
    data: result,
  };
}
