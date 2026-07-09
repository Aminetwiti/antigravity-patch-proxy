/**
 * Proxy check — verifies the local proxy is reachable on port 50999.
 *
 * Improvements over original:
 *  - Detects whether the proxy is the real proxy or an emergency stub
 *    (by reading the X-Proxy-Stub response header set by proxy-stub.js).
 *  - Reports stub mode as a warning with guidance to run repack.ps1.
 *  - Separates ECONNREFUSED (port closed) from other errors.
 */
import type { CheckResult } from '../types';
import { probe } from '../core/probe';

export async function checkProxy(port = 50999): Promise<CheckResult> {
  const result = await probe(`http://127.0.0.1:${port}/health`, 2000);

  if (!result.ok) {
    const isRefused = (result.error ?? '').toLowerCase().includes('econnrefused') ||
                      (result.error ?? '').toLowerCase().includes('actively refused') ||
                      (result.error ?? '').toLowerCase().includes('connection refused');
    return {
      id: 'proxy',
      title: 'Local proxy',
      status: 'warn',
      message: `Not reachable on port ${port}: ${result.error ?? 'unknown'}`,
      details: isRefused
        ? 'Port is closed — Antigravity may not be running. Launch Antigravity or run proxy-stub.js as a temporary workaround.'
        : 'The proxy starts automatically when Antigravity launches.',
      fixable: false,
      data: result,
    };
  }

  // Check if this is the stub proxy (emergency fallback) rather than the real one
  const isStub = result.headers?.['x-proxy-stub'] === '1';

  if (isStub) {
    return {
      id: 'proxy',
      title: 'Local proxy',
      status: 'warn',
      message: `Reachable on http://127.0.0.1:${port} (${result.latencyMs}ms) — stub mode only`,
      details: [
        'The proxy stub is active. Custom models will NOT be injected into Antigravity.',
        'To enable full proxy support, run repack.ps1 to update the bundled app.asar:',
        '  .\\repack.ps1',
        'Then restart Antigravity. The stub can remain running as a fallback.',
      ].join('\n'),
      fixable: false,
      data: result,
    };
  }

  return {
    id: 'proxy',
    title: 'Local proxy',
    status: 'ok',
    message: `Reachable on http://127.0.0.1:${port} (${result.latencyMs}ms)`,
    data: result,
  };
}
