/**
 * Model Health Checker for Antigravity Proxy
 * Performs concurrent lightweight ping/health checks on custom model endpoints
 * to display status dots (🟢🟡🔴) and dynamic latency (ms) in the IDE model dropdown.
 */

import http from 'http';
import https from 'https';
import log from 'electron-log';
import type { CustomModel } from './types';

export interface ModelHealthResult {
  status: 'healthy' | 'slow' | 'unhealthy';
  statusCode?: number;
  latencyMs: number;
  error?: string;
}

/** Health check results cache (model name -> result) with 30s TTL */
const healthCache = new Map<string, { result: ModelHealthResult; expiresAt: number }>();
const CACHE_TTL_MS = 30_000;
const HEALTH_CHECK_TIMEOUT_MS = 800;

/** Ping a single custom model endpoint with strict timeout */
export function pingCustomModel(model: CustomModel): Promise<ModelHealthResult> {
  const cached = healthCache.get(model.name);
  if (cached && Date.now() < cached.expiresAt) {
    return Promise.resolve(cached.result);
  }

  return new Promise((resolve) => {
    const startTime = Date.now();
    let settled = false;

    const finish = (result: ModelHealthResult) => {
      if (settled) return;
      settled = true;
      healthCache.set(model.name, { result, expiresAt: Date.now() + CACHE_TTL_MS });
      resolve(result);
    };

    const timer = setTimeout(() => {
      finish({
        status: 'unhealthy',
        latencyMs: Date.now() - startTime,
        error: 'Timeout (>800ms)',
      });
    }, HEALTH_CHECK_TIMEOUT_MS);

    try {
      const url = new URL(model.apiUrl);
      const isHttps = url.protocol === 'https:';
      const client = isHttps ? https : http;

      const req = client.request(
        model.apiUrl,
        {
          method: 'GET',
          timeout: HEALTH_CHECK_TIMEOUT_MS,
          rejectUnauthorized: model.allowUnauthorized ? false : true,
          headers: {
            'User-Agent': 'Antigravity-HealthCheck/1.0',
            ...(model.apiKey && model.apiKey !== 'none' ? { Authorization: `Bearer ${model.apiKey}` } : {}),
          },
        },
        (res) => {
          clearTimeout(timer);
          const latencyMs = Date.now() - startTime;
          const statusCode = res.statusCode || 0;
          // Consume response body to free socket
          res.resume();

          if (statusCode === 429) {
            finish({ status: 'unhealthy', statusCode, latencyMs, error: 'Rate Limited (429)' });
          } else if (statusCode === 401 || statusCode === 403) {
            finish({ status: 'unhealthy', statusCode, latencyMs, error: 'Auth Error' });
          } else if (statusCode >= 500) {
            finish({ status: 'unhealthy', statusCode, latencyMs, error: `Server Error (${statusCode})` });
          } else if (latencyMs > 500) {
            finish({ status: 'slow', statusCode, latencyMs });
          } else {
            finish({ status: 'healthy', statusCode, latencyMs });
          }
        },
      );

      req.on('error', (err) => {
        clearTimeout(timer);
        finish({
          status: 'unhealthy',
          latencyMs: Date.now() - startTime,
          error: err.message,
        });
      });

      req.end();
    } catch (e) {
      clearTimeout(timer);
      finish({
        status: 'unhealthy',
        latencyMs: 0,
        error: String(e),
      });
    }
  });
}

/** Check health of all custom models concurrently */
export async function checkAllModelsHealth(models: CustomModel[]): Promise<Map<string, ModelHealthResult>> {
  const results = new Map<string, ModelHealthResult>();
  log.info(`[HealthChecker] Checking health for ${models.length} custom models concurrently...`);

  const checks = models.map(async (model) => {
    const health = await pingCustomModel(model);
    results.set(model.name, health);
  });

  await Promise.allSettled(checks);
  return results;
}
