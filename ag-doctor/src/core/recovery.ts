/**
 * Auto-recovery rules engine.
 *
 * Each rule defines:
 *   - id:           unique identifier
 *   - checkId:      which check.id it watches
 *   - status:       which status triggers it ('error' | 'warn')
 *   - action:       async function that attempts to fix the issue
 *   - cooldownMs:   minimum time between two consecutive executions
 *   - requiresConfirm: if true, the rule only runs in --auto mode
 *   - timeoutMs:    max time the action can take
 *
 * Rules are stored in:
 *   ~/.gemini/antigravity/recovery.json
 *
 * Built-in rules:
 *   - proxy-down        â†’ restart local proxy
 *   - patch-missing     â†’ re-apply binary patch
 *   - ca-not-installed  â†’ install CA cert (admin required)
 *   - models-corrupted  â†’ restore from latest snapshot
 *   - disk-full         â†’ cleanup old snapshots/history
 *   - connectivity-fail â†’ retry with exponential backoff
 */
import fs from 'fs';
import path from 'path';
import { getAntigravityDataDir } from './paths';
import { getProfilePath } from './profile';
import type { CheckResult } from '../types';

export interface RecoveryRule {
  id: string;
  checkId: string;
  status: 'error' | 'warn';
  title: string;
  description: string;
  cooldownMs: number;
  requiresConfirm: boolean;
  timeoutMs: number;
  enabled: boolean;
}

export interface RecoveryActionResult {
  ok: boolean;
  message: string;
  durationMs: number;
  details?: string;
  ruleId: string;
}

export interface RecoveryConfig {
  enabled: boolean;
  autoMode: boolean; // if false, only non-confirming rules run
  notifyOnRecovery: boolean;
  notifyWebhook?: string;
  logFile: string;
  rules: RecoveryRule[];
}

const DEFAULT_CONFIG: RecoveryConfig = {
  enabled: true,
  autoMode: false,
  notifyOnRecovery: false,
  logFile: 'recovery.log',
  rules: [
    {
      id: 'proxy-down',
      checkId: 'proxy',
      status: 'error',
      title: 'Restart local proxy',
      description: 'Restart the local proxy on port 50999 when it is unreachable',
      cooldownMs: 60_000,
      requiresConfirm: false,
      timeoutMs: 10_000,
      enabled: true,
    },
    {
      id: 'patch-missing',
      checkId: 'patch',
      status: 'error',
      title: 'Re-apply binary patch',
      description: 'Re-apply the binary patch when the language_server binary is unpatched',
      cooldownMs: 5 * 60_000,
      requiresConfirm: true,
      timeoutMs: 30_000,
      enabled: true,
    },
    {
      id: 'ca-not-installed',
      checkId: 'mitm',
      status: 'warn',
      title: 'Install MITM CA cert',
      description: 'Install the MITM CA certificate into the OS trust store (requires admin)',
      cooldownMs: 5 * 60_000,
      requiresConfirm: true,
      timeoutMs: 15_000,
      enabled: true,
    },
    {
      id: 'disk-full',
      checkId: 'disk_space',
      status: 'error',
      title: 'Cleanup old snapshots/history',
      description: 'Remove old snapshots and history entries to free disk space',
      cooldownMs: 60 * 60_000,
      requiresConfirm: false,
      timeoutMs: 30_000,
      enabled: true,
    },
    {
      id: 'connectivity-fail',
      checkId: 'connectivity',
      status: 'error',
      title: 'Retry provider connectivity',
      description: 'Retry failed provider endpoints with exponential backoff',
      cooldownMs: 30_000,
      requiresConfirm: false,
      timeoutMs: 60_000,
      enabled: true,
    },
  ],
};

export function getRecoveryConfigPath(): string {
  return getProfilePath('config').replace(/config\.json$/, 'recovery.json');
}

export function loadRecoveryConfig(): RecoveryConfig {
  const p = getRecoveryConfigPath();
  if (!fs.existsSync(p)) return { ...DEFAULT_CONFIG, rules: [...DEFAULT_CONFIG.rules] };
  try {
    const raw = JSON.parse(fs.readFileSync(p, 'utf-8'));
    const merged: RecoveryConfig = {
      ...DEFAULT_CONFIG,
      ...raw,
      rules: Array.isArray(raw.rules) ? raw.rules : DEFAULT_CONFIG.rules,
    };
    return merged;
  } catch {
    return { ...DEFAULT_CONFIG, rules: [...DEFAULT_CONFIG.rules] };
  }
}

