/**
 * Connectivity check — pings each configured provider endpoint.
 */
import type { CheckResult } from '../types';
import { loadCustomModels } from '../core/custom-models';
import { probe } from '../core/probe';

export async function checkConnectivity(): Promise<CheckResult> {
  const file = loadCustomModels();
  if (file.models.length === 0) {
    return {
      id: 'connectivity',
      title: 'Provider connectivity',
      status: 'info',
      message: 'No models configured, nothing to probe',
    };
  }
  const urls = Array.from(new Set(file.models.map((m) => m.apiUrl).filter(Boolean)));
  const results = await Promise.all(urls.map((u) => probe(u, 5000)));
  const ok = results.filter((r) => r.ok).length;
  if (ok === results.length) {
    return {
      id: 'connectivity',
      title: 'Provider connectivity',
      status: 'ok',
      message: `All ${ok}/${results.length} endpoints reachable`,
      data: { results },
    };
  }
  if (ok === 0) {
    return {
      id: 'connectivity',
      title: 'Provider connectivity',
      status: 'error',
      message: `0/${results.length} endpoints reachable`,
      details: results.map((r) => `  ${r.ok ? '✔' : '✖'} ${r.url} — ${r.error ?? r.statusCode}`).join('\n'),
      data: { results },
    };
  }
  return {
    id: 'connectivity',
    title: 'Provider connectivity',
    status: 'warn',
    message: `${ok}/${results.length} endpoints reachable`,
    details: results.map((r) => `  ${r.ok ? '✔' : '✖'} ${r.url} — ${r.error ?? r.statusCode}`).join('\n'),
    data: { results },
  };
}
