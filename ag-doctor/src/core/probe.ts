/**
 * Connectivity probe — pings an endpoint and reports latency / status.
 * Uses Node's built-in http/https modules, no third-party deps.
 *
 * Reachability semantics:
 *   - 2xx → reachable (success)
 *   - 3xx → reachable (redirect; not followed for a connectivity probe)
 *   - 4xx → reachable (server responded, path not found / unauthorized)
 *   - 5xx → reachable (server responded, upstream error)
 *   - network error / timeout → unreachable
 *
 * This matches the spirit of "is the endpoint up?" rather than
 * "does this specific path return 200?".
 *
 * Improvements over the original:
 *   - Distinguishes reachable vs unreachable (was: any response = ok).
 *   - `probeWithProxy` no longer leaks sockets on error paths.
 *   - Adds an explicit socket timeout with cleanup.
 *   - Avoids hanging on unreachable proxies via a hard deadline.
 */
import http from 'http';
import https from 'https';
import { URL } from 'url';
import type { ConnectivityResult } from '../types';

/** A response counts as "reachable" if we got any HTTP status back. */
function isReachable(code: number | undefined): boolean {
  return typeof code === 'number' && code >= 200 && code < 600;
}

/** A response counts as "success" only for 2xx. */
function isSuccess(code: number | undefined): boolean {
  return typeof code === 'number' && code >= 200 && code < 300;
}

export async function probe(url: string, timeoutMs = 5000): Promise<ConnectivityResult> {
  const started = Date.now();
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch (e) {
    return { url, ok: false, error: `invalid URL: ${(e as Error).message}` };
  }
  return new Promise((resolve) => {
    let settled = false;
    const deadline = setTimeout(() => {
      if (settled) return;
      settled = true;
      resolve({ url, ok: false, latencyMs: Date.now() - started, error: 'hard deadline reached' });
    }, timeoutMs * 2 + 1000);
    const finish = (res: ConnectivityResult) => {
      if (settled) return;
      settled = true;
      clearTimeout(deadline);
      resolve(res);
    };
    const lib = parsed.protocol === 'https:' ? https : http;
    const req = lib.request(
      {
        method: 'GET',
        hostname: parsed.hostname,
        port: parsed.port || (parsed.protocol === 'https:' ? 443 : 80),
        path: parsed.pathname + parsed.search,
        timeout: timeoutMs,
        headers: { 'User-Agent': 'ag-doctor/1.0' },
      },
      (res) => {
        // Drain body to free the socket
        let body = '';
        res.setEncoding('utf8');
        res.on('data', (chunk: string) => { body += chunk; });
        res.on('end', () => {
          const reachable = isReachable(res.statusCode);
          const success = isSuccess(res.statusCode);
          // Expose selected headers for callers (e.g. X-Proxy-Stub detection)
          const headers: Record<string, string> = {};
          for (const [k, v] of Object.entries(res.headers)) {
            if (v != null) headers[k] = Array.isArray(v) ? v[0] : String(v);
          }
          finish({
            url,
            ok: reachable,
            latencyMs: Date.now() - started,
            statusCode: res.statusCode,
            headers,
            body: body.slice(0, 512), // first 512 chars for diagnostics
            ...(success ? {} : { error: `HTTP ${res.statusCode}` }),
          });
        });
        res.on('error', (err) => {
          finish({ url, ok: false, latencyMs: Date.now() - started, error: err.message });
        });
      },
    );
    req.on('timeout', () => {
      finish({ url, ok: false, latencyMs: Date.now() - started, error: 'timeout' });
      try { req.destroy(); } catch { /* ignore */ }
    });
    req.on('error', (err) => {
      finish({ url, ok: false, latencyMs: Date.now() - started, error: err.message });
    });
    req.on('close', () => {
      finish({ url, ok: false, latencyMs: Date.now() - started, error: 'connection closed' });
    });
    req.end();
  });
}