export function saveRecoveryConfig(cfg: RecoveryConfig): void {
  const p = getRecoveryConfigPath();
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, JSON.stringify(cfg, null, 2) + '\n', 'utf-8');
}

export function resetRecoveryConfig(): RecoveryConfig {
  saveRecoveryConfig(DEFAULT_CONFIG);
  return { ...DEFAULT_CONFIG, rules: [...DEFAULT_CONFIG.rules] };
}

/** Get a rule by id. */
export function getRecoveryRule(id: string): RecoveryRule | null {
  return loadRecoveryConfig().rules.find((r) => r.id === id) ?? null;
}

/** Enable or disable a rule. */
export function setRuleEnabled(id: string, enabled: boolean): boolean {
  const cfg = loadRecoveryConfig();
  const rule = cfg.rules.find((r) => r.id === id);
  if (!rule) return false;
  rule.enabled = enabled;
  saveRecoveryConfig(cfg);
  return true;
}

// â”€â”€â”€ Recovery actions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

/** Run a recovery action with timeout. */
async function withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
  return Promise.race([
    p,
    new Promise<T>((_, reject) => setTimeout(() => reject(new Error(`timeout after ${ms}ms`)), ms)),
  ]);
}

/** Recovery action: restart local proxy. */
async function restartProxy(rule: RecoveryRule): Promise<RecoveryActionResult> {
  const start = Date.now();
  try {
    // The proxy is started by the parent process (Antigravity). We can ping it
    // and try to trigger a restart by sending a signal to the parent PID.
    const port = 50999;
    const pingRes = await fetch(`http://127.0.0.1:${port}/health`, {
      signal: AbortSignal.timeout(2000),
    }).catch(() => null);

    if (pingRes && pingRes.ok) {
      return {
        ok: true,
        message: `Proxy already reachable on port ${port}`,
        durationMs: Date.now() - start,
        ruleId: rule.id,
      };
    }

    // Try to find the parent process and restart it via the parent's IPC.
    // For now, we log a clear instruction.
    return {
      ok: false,
      message: `Proxy unreachable on port ${port}. Restart Antigravity to recover.`,
      details: 'Auto-restart requires IPC with the parent process.',
      durationMs: Date.now() - start,
      ruleId: rule.id,
    };
  } catch (e) {
    return {
      ok: false,
      message: `Failed to check proxy: ${(e as Error).message}`,
      durationMs: Date.now() - start,
      ruleId: rule.id,
    };
  }
}

/** Recovery action: re-apply binary patch.
 *  Note: This is intentionally conservative â€” we don't kill the running app
 *  from a background daemon. We only verify the patch state and report.
 *  The user must run `ag-doctor patch apply` manually.
 */
async function reapplyPatch(rule: RecoveryRule): Promise<RecoveryActionResult> {
  const start = Date.now();
  try {
    const { getPatchStatus } = await import('./binary-patch');
    const status = getPatchStatus();
    if (status.applied) {
      return {
        ok: true,
        message: 'Patch already applied â€” nothing to do',
        durationMs: Date.now() - start,
        ruleId: rule.id,
      };
    }
    return {
      ok: false,
      message: 'Patch not applied â€” manual intervention required',
      details: 'Run `ag-doctor patch apply` (this requires closing Antigravity first).',
      durationMs: Date.now() - start,
      ruleId: rule.id,
    };
  } catch (e) {
    return {
      ok: false,
      message: `Failed to check patch status: ${(e as Error).message}`,
      durationMs: Date.now() - start,
      ruleId: rule.id,
    };
  }
}

/** Recovery action: install MITM CA. */
async function installCa(rule: RecoveryRule): Promise<RecoveryActionResult> {
  const start = Date.now();
  try {
    const { installCaCert } = await import('./mitm');
    const result = await withTimeout(installCaCert(), rule.timeoutMs);
    return {
      ok: result.ok,
      message: result.message,
      durationMs: Date.now() - start,
      ruleId: rule.id,
    };
  } catch (e) {
    return {
      ok: false,
      message: `Failed to install CA: ${(e as Error).message}`,
      durationMs: Date.now() - start,
      ruleId: rule.id,
    };
  }
}

/** Recovery action: cleanup old snapshots/history. */
async function cleanupDisk(rule: RecoveryRule): Promise<RecoveryActionResult> {
  const start = Date.now();
  try {
    const { listSnapshots, deleteSnapshot } = await import('./snapshot');
    const { listHistory, deleteHistory } = await import('./history');

    let freedBytes = 0;
    let removedSnapshots = 0;
    let removedHistory = 0;

    // Keep only the 5 most recent snapshots
    const snaps = listSnapshots();
    const oldSnaps = snaps.slice(5);
    for (const s of oldSnaps) {
      try {
        deleteSnapshot(s.id);
        removedSnapshots++;
        freedBytes += s.sizeBytes;
      } catch {
        // continue
      }
    }

    // Keep only the 20 most recent history entries
    const hist = listHistory();
    const oldHist = hist.slice(20);
    for (const h of oldHist) {
      try {
        deleteHistory(h.id);
        removedHistory++;
      } catch {
        // continue
      }
    }

    return {
      ok: true,
      message: `Cleanup complete: removed ${removedSnapshots} snapshots, ${removedHistory} history entries`,
      details: `Freed approximately ${(freedBytes / 1024 / 1024).toFixed(1)} MB`,
      durationMs: Date.now() - start,
      ruleId: rule.id,
    };
  } catch (e) {
    return {
      ok: false,
      message: `Cleanup failed: ${(e as Error).message}`,
      durationMs: Date.now() - start,
      ruleId: rule.id,
    };
  }
}

/**
 * Recovery action: retry connectivity.
 *
 * Improved: instead of counting any non-ok probe as "failed", we classify each
 * probe outcome. Only true unreachable errors (timeout, DNS, TCP refused) are
 * retried with exponential backoff. Path/auth errors (4xx/5xx with reachable=true)
 * are surfaced but skipped â€” retrying them achieves nothing, since the cause is
 * configuration, not network. This avoids log spam and false-positive recoveries.
 */
async function retryConnectivity(rule: RecoveryRule): Promise<RecoveryActionResult> {
  const start = Date.now();
  try {
    const { checkConnectivity } = await import('../checks/connectivity');
    const { probe } = await import('./probe');
    const { buildModelsUrl } = await import('../commands/models/fetch');
    const { loadCustomModels } = await import('./custom-models');

    const initial = await checkConnectivity();
    const data = initial.data as
      | { results?: Array<{ source: string; target: string; result: { ok: boolean; statusCode?: number; error?: string } }> }
      | undefined;
    const results = data?.results ?? [];

    // Classify and count true unreachable vs reachable-but-4xx/5xx
    let trulyDown = 0;
    let reachableButBad = 0;
    for (const { result } of results) {
      if (!result.ok) trulyDown++;
      else if (typeof result.statusCode === 'number' && result.statusCode >= 400) reachableButBad++;
    }

    if (trulyDown === 0) {
      return {
        ok: true,
        message:
          reachableButBad > 0
            ? `All hosts reachable (${reachableButBad} still returning 4xx/5xx â€” config issue, not a network problem)`
            : 'All providers reachable',
        details: JSON.stringify(initial, null, 2),
        durationMs: Date.now() - start,
        ruleId: rule.id,
      };
    }

    // Exponential backoff retry: 1s, 2s, 4s, 8s â€” capped at 4 attempts total
    const backoffMs = [1000, 2000, 4000, 8000];
    const file = loadCustomModels();
    const urlToModel = new Map<string, (typeof file.models)[number]>();
    for (const m of file.models) {
      if (!m.apiUrl) continue;
      if (!urlToModel.has(m.apiUrl)) {
        urlToModel.set(m.apiUrl, m);
      } else if (m.apiKey && !m.apiKey.startsWith('enc:') && urlToModel.get(m.apiUrl)?.apiKey?.startsWith('enc:')) {
        urlToModel.set(m.apiUrl, m);
      }
    }
    const urls = Array.from(urlToModel.keys());

    let lastResult = initial;
    for (let attempt = 0; attempt < backoffMs.length; attempt++) {
      await new Promise((r) => setTimeout(r, backoffMs[attempt]));
      const probes = await Promise.all(urls.map(async (u) => {
        const target = buildModelsUrl(u);
        const model = urlToModel.get(u);
        return {
          source: u,
          target,
          result: await probe(target, 5000, { provider: model?.provider, apiKey: model?.apiKey }),
        };
      }));
      const stillDown = probes.filter(({ result }) => !result.ok).length;
      if (stillDown === 0) {
        return {
          ok: true,
          message: `Recovered after ${attempt + 1} retry(ies) â€” ${urls.length}/${urls.length} endpoints reachable`,
          details: JSON.stringify({ results: probes }, null, 2),
          durationMs: Date.now() - start,
          ruleId: rule.id,
        };
      }
      lastResult = { ...initial, data: { results: probes } };
    }

    return {
      ok: false,
      message: `${trulyDown} endpoint(s) still unreachable after retries (${reachableButBad} returning 4xx/5xx â€” config issue)`,
      details: JSON.stringify(lastResult, null, 2),
      durationMs: Date.now() - start,
      ruleId: rule.id,
    };
  } catch (e) {
    return {
      ok: false,
      message: `Connectivity retry failed: ${(e as Error).message}`,
      durationMs: Date.now() - start,
      ruleId: rule.id,
    };
  }
}