export async function probeWithProxy(
  url: string,
  timeoutMs = 5000,
  proxyUrl?: string,
): Promise<ConnectivityResult> {
  if (!proxyUrl) return probe(url, timeoutMs);
  const started = Date.now();
  let parsed: URL;
  let proxyParsed: URL;
  try {
    parsed = new URL(url);
    proxyParsed = new URL(proxyUrl);
  } catch (e) {
    return { url, ok: false, error: `invalid URL: ${(e as Error).message}` };
  }

  // Hard deadline: if neither CONNECT nor the inner TLS request completes in
  // `timeoutMs`, we resolve with an error rather than hanging forever.
  return new Promise<ConnectivityResult>((resolve) => {
    let settled = false;
    // Absolute deadline: guarantees the promise resolves within 2*timeoutMs
    // even if every event handler fails to fire (e.g., socket in a bad state).
    const deadline = setTimeout(() => {
      if (settled) return;
      settled = true;
      resolve({ url, ok: false, latencyMs: Date.now() - started, error: 'hard deadline reached' });
    }, timeoutMs * 2 + 1000);
    const settle = (res: ConnectivityResult) => {
      if (settled) return;
      settled = true;
      clearTimeout(deadline);
      resolve(res);
    };
    const proxyReq = http.request(
      {
        method: 'CONNECT',
        hostname: proxyParsed.hostname,
        port: proxyParsed.port || 80,
        path: `${parsed.hostname}:${parsed.port || 443}`,
        timeout: timeoutMs,
        headers: { 'User-Agent': 'ag-doctor/1.0' },
        agent: false,
      },
      (proxyRes) => {
        if (settled) return;
        if (proxyRes.statusCode !== 200) {
          // Destroy the socket so we don't leak it.
          proxyRes.socket?.destroy();
          settle({
            url,
            ok: false,
            latencyMs: Date.now() - started,
            error: `proxy CONNECT ${proxyRes.statusCode}`,
          });
          return;
        }
        const socket = proxyRes.socket;
        if (!socket) {
          settle({ url, ok: false, latencyMs: Date.now() - started, error: 'proxy returned no socket' });
          return;
        }
        const tlsReq = https.request(
          {
            method: 'GET',
            hostname: parsed.hostname,
            port: Number(parsed.port || 443),
            path: parsed.pathname + parsed.search,
            timeout: timeoutMs,
            headers: { 'User-Agent': 'ag-doctor/1.0' },
            createConnection: () => socket,
            agent: false,
          } as https.RequestOptions,
          (res) => {
            res.resume();
            const reachable = isReachable(res.statusCode);
            const success = isSuccess(res.statusCode);
            settle({
              url,
              ok: reachable,
              latencyMs: Date.now() - started,
              statusCode: res.statusCode,
              ...(success ? {} : { error: `HTTP ${res.statusCode}` }),
            });
          },
        );
        tlsReq.on('timeout', () => {
          settle({ url, ok: false, latencyMs: Date.now() - started, error: 'TLS timeout' });
          try { tlsReq.destroy(); } catch { /* ignore */ }
        });
        tlsReq.on('error', (err) => {
          settle({ url, ok: false, latencyMs: Date.now() - started, error: err.message });
        });
        tlsReq.on('close', () => {
          // Safety net: if neither timeout nor error fired, resolve with a generic error.
          settle({ url, ok: false, latencyMs: Date.now() - started, error: 'TLS connection closed' });
        });
        tlsReq.end();
      },
    );
    proxyReq.on('timeout', () => {
      settle({ url, ok: false, latencyMs: Date.now() - started, error: 'proxy timeout' });
      try { proxyReq.destroy(); } catch { /* ignore */ }
    });
    proxyReq.on('error', (err) => {
      settle({ url, ok: false, latencyMs: Date.now() - started, error: err.message });
    });
    proxyReq.on('close', () => {
      // Safety net: if neither timeout nor error fired, resolve with a generic error.
      settle({ url, ok: false, latencyMs: Date.now() - started, error: 'proxy connection closed' });
    });
    proxyReq.end();
  });
}