const ACTIONS: Record<string, (rule: RecoveryRule) => Promise<RecoveryActionResult>> = {
  'proxy-down': restartProxy,
  'patch-missing': reapplyPatch,
  'ca-not-installed': installCa,
  'disk-full': cleanupDisk,
  'connectivity-fail': retryConnectivity,
};

/** Execute a recovery action by rule id. */
export async function runRecoveryAction(ruleId: string): Promise<RecoveryActionResult | null> {
  const rule = getRecoveryRule(ruleId);
  if (!rule) return null;
  const action = ACTIONS[ruleId];
  if (!action) {
    return {
      ok: false,
      message: `No action handler for rule "${ruleId}"`,
      durationMs: 0,
      ruleId,
    };
  }
  return await withTimeout(action(rule), rule.timeoutMs);
}

// â”€â”€â”€ Rule evaluation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

interface CooldownTracker {
  [ruleId: string]: number;
}

const lastRun: CooldownTracker = {};

/** Find rules that should fire given a set of check results. */
export function findApplicableRules(
  results: CheckResult[],
  cfg: RecoveryConfig,
): RecoveryRule[] {
  const applicable: RecoveryRule[] = [];
  for (const rule of cfg.rules) {
    if (!rule.enabled) continue;
    if (!cfg.enabled) continue;
    if (rule.requiresConfirm && !cfg.autoMode) continue;

    // Check cooldown
    const last = lastRun[rule.id] ?? 0;
    if (Date.now() - last < rule.cooldownMs) continue;

    // Find a matching check
    const check = results.find((r) => r.id === rule.checkId);
    if (!check) continue;
    if (check.status !== rule.status) continue;

    applicable.push(rule);
  }
  return applicable;
}

/** Run all applicable rules for the given check results. */
export async function runRecovery(
  results: CheckResult[],
  cfg: RecoveryConfig,
): Promise<RecoveryActionResult[]> {
  const rules = findApplicableRules(results, cfg);
  const outcomes: RecoveryActionResult[] = [];

  for (const rule of rules) {
    lastRun[rule.id] = Date.now();
    const outcome = await runRecoveryAction(rule.id);
    if (outcome) outcomes.push(outcome);

    if (cfg.notifyOnRecovery && cfg.notifyWebhook) {
      await notifyWebhook(cfg.notifyWebhook, { rule, outcome }).catch(() => undefined);
    }
  }

  return outcomes;
}

async function notifyWebhook(url: string, payload: unknown): Promise<void> {
  await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      source: 'ag-doctor',
      timestamp: new Date().toISOString(),
      payload,
    }),
    signal: AbortSignal.timeout(5000),
  });
}

/** Reset cooldown tracker (useful for tests). */
export function resetCooldowns(): void {
  for (const k of Object.keys(lastRun)) delete lastRun[k];
}

