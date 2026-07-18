// ─── Constants ─────────────────────────────────────────────────────────────

import * as http from 'http';
import * as https from 'https';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import { app } from 'electron';
import log from 'electron-log';

let server: http.Server | null = null;
let proxyPort = 0;

import {
  GOOGLE_PROXY_TIMEOUT_MS,
  FILE_DOWNLOAD_TIMEOUT_MS,
  FALLBACK_PROXY_PORTS,
  ACTIVE_PORT_FILE,
} from './constants';

// ─── Types ────────────────────────────────────────────────────────────────

import type { CustomModel, GeminiRequestBody, GeminiCandidate, CloudCodeResponse } from './proxy/types';
export type { CustomModel, GeminiRequestBody, GeminiCandidate, CloudCodeResponse };

// ─── Module Imports ───────────────────────────────────────────────────────

// Shared cross-turn state
import {
  modelToolCallIds,
  modelReasoningContent,
  activeStreamContexts,
  translatedToolCalls,
  stateTimestamps,
  touchStateTimestamp,
  startCleanupInterval,
  stopCleanupInterval,
} from './proxy/shared';

// Model configuration & capability detection
import { detectModelCapabilities } from './proxy/modelUtils';

// Provider translator registry (auto-discovers translators from proxy/translators/)
import * as registry from './proxy/registry';

// Protobuf injection (extracted from proxy.ts)
import { injectCustomModelsIntoResponse } from './proxy/protoInjector';

// Custom model loading (extracted from proxy.ts)
import { loadCustomModels } from './proxy/modelLoader';
import { classifyError, ErrorDiagnostic } from './proxy/errorClassifier';
import { shouldRetryStatus } from './proxy/retryStrategy';

function generateGracefulMarkdown(diagnostic: ErrorDiagnostic): string {
  let md = `🚨 **${diagnostic.title}**\n\n${diagnostic.message}\n\n`;
  if (diagnostic.suggestions && diagnostic.suggestions.length > 0) {
    md += `**Suggested Actions:**\n`;
    diagnostic.suggestions.forEach(s => md += `- ${s}\n`);
  }
  if (diagnostic.actionUrl) {
    md += `\n🔗 [Manage Billing & Credits](${diagnostic.actionUrl})`;
  }
  md += `\n\n<span class="ag-system-error-marker" data-type="${diagnostic.errorType}" style="display:none;"></span>`;
  return md;
}

// URL construction for custom model requests (extracted from proxy.ts)
import {
  resolveProvider,
  resolveCustomModelUrl,
  resolveMaxRetries,
  resolveRequestTimeout,
} from './proxy/urlBuilder';

// ID generation (extracted from proxy.ts)
import { generateModelPlaceholderId, toSlug } from './proxy/idGenerator';
export { generateModelPlaceholderId, toSlug };

// DNS resolution bypasses the poisoned hosts file (extracted from proxy.ts)
import { resolveGoogleIp } from './proxy/dnsResolver';

// ─── Safe Response Helpers ─────────────────────────────────────────────────
// Guard flag pattern to prevent ERR_HTTP_HEADERS_SENT when timeout and
// upstream response race. Returns true if the operation succeeded, false if
// the response was already terminated.

function safeWriteHead(
  res: http.ServerResponse,
  status: number,
  headers?: Record<string, string>,
): boolean {
  if (res.headersSent || res.writableEnded) {
    return false;
  }
  try {
    res.writeHead(status, headers);
    return true;
  } catch (err) {
    log.warn('[Proxy] safeWriteHead failed:', (err as Error).message);
    return false;
  }
}

function safeEnd(res: http.ServerResponse, data?: string | Buffer): boolean {
  if (res.writableEnded) {
    return false;
  }
  try {
    res.end(data);
    return true;
  } catch (err) {
    log.warn('[Proxy] safeEnd failed:', (err as Error).message);
    return false;
  }
}

// ─── Model Helpers ────────────────────────────────────────────────────────

// generateModelPlaceholderId and toSlug are now in ./proxy/idGenerator.ts (re-exported above)

// ─── Google Proxy ─────────────────────────────────────────────────────────

async function proxyToGoogle(req: http.IncomingMessage, res: http.ServerResponse, reqBody: Buffer): Promise<void> {
  const isCloudCodeUrl = req.url!.includes('v1internal') || req.url!.includes('daily-cloudcode');
  const targetHost = isCloudCodeUrl ? 'daily-cloudcode-pa.googleapis.com' : 'generativelanguage.googleapis.com';
  const targetUrl = `https://${targetHost}`;
  const parsedUrl = new URL(req.url!, targetUrl);

  try {
    const realIp = await resolveGoogleIp(targetHost);
    parsedUrl.hostname = realIp;
  } catch (e) {
    log.error(`[Proxy] Could not resolve upstream IP for ${targetHost}:`, e);
    if (safeWriteHead(res, 500, { 'Content-Type': 'application/json' })) {
      safeEnd(res, JSON.stringify({ error: { message: 'DNS resolution failed for ' + targetHost } }));
    }
    return;
  }

  const headers: Record<string, string | string[] | undefined> = {
    ...(req.headers as Record<string, string | string[] | undefined>),
  };
  headers['host'] = targetHost;
  delete headers['connection'];
  delete headers['keep-alive'];

  const isGeneration = req.url!.includes('generateContent') || req.url!.includes('streamGenerateContent');
  const shouldBufferAndModify = isCloudCodeUrl && !isGeneration;

  if (shouldBufferAndModify) {
    delete headers['accept-encoding'];
  }

  const options: https.RequestOptions = {
    method: req.method,
    headers: headers as Record<string, string>,
    servername: targetHost,
  };

  // Guard flag to prevent ERR_HTTP_HEADERS_SENT when timeout and response race
  const safeHead = (status: number, headers?: Record<string, string>): boolean =>
    safeWriteHead(res, status, headers);

  const proxyReq = https.request(parsedUrl, options, (proxyRes) => {
    proxyReq.setTimeout(GOOGLE_PROXY_TIMEOUT_MS, () => {
      log.error(`[Proxy] Google proxy request timed out after ${GOOGLE_PROXY_TIMEOUT_MS / 1000}s`);
      proxyReq.destroy();
      if (safeHead(504, { 'Content-Type': 'application/json' })) {
        safeEnd(res, JSON.stringify({ error: { message: 'Google API request timed out' } }));
      }
    });

    if (shouldBufferAndModify) {
      const responseChunks: Buffer[] = [];
      proxyRes.on('data', (chunk) => responseChunks.push(chunk));
      proxyRes.on('end', () => {
        if (res.headersSent || res.writableEnded) {
          log.debug('[Proxy] Skipping buffered modify: response already terminated');
          return;
        }
        const fullResBody = Buffer.concat(responseChunks);
        let text: string;
        const encoding = proxyRes.headers['content-encoding'];
        if (encoding === 'gzip') {
          try {
            const zlib = require('zlib');
            text = zlib.gunzipSync(fullResBody).toString('utf-8');
          } catch (e) {
            log.error('[Proxy] gunzipSync failed:', e);
            text = fullResBody.toString('utf-8');
          }
        } else {
          text = fullResBody.toString('utf-8');
        }

        log.info(
          `[Proxy] Response for ${req.url} (status: ${proxyRes.statusCode}, encoding: ${encoding}, length: ${text.length})`,
        );
        // P0-3: Response body content is NOT logged to disk. Only metadata.

        const proxyHost = req.headers.host || 'localhost';
        const proxyProto = proxyHost.endsWith('.googleapis.com') ? 'https:' : 'http:';
        text = text.replace(/https:(\/\/)daily-cloudcode-pa\.googleapis\.com/g, `${proxyProto}$1${proxyHost}`);
        text = text.replace(/https:(\/\/)cloudcode-pa\.googleapis\.com/g, `${proxyProto}$1${proxyHost}`);
        text = text.replace(/https:(\/\/)generativelanguage\.googleapis\.com/g, `${proxyProto}$1${proxyHost}`);

        const modifiedHeaders: Record<string, string | string[] | undefined> = { ...proxyRes.headers };
        delete modifiedHeaders['content-encoding'];
        delete modifiedHeaders['transfer-encoding'];

        const modifiedBuffer = Buffer.from(text, 'utf-8');
        modifiedHeaders['content-length'] = String(modifiedBuffer.length);

        if (safeWriteHead(res, proxyRes.statusCode || 200, modifiedHeaders as Record<string, string>)) {
          safeEnd(res, modifiedBuffer);
        }
      });
    } else {
      if (safeHead(proxyRes.statusCode || 200, proxyRes.headers as Record<string, string>)) {
        proxyRes.pipe(res);
      }
    }
  });

  proxyReq.on('error', (err) => {
    log.error('[Proxy] Google Forwarding Error:', err);
    if (safeWriteHead(res, 500, { 'Content-Type': 'application/json' })) {
      safeEnd(res, JSON.stringify({ error: { message: 'Proxy forwarding failed: ' + err.message } }));
    }
  });

  if (reqBody) {
    proxyReq.write(reqBody);
  }
  proxyReq.end();
}

// ─── File Data Resolver ────────────────────────────────────────────────────

async function resolveFileData(body: GeminiRequestBody, reqHeaders: Record<string, string | string[] | undefined>): Promise<void> {
  const contents = body.contents;
  if (!contents) return;
  const authHeader = (reqHeaders['authorization'] || reqHeaders['Authorization'] || '') as string;
  for (const item of contents) {
    if (!item.parts) continue;
    for (let i = 0; i < item.parts.length; i++) {
      const p = item.parts[i] as Record<string, unknown>;
      const fd = p.fileData as { mimeType?: string; fileUri?: string } | undefined;
      if (!fd?.fileUri) continue;
      // Keep image fileData intact so provider translators can map it natively.
      if (fd.mimeType?.startsWith('image/')) continue;
      try {
        const uri = fd.fileUri; let fileContent = '';
        if (uri.startsWith('file://')) {
          const fp = uri.replace('file://', '').replace(/\//g, path.sep);
          if (fs.existsSync(fp)) fileContent = fs.readFileSync(fp, 'utf-8');
        } else if (authHeader && uri.startsWith('https://')) {
          fileContent = await downloadFileContent(uri, authHeader);
        }
        if (fileContent) {
          (item.parts[i] as Record<string, unknown>) = { text: '[File content]:\n\n' + fileContent };
        }
      } catch (e) { log.warn('[Proxy] File resolve failed:', (e as Error).message); }
    }
  }
}

function downloadFileContent(url: string, authHeader: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    (u.protocol === 'https:' ? https : http).request({
      hostname: u.hostname, path: u.pathname + u.search,
      method: 'GET', headers: { 'Authorization': authHeader }, timeout: FILE_DOWNLOAD_TIMEOUT_MS,
    }, (res) => {
      if (res.statusCode !== 200) { reject(new Error('HTTP ' + res.statusCode)); return; }
      let d = ''; res.on('data', (c: Buffer) => d += c.toString()); res.on('end', () => resolve(d));
    }).on('error', reject).end();
  });
}

// ─── Custom Model Request Handler ─────────────────────────────────────────

/**
 * Parses the Retry-After header from upstream responses (RFC 7231 §7.1.3).
 * Returns delay in milliseconds, or 0 if no valid header is present.
 */
export function parseRetryAfter(headers: Record<string, string | string[] | undefined>): number {
  const val = headers['retry-after'];
  if (!val) return 0;

  const raw = Array.isArray(val) ? val[0] : val;
  if (!raw) return 0;

  // Try delta-seconds (e.g. "120")
  const seconds = parseInt(raw.trim(), 10);
  if (!isNaN(seconds) && seconds >= 0) {
    return seconds * 1000;
  }

  // Try HTTP-date (e.g. "Wed, 21 Oct 2015 07:28:00 GMT")
  const date = new Date(raw);
  if (!isNaN(date.getTime())) {
    const delay = date.getTime() - Date.now();
    return delay > 0 ? delay : 0;
  }

  return 0;
}

function handleCustomModelRequest(
  res: http.ServerResponse,
  model: CustomModel,
  geminiBody: GeminiRequestBody,
  isStream: boolean,
  retryCount = 0,
  fallbackDepth = 0,
): void {
  // P3-18: Configurable max retries per model (default 3, min 0, max 5)
  const MAX_RETRIES = resolveMaxRetries(model);
  const REQUEST_TIMEOUT_MS = resolveRequestTimeout(model);

  function attemptFallback(diagnostic: ErrorDiagnostic): boolean {
    if (fallbackDepth > 0) return false;
    try {
      const allModels = loadCustomModels();
      for (const m of allModels) {
        if (m.name !== model.name && m.apiKey && m.apiKey !== 'none' && !m.apiKey.startsWith('fallback:')) {
           log.warn(`[Proxy] Model ${model.name} failed (${diagnostic.errorType}). Auto-falling back to ${m.name}...`);
           handleCustomModelRequest(res, m, geminiBody, isStream, 0, fallbackDepth + 1);
           return true; // Fallback successfully initiated
        }
      }
    } catch(e) {}
    return false;
  }

  const provider = resolveProvider(model);

  const payload = registry.translateRequest(provider, geminiBody, model.externalModelName);
  const headers = registry.getProviderHeaders(provider, model.apiKey);

  if (isStream && registry.supportsStreaming(provider)) {
    (payload as Record<string, unknown>).stream = true;
  }

  const finalUrlStr = resolveCustomModelUrl(
    model,
    isStream,
    (apiUrl, externalModelName, stream, translator) =>
      registry.getProviderUrl(apiUrl, externalModelName, stream, translator as Parameters<typeof registry.getProviderUrl>[3]),
  );
  const url = new URL(finalUrlStr);
  const client = url.protocol === 'https:' ? https : http;

  const options: https.RequestOptions = {
    method: 'POST',
    headers: headers as Record<string, string>,
  };

  // P0-2: SSL bypass ONLY when user explicitly opts in via allowUnauthorized.
  // Custom providers no longer bypass SSL automatically.
  if (model.allowUnauthorized) {
    log.warn(
      `[Proxy] SSL verification DISABLED for ${model.name} (allowUnauthorized=true). Connection is vulnerable to MITM.`,
    );
    (options as Record<string, unknown>).rejectUnauthorized = false;
  }

  log.info(
    `[Proxy] Routing ${model.name} to ${model.provider} (${model.apiUrl}) (isStream: ${!!isStream})${retryCount > 0 ? ` (retry ${retryCount})` : ''}`,
  );

  const request = client.request(url, options, (apiRes) => {
    apiRes.on('error', (err) => {
      log.error(`[Proxy] Upstream stream error for ${model.name}:`, err.message);
      const diagnostic = classifyError(500, err, undefined, model.provider);
      if (safeWriteHead(res, 500, {
        'Content-Type': 'application/json',
        'X-AG-Error-Type': diagnostic.errorType
      })) {
        safeEnd(res, JSON.stringify({ error: { message: 'Upstream connection error: ' + err.message }, _agDiagnostic: diagnostic }));
      } else if (!res.writableEnded) {
        safeEnd(res);
      }
    });
    const status = apiRes.statusCode || 0;

    // P3: Log 401 errors with detailed diagnostic context to help users
    // understand why their custom endpoint rejected the request.
    // Common causes: missing API key, wrong header name, expired token,
    // wrong endpoint URL, account suspended.
    if (status === 401) {
      const apiKeyPreview = model.apiKey
        ? `${model.apiKey.slice(0, 4)}…${model.apiKey.slice(-4)} (len=${model.apiKey.length})`
        : '<empty>';
      log.error(`[Proxy] 401 Unauthorized from ${model.name} (${model.provider})`);
      log.error(`[Proxy]   URL: ${finalUrlStr}`);
      log.error(`[Proxy]   API key: ${apiKeyPreview}`);
      log.error(`[Proxy]   Headers sent: ${Object.keys(headers).join(', ')}`);
      log.error(`[Proxy]   Possible causes:`);
      log.error(`[Proxy]     - Missing or invalid API key (check custom_models.json)`);
      log.error(`[Proxy]     - Wrong header name for this provider (e.g. 'Authorization' vs 'x-api-key')`);
      log.error(`[Proxy]     - Expired or revoked token`);
      log.error(`[Proxy]     - Account suspended or rate-limited`);
      log.error(`[Proxy]     - Wrong endpoint URL (${finalUrlStr})`);
      log.error(`[Proxy]   Upstream response: ${JSON.stringify(apiRes.headers).slice(0, 200)}`);
    }

    if (isStream) {
      // Check for API errors BEFORE writing streaming headers
      if (apiRes.statusCode! >= 400) {
        let errorBody = '';
        apiRes.on('data', (chunk: Buffer) => errorBody += chunk.toString());
        apiRes.on('end', () => {
          log.error(`[Proxy] Stream API error (${apiRes.statusCode}) for ${model.name}: ${errorBody.substring(0, 300)}`);
          if (shouldRetryStatus(apiRes.statusCode!, retryCount, MAX_RETRIES)) {
            log.warn(`[Proxy] Stream error, retrying (${retryCount + 1}/${MAX_RETRIES})...`);
            setTimeout(() => handleCustomModelRequest(res, model, geminiBody, isStream, retryCount + 1), 1000 * (retryCount + 1));
            return;
          }
          const diagnostic = classifyError(apiRes.statusCode!, null, errorBody, model.provider);

          if (attemptFallback(diagnostic)) return;

          if (diagnostic.errorType === 'billing' || diagnostic.errorType === 'auth' || diagnostic.errorType === 'forbidden') {
            const errResponse = {
              response: {
                candidates: [
                  {
                    content: { parts: [{ text: generateGracefulMarkdown(diagnostic) }], role: 'model' },
                    finishReason: 'STOP',
                    index: 0,
                  },
                ],
              },
              traceId: '',
              metadata: {},
              _agDiagnostic: diagnostic
            };
            if (safeWriteHead(res, 200, {
              'Content-Type': 'text/event-stream',
              'Cache-Control': 'no-cache',
              Connection: 'keep-alive',
              'X-AG-Error-Type': diagnostic.errorType
            })) {
              res.write('data: ' + JSON.stringify(errResponse) + '\n\n');
              safeEnd(res);
            }
            return;
          }

          let responseJson = { error: { message: `Upstream error: ${errorBody}` } };
          try {
            responseJson = JSON.parse(errorBody);
          } catch {
            // not JSON
          }
          if (typeof responseJson === 'object' && responseJson !== null) {
            (responseJson as any)._agDiagnostic = diagnostic;
          }
          if (safeWriteHead(res, apiRes.statusCode!, {
            'Content-Type': 'application/json',
            'X-AG-Error-Type': diagnostic.errorType
          })) {
            safeEnd(res, JSON.stringify(responseJson));
          }
        });
        return;
      }

      if (!safeWriteHead(res, 200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        Connection: 'keep-alive',
        'X-Accel-Buffering': 'no',
      })) {
        return;
      }

      let buffer = '';
      apiRes.on('data', (chunk: Buffer) => {
        buffer += chunk.toString('utf-8');
        const lines = buffer.split('\n');
        buffer = lines.pop() || '';

        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed) continue;
          if (trimmed.startsWith('data: ')) {
            const dataStr = trimmed.substring(6).trim();
            if (dataStr === '[DONE]') continue;
            try {
              const parsed = JSON.parse(dataStr);
              const mapped = registry.translateStreamChunk(provider, parsed, model.name);

              if (mapped) {
                const cloudCodeResponse = {
                  response: { candidates: [mapped] },
                  traceId: '',
                  metadata: {},
                };
                res.write(`data: ${JSON.stringify(cloudCodeResponse)}\n\n`);
              }
            } catch (err) {
              // Partial/invalid JSON chunks are normal during streaming; debug-level only
              log.debug(`[Proxy] Stream chunk parse warning for ${model.name}:`, (err as Error).message);
            }
          }
        }
      });

      apiRes.on('end', () => {
        if (buffer.trim().startsWith('data: ')) {
          const dataStr = buffer.trim().substring(6).trim();
          if (dataStr !== '[DONE]') {
            try {
              const parsed = JSON.parse(dataStr);
              const mapped = registry.translateStreamChunk(provider, parsed, model.name);
              if (mapped) {
                const cloudCodeResponse = {
                  response: { candidates: [mapped] },
                  traceId: '',
                  metadata: {},
                };
                res.write(`data: ${JSON.stringify(cloudCodeResponse)}\n\n`);
              }
            } catch (e) {
              log.debug(`[Proxy] Stream buffer drain parse warning for ${model.name}:`, (e as Error).message);
            }
          }
        }

        const finalChunk = {
          response: {
            candidates: [
              {
                content: { parts: [], role: 'model' },
                finishReason: 'STOP',
                index: 0,
              },
            ],
          },
          traceId: '',
          metadata: {},
        };
        res.write(`data: ${JSON.stringify(finalChunk)}\n\n`);
        res.end();
      });
    } else {
      let body = '';
      apiRes.on('data', (chunk: Buffer) => (body += chunk));
      apiRes.on('end', () => {
        // Retry if eligible based on status code
        if (shouldRetryStatus(apiRes.statusCode!, retryCount, MAX_RETRIES)) {
          const retryAfter = parseRetryAfter(apiRes.headers);
          const delay = retryAfter > 0 ? retryAfter : (apiRes.statusCode === 429 ? 2000 : 1000) * Math.pow(2, retryCount);
          log.warn(
            `[Proxy] Upstream error status ${apiRes.statusCode} for ${model.name}, retrying in ${delay}ms (${retryCount + 1}/${MAX_RETRIES})...`,
          );
          setTimeout(() => handleCustomModelRequest(res, model, geminiBody, isStream, retryCount + 1), delay);
          return;
        }

        if (apiRes.statusCode! >= 400) {
          // P0-3: Only log status code and model name, NOT response body content
          log.error(`[Proxy] API error (${apiRes.statusCode}) for ${model.name}`);
          
          const diagnostic = classifyError(apiRes.statusCode!, null, body, model.provider);

          if (attemptFallback(diagnostic)) return;

          if (diagnostic.errorType === 'billing' || diagnostic.errorType === 'auth' || diagnostic.errorType === 'forbidden') {
            const errResponse = {
              response: {
                candidates: [
                  {
                    content: { parts: [{ text: generateGracefulMarkdown(diagnostic) }], role: 'model' },
                    finishReason: 'STOP',
                    index: 0,
                  },
                ],
              },
              traceId: '',
              metadata: {},
              _agDiagnostic: diagnostic
            };
            if (safeWriteHead(res, 200, {
              'Content-Type': 'application/json',
              'X-AG-Error-Type': diagnostic.errorType
            })) {
              safeEnd(res, JSON.stringify(errResponse));
            }
            return;
          }

          let responseJson = { error: { message: `Upstream error: ${body}` } };
          try {
            responseJson = JSON.parse(body);
          } catch {
            // not JSON
          }
          if (typeof responseJson === 'object' && responseJson !== null) {
            (responseJson as any)._agDiagnostic = diagnostic;
          }

          if (safeWriteHead(res, apiRes.statusCode!, {
            'Content-Type': 'application/json',
            'X-AG-Error-Type': diagnostic.errorType
          })) {
            safeEnd(res, JSON.stringify(responseJson));
          }
          return;
        }

        try {
          const parsed = JSON.parse(body) as Record<string, unknown>;

          const reasoning =
            (parsed as { choices?: { message?: { reasoning_content?: string; reasoning?: string } }[] }).choices?.[0]
              ?.message?.reasoning_content ||
            (parsed as { choices?: { message?: { reasoning_content?: string; reasoning?: string } }[] }).choices?.[0]
              ?.message?.reasoning;
          if (reasoning) {
            modelReasoningContent.set(model.name, reasoning);
            touchStateTimestamp(stateTimestamps.reasoning, model.name);
          }

          const providerForResponse =
            model.provider === 'custom' || model.provider === 'openrouter' ? 'openai' : model.provider;
          const mapped = registry.translateResponse(providerForResponse, parsed, model.name);

          const cloudCodeResponse = {
            response: mapped,
            traceId: '',
            metadata: {},
          };

          if (safeWriteHead(res, 200, { 'Content-Type': 'application/json' })) {
            safeEnd(res, JSON.stringify(cloudCodeResponse));
          }
        } catch (e) {
          log.error('[Proxy] Failed to map response:', e);

          if (retryCount < MAX_RETRIES) {
            log.warn(`[Proxy] Parse error for ${model.name}, retrying (${retryCount + 1}/${MAX_RETRIES})...`);
            setTimeout(
              () => handleCustomModelRequest(res, model, geminiBody, isStream, retryCount + 1),
              1000 * (retryCount + 1),
            );
            return;
          }

          const diagnostic = classifyError(500, e, body, model.provider);
          
          if (attemptFallback(diagnostic)) return;
          
          if (safeWriteHead(res, 500, {
            'Content-Type': 'application/json',
            'X-AG-Error-Type': diagnostic.errorType
          })) {
            safeEnd(res, JSON.stringify({ error: { message: 'Failed to translate model response' }, _agDiagnostic: diagnostic }));
          }
        }
      });
    }
  });

  request.setTimeout(REQUEST_TIMEOUT_MS, () => {
    log.error(`[Proxy] Request timeout (${REQUEST_TIMEOUT_MS}ms) for ${model.name}`);
    request.destroy();

    if (retryCount < MAX_RETRIES) {
      log.warn(`[Proxy] Timeout for ${model.name}, retrying (${retryCount + 1}/${MAX_RETRIES})...`);
      setTimeout(
        () => handleCustomModelRequest(res, model, geminiBody, isStream, retryCount + 1),
        1000 * (retryCount + 1),
      );
      return;
    }

    const diagnostic = classifyError(504, 'ETIMEDOUT', undefined, model.provider);
    
    if (attemptFallback(diagnostic)) return;
    
    if (safeWriteHead(res, 504, {
      'Content-Type': 'application/json',
      'X-AG-Error-Type': diagnostic.errorType
    })) {
      safeEnd(res, JSON.stringify({ error: { message: `Request timeout after ${REQUEST_TIMEOUT_MS / 1000}s` }, _agDiagnostic: diagnostic }));
    }
  });

  request.on('error', (err) => {
    log.error('[Proxy] Custom Model Request Error:', err);

    if (retryCount < MAX_RETRIES) {
      log.warn(`[Proxy] Network error for ${model.name}, retrying (${retryCount + 1}/${MAX_RETRIES})...`);
      setTimeout(
        () => handleCustomModelRequest(res, model, geminiBody, isStream, retryCount + 1),
        1000 * (retryCount + 1),
      );
      return;
    }

    const diagnostic = classifyError(undefined, err, undefined, model.provider);

    if (attemptFallback(diagnostic)) return;

    if (isStream) {
      if (!res.headersSent && !res.writableEnded) {
        const errResponse = {
          response: {
            candidates: [
              {
                content: { parts: [{ text: 'Network error: ' + err.message }], role: 'model' },
                finishReason: 'STOP',
                index: 0,
              },
            ],
          },
          traceId: '',
          metadata: {},
          _agDiagnostic: diagnostic
        };
        safeWriteHead(res, 502, {
          'Content-Type': 'text/event-stream',
          'X-AG-Error-Type': diagnostic.errorType
        });
        res.write('data: ' + JSON.stringify(errResponse) + '\n\n');
      }
      safeEnd(res);
    } else {
      if (safeWriteHead(res, 502, {
        'Content-Type': 'application/json',
        'X-AG-Error-Type': diagnostic.errorType
      })) {
        safeEnd(res, JSON.stringify({ error: { message: 'Custom model request failed: ' + err.message }, _agDiagnostic: diagnostic }));
      }
    }
  });

  request.write(JSON.stringify(payload));
  request.end();
}

// ─── GetAvailableModels Proxy Handler ───────────────────────────────────────

function handleGetAvailableModelsProxy(
  res: http.ServerResponse,
  reqBody: Buffer,
  lsUrl: string,
): void {
  const lsParsed = new URL(lsUrl);
  const client = lsParsed.protocol === 'https:' ? https : http;

  const options: https.RequestOptions = {
    method: 'POST',
    hostname: lsParsed.hostname,
    port: lsParsed.port || (lsParsed.protocol === 'https:' ? '443' : '80'),
    path: lsParsed.pathname + lsParsed.search,
    headers: {
      'Content-Type': 'application/grpc-web+proto',
      'Accept': 'application/grpc-web+proto',
      'Content-Length': String(reqBody.length),
    },
    rejectUnauthorized: false,
  };

  const lsReq = client.request(options, (lsRes) => {
    let lsResErrored = false;
    lsRes.on('error', (err) => {
      lsResErrored = true;
      log.error('[Proxy] LS error for GetAvailableModels:', err.message);
      if (!res.headersSent && !res.writableEnded) {
        safeWriteHead(res, 502);
        safeEnd(res);
      }
    });

    const chunks: Buffer[] = [];
    lsRes.on('data', (chunk: Buffer) => chunks.push(chunk));
    lsRes.on('end', () => {
      // Guard: timeout or error may have already terminated the response
      if (lsResErrored || res.headersSent || res.writableEnded) {
        log.debug('[Proxy] GetAvailableModels: skipping end handler (response terminated)');
        return;
      }
      const responseBuf = Buffer.concat(chunks);
      const customModels = loadCustomModels();
      const { buffer: modifiedBuf } = injectCustomModelsIntoResponse(responseBuf, customModels);

      if (
        safeWriteHead(res, lsRes.statusCode || 200, {
          'Content-Type': 'application/grpc-web+proto',
          'Content-Length': String(modifiedBuf.length),
        })
      ) {
        safeEnd(res, modifiedBuf);
      }
    });
  });

  lsReq.setTimeout(30_000, () => {
    log.error('[Proxy] GetAvailableModels forward timed out');
    lsReq.destroy();
    if (!res.headersSent && !res.writableEnded) {
      safeWriteHead(res, 504);
      safeEnd(res);
    }
  });

  lsReq.on('error', (err) => {
    log.error('[Proxy] GetAvailableModels forward error:', err.message);
    if (!res.headersSent && !res.writableEnded) {
      safeWriteHead(res, 502);
      safeEnd(res);
    }
  });

  lsReq.write(reqBody);
  lsReq.end();
}

// ─── Main Request Handler ─────────────────────────────────────────────────

function handleRequest(req: http.IncomingMessage, res: http.ServerResponse): void {
  // Health check — keep this FIRST so the LS sees a live port even if other
  // initialization (padding strip, model loading, etc.) is delayed or fails.
  if (req.method === 'GET' && (req.url === '/health' || req.url === '/healthz')) {
    log.info(`[Proxy] /health hit from ${req.socket.remoteAddress || 'unknown'}`);
    const memUsage = process.memoryUsage();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(
      JSON.stringify({
        status: 'ok',
        uptime: process.uptime(),
        port: proxyPort,
        memory: {
          rssMB: Math.round(memUsage.rss / 1024 / 1024),
          heapUsedMB: Math.round(memUsage.heapUsed / 1024 / 1024),
          heapTotalMB: Math.round(memUsage.heapTotal / 1024 / 1024),
        },
        state: {
          activeStreamContexts: activeStreamContexts.size,
          modelToolCallIds: modelToolCallIds.size,
          translatedToolCalls: translatedToolCalls.size,
          modelReasoningContent: modelReasoningContent.size,
        },
        timestamp: new Date().toISOString(),
      }),
    );
    return;
  }

  req.url = req.url!.replace(/^.*\/dummy_path_padding/, '');
  // Strip binary patch padding (from LS hostname replacement)
  req.url = req.url!.replace(/\/v1internal\/x{7}/, '');

  // P0-4: Enforce maximum request body size to prevent memory exhaustion DoS
  const MAX_BODY_SIZE = 10 * 1024 * 1024; // 10 MB
  let bodyLength = 0;
  let bodyRejected = false;

  const bodyChunks: Buffer[] = [];
  req.on('data', (chunk) => {
    bodyLength += chunk.length;
    if (bodyLength > MAX_BODY_SIZE) {
      if (!bodyRejected) {
        bodyRejected = true;
        log.warn(`[Proxy] Request body exceeds ${MAX_BODY_SIZE / 1024 / 1024}MB limit (${req.method} ${req.url})`);
        req.destroy();
        if (!res.headersSent) {
          res.writeHead(413, { 'Content-Type': 'application/json' });
          res.end(
            JSON.stringify({ error: { message: `Request body too large. Maximum: ${MAX_BODY_SIZE / 1024 / 1024}MB` } }),
          );
        }
      }
      return;
    }
    bodyChunks.push(chunk);
  });
  req.on('end', async () => {
    if (bodyRejected) return;

    const fullBody = Buffer.concat(bodyChunks);
    const bodyStr = fullBody.toString('utf-8');

    log.info(`[Proxy] Request: ${req.method} ${req.url}`);

    // 0. Intercept GetAvailableModels (redirected from Electron webRequest)
    if (req.url!.startsWith('/GetAvailableModels')) {
      const gavParsed = new URL(req.url!, 'http://127.0.0.1');
      const lsUrl = gavParsed.searchParams.get('ls');
      if (lsUrl) {
        handleGetAvailableModelsProxy(res, fullBody, lsUrl);
        return;
      }
      if (safeWriteHead(res, 400, { 'Content-Type': 'application/json' })) {
        safeEnd(res, JSON.stringify({ error: 'Missing ls parameter' }));
      }
      return;
    }

    // 1. Intercept /v1internal:fetchAvailableModels
    if (req.url!.includes('/v1internal:fetchAvailableModels')) {
      log.info('[Proxy] Intercepting fetchAvailableModels request');

      const targetHost = 'daily-cloudcode-pa.googleapis.com';
      const targetUrl = `https://${targetHost}`;
      let parsedUrl: URL;
      try {
        const realIp = await resolveGoogleIp(targetHost);
        parsedUrl = new URL(req.url!, targetUrl);
        parsedUrl.hostname = realIp;
      } catch (e) {
        log.error(`[Proxy] Could not resolve upstream IP for ${targetHost}:`, e);
        if (safeWriteHead(res, 500, { 'Content-Type': 'application/json' })) {
          safeEnd(res, JSON.stringify({ error: { message: 'DNS resolution failed for ' + targetHost } }));
        }
        return;
      }
      const fwdHeaders: Record<string, string | string[] | undefined> = {
        ...(req.headers as Record<string, string | string[] | undefined>),
      };
      fwdHeaders['host'] = targetHost;
      delete fwdHeaders['connection'];
      delete fwdHeaders['keep-alive'];
      delete fwdHeaders['accept-encoding'];

      const fwdOptions: https.RequestOptions = {
        method: req.method,
        headers: fwdHeaders as Record<string, string>,
        servername: targetHost,
      };

      const googleReq = https.request(parsedUrl, fwdOptions, (googleRes) => {
        let googleResErrored = false;
        googleRes.on('error', (err) => {
          googleResErrored = true;
          log.error('[Proxy] fetchAvailableModels upstream error:', err.message);
        });

        // P0-5: Timeout for fetchAvailableModels forward request (30s)
        googleReq.setTimeout(30_000, () => {
          log.error('[Proxy] fetchAvailableModels forward request timed out');
          googleReq.destroy();
          if (!res.headersSent && !res.writableEnded) {
            const customModels = loadCustomModels();
            const mappedCustom: Record<string, unknown> = {};
            customModels.forEach((m) => {
              const slug = toSlug(m);
              mappedCustom[slug] = {
                displayName: m.displayName,
                maxTokens: 1048576,
                maxOutputTokens: 4096,
                model: generateModelPlaceholderId(m),
                apiProvider: 'API_PROVIDER_GOOGLE_GEMINI',
                modelProvider: 'MODEL_PROVIDER_GOOGLE',
              };
            });
            safeWriteHead(res, 200, { 'Content-Type': 'application/json' });
            safeEnd(res, JSON.stringify({ models: mappedCustom }));
          }
        });

        let googleBody = '';
        googleRes.on('data', (chunk) => (googleBody += chunk));
        googleRes.on('end', () => {
          // Guard: timeout or upstream error may have already terminated the response
          if (googleResErrored || res.headersSent || res.writableEnded) {
            log.debug('[Proxy] fetchAvailableModels: skipping end handler (response terminated)');
            return;
          }
          try {
            log.info(
              `[Proxy] fetchAvailableModels response status: ${googleRes.statusCode}, body length: ${googleBody.length}`,
            );

            const googleJson = JSON.parse(googleBody) as Record<string, unknown>;
            const customModels = loadCustomModels();

            log.info(`[Proxy] Loaded custom models count: ${customModels.length}`);

            const mergeModels = (target: unknown): unknown => {
              if (Array.isArray(target)) {
                const mapped = customModels.map((m) => {
                  const cap = detectModelCapabilities(m, true);
                  return {
                    name: 'models/' + generateModelPlaceholderId(m),
                    version: '1.0',
                    displayName: m.displayName,
                    description: m.description,
                    inputTokenLimit: cap.maxTokens,
                    outputTokenLimit: cap.maxOutputTokens,
                    supportedGenerationMethods: ['generateContent', 'countTokens'],
                    temperature: cap.isThinking ? undefined : 0.7,
                    topP: cap.isThinking ? undefined : 0.9,
                    topK: cap.isThinking ? undefined : 40,
                    reasoningEffort: m.reasoningEffort || undefined,
                    thinkingBudget: m.thinkingBudget || undefined,
                    mode: m.mode || undefined,
                  };
                });
                return [...mapped, ...target];
              } else if (target && typeof target === 'object') {
                const result = { ...(target as Record<string, unknown>) };
                customModels.forEach((m) => {
                  const slug = toSlug(m);
                  const cap = detectModelCapabilities(m, true);
                  const entry: Record<string, unknown> = {
                    displayName: m.displayName,
                    supportsImages: cap.supportsImages,
                    supportsThinking: cap.isThinking,
                    reasoningEffort: m.reasoningEffort || undefined,
                    thinkingBudget: m.thinkingBudget || undefined,
                    mode: m.mode || undefined,
                    recommended: true,
                    maxTokens: cap.maxTokens,
                    maxOutputTokens: cap.maxOutputTokens,
                    tokenizerType: 'LLAMA_WITH_SPECIAL',
                    model: generateModelPlaceholderId(m),
                    apiProvider: 'API_PROVIDER_GOOGLE_GEMINI',
                    modelProvider: 'MODEL_PROVIDER_GOOGLE',
                  };
                  if (cap.supportsImages) {
                    entry.supportsVideo = false;
                    entry.supportedMimeTypes = {
                      'image/png': true,
                      'image/jpeg': true,
                      'image/webp': true,
                      'image/gif': true,
                      'image/heic': true,
                      'image/heif': true,
                      'text/plain': true,
                      'text/markdown': true,
                      'text/html': true,
                      'text/css': true,
                      'text/xml': true,
                      'text/csv': true,
                      'application/json': true,
                      'application/pdf': true,
                      'application/x-javascript': true,
                      'application/x-typescript': true,
                      'application/x-python-code': true,
                      'application/x-ipynb+json': true,
                    };
                  } else {
                    entry.supportsVideo = false;
                    entry.supportedMimeTypes = {
                      'text/plain': true,
                      'text/markdown': true,
                      'text/html': true,
                      'text/css': true,
                      'text/xml': true,
                      'text/csv': true,
                      'application/json': true,
                      'application/pdf': true,
                      'application/x-javascript': true,
                      'application/x-typescript': true,
                      'application/x-python-code': true,
                      'application/x-ipynb+json': true,
                    };
                  }
                  (result as Record<string, unknown>)[slug] = entry;
                  m._slug = slug;
                  log.info(
                    `[Proxy] Custom model "${m.displayName}" => slug: ${slug} => model: ${generateModelPlaceholderId(m)} => thinking: ${cap.isThinking} => images: ${cap.supportsImages}`,
                  );
                });
                return result;
              }
              return target;
            };

            let merged = false;
            if (googleJson.models) {
              googleJson.models = mergeModels(googleJson.models);
              merged = true;
            }
            if (googleJson.availableModels) {
              googleJson.availableModels = mergeModels(googleJson.availableModels);
              merged = true;
            }
            if (googleJson.available_models) {
              googleJson.available_models = mergeModels(googleJson.available_models);
              merged = true;
            }

            if (!merged) {
              const modelsMap: Record<string, unknown> = {};
              customModels.forEach((m) => {
                const slug = toSlug(m);
                modelsMap[slug] = {
                  displayName: m.displayName,
                  recommended: true,
                  maxTokens: 1048576,
                  maxOutputTokens: 4096,
                  tokenizerType: 'LLAMA_WITH_SPECIAL',
                  model: generateModelPlaceholderId(m),
                  apiProvider: 'API_PROVIDER_GOOGLE_GEMINI',
                  modelProvider: 'MODEL_PROVIDER_GOOGLE',
                };
                m._slug = slug;
              });
              googleJson.models = modelsMap;
            }

            // Inject custom model slugs into agentModelSorts
            const customSlugs = customModels.map((m) => m._slug).filter(Boolean) as string[];
            if (customSlugs.length > 0) {
              if (googleJson.agentModelSorts && Array.isArray(googleJson.agentModelSorts)) {
                (googleJson.agentModelSorts as { groups?: { modelIds?: string[] }[] }[]).forEach((sort) => {
                  if (sort.groups && Array.isArray(sort.groups)) {
                    sort.groups.forEach((group) => {
                      if (group.modelIds && Array.isArray(group.modelIds)) {
                        customSlugs.forEach((slug) => {
                          if (!group.modelIds!.includes(slug)) {
                            group.modelIds!.push(slug);
                          }
                        });
                      }
                    });
                  }
                });
              }
            }

            // P1: Strip Google's upstream error from the response. When Google
            // returns 401/403/etc., the proxy forwards that error object alongside
            // our injected custom models. The Antigravity frontend treats any
            // `error` key as a hard failure and hides the entire model list,
            // even though we successfully injected valid models. Removing the
            // error key lets the frontend render the merged model list normally.
            if (googleJson.error) {
              log.warn(
                `[Proxy] fetchAvailableModels: stripping upstream error from response (status: ${googleRes.statusCode})`,
              );
              delete (googleJson as Record<string, unknown>).error;
            }

            safeWriteHead(res, 200, { 'Content-Type': 'application/json' });
            safeEnd(res, JSON.stringify(googleJson));
          } catch (err) {
            log.error('[Proxy] Parsing fetchAvailableModels failed, returning custom models:', err);
            if (res.headersSent || res.writableEnded) return;
            const customModels = loadCustomModels();
            const mappedCustom: Record<string, unknown> = {};
            customModels.forEach((m) => {
              const slug = toSlug(m);
              mappedCustom[slug] = {
                displayName: m.displayName,
                maxTokens: 1048576,
                maxOutputTokens: 4096,
                model: generateModelPlaceholderId(m),
                apiProvider: 'API_PROVIDER_GOOGLE_GEMINI',
                modelProvider: 'MODEL_PROVIDER_GOOGLE',
              };
            });
            safeWriteHead(res, 200, { 'Content-Type': 'application/json' });
            safeEnd(res, JSON.stringify({ models: mappedCustom }));
          }
        });
      });

      googleReq.on('error', (err) => {
        log.error('[Proxy] Forwarding fetchAvailableModels failed:', err);
        if (!res.headersSent && !res.writableEnded) {
          const customModels = loadCustomModels();
          const mappedCustom: Record<string, unknown> = {};
          customModels.forEach((m) => {
            const slug = toSlug(m);
            mappedCustom[slug] = {
              displayName: m.displayName,
              maxTokens: 1048576,
              maxOutputTokens: 4096,
              model: generateModelPlaceholderId(m),
              apiProvider: 'API_PROVIDER_GOOGLE_GEMINI',
              modelProvider: 'MODEL_PROVIDER_GOOGLE',
            };
          });
          safeWriteHead(res, 200, { 'Content-Type': 'application/json' });
          safeEnd(res, JSON.stringify({ models: mappedCustom }));
        }
      });

      if (fullBody && fullBody.length > 0) {
        googleReq.write(fullBody);
      }
      googleReq.end();
      return;
    }

    // 2. Intercept /v1beta/models or /v1/models list request
    if (req.method === 'GET' && (req.url!.endsWith('/models') || req.url!.includes('/models?'))) {
      log.info('[Proxy] Intercepting models list request');

      const targetHost = 'generativelanguage.googleapis.com';
      const targetUrl = `https://${targetHost}`;
      let parsedUrl: URL;
      try {
        const realIp = await resolveGoogleIp(targetHost);
        parsedUrl = new URL(req.url!, targetUrl);
        parsedUrl.hostname = realIp;
      } catch (e) {
        log.error(`[Proxy] Could not resolve upstream IP for ${targetHost}:`, e);
        if (safeWriteHead(res, 500, { 'Content-Type': 'application/json' })) {
          safeEnd(res, JSON.stringify({ error: { message: 'DNS resolution failed for ' + targetHost } }));
        }
        return;
      }
      const mdlHeaders: Record<string, string | string[] | undefined> = {
        ...(req.headers as Record<string, string | string[] | undefined>),
      };
      mdlHeaders['host'] = targetHost;
      delete mdlHeaders['connection'];
      delete mdlHeaders['accept-encoding'];

      const mdlOptions: https.RequestOptions = {
        method: 'GET',
        headers: mdlHeaders as Record<string, string>,
        servername: targetHost,
      };

      const googleReq = https.request(parsedUrl, mdlOptions, (googleRes) => {
        let googleResErrored = false;
        googleRes.on('error', (err) => {
          googleResErrored = true;
          log.error('[Proxy] Models list upstream error:', err.message);
        });

        // P0-5: Timeout for models list forward request (30s)
        googleReq.setTimeout(30_000, () => {
          log.error('[Proxy] Models list forward request timed out');
          googleReq.destroy();
          if (!res.headersSent && !res.writableEnded) {
            const customModels = loadCustomModels();
            safeWriteHead(res, 200, { 'Content-Type': 'application/json' });
            safeEnd(
              res,
              JSON.stringify({
                models: customModels.map((m) => ({
                  name: m.name,
                  displayName: m.displayName,
                  description: m.description,
                  supportedGenerationMethods: ['generateContent'],
                })),
              }),
            );
          }
        });

        let googleBody = '';
        googleRes.on('data', (chunk) => (googleBody += chunk));
        googleRes.on('end', () => {
          // Guard: timeout or upstream error may have already terminated the response
          if (googleResErrored || res.headersSent || res.writableEnded) {
            log.debug('[Proxy] Models list: skipping end handler (response terminated)');
            return;
          }
          try {
            const googleJson = JSON.parse(googleBody) as { models?: unknown[] };
            const customModels = loadCustomModels();

            const mappedCustom = customModels.map((m) => ({
              name: 'models/' + generateModelPlaceholderId(m),
              version: '1.0',
              displayName: m.displayName,
              description: m.description,
              inputTokenLimit: 1048576,
              outputTokenLimit: 4096,
              supportedGenerationMethods: ['generateContent', 'countTokens'],
              temperature: 0.7,
              topP: 0.9,
              topK: 40,
            }));

            if (googleJson.models) {
              googleJson.models = [...mappedCustom, ...googleJson.models];
            } else {
              googleJson.models = mappedCustom;
            }

            safeWriteHead(res, 200, { 'Content-Type': 'application/json' });
            safeEnd(res, JSON.stringify(googleJson));
          } catch (err) {
            log.error('[Proxy] Google list models failed, returning custom models list only:', err);
            if (res.headersSent || res.writableEnded) return;
            const customModels = loadCustomModels();
            const mappedCustom = customModels.map((m) => ({
              name: 'models/' + generateModelPlaceholderId(m),
              version: '1.0',
              displayName: m.displayName,
              description: m.description,
              inputTokenLimit: 1048576,
              outputTokenLimit: 4096,
              supportedGenerationMethods: ['generateContent', 'countTokens'],
            }));
            safeWriteHead(res, 200, { 'Content-Type': 'application/json' });
            safeEnd(res, JSON.stringify({ models: mappedCustom }));
          }
        });
      });

      googleReq.on('error', (err) => {
        log.error('[Proxy] Google models list request error:', err);
        if (!res.headersSent && !res.writableEnded) {
          const customModels = loadCustomModels();
          safeWriteHead(res, 200, { 'Content-Type': 'application/json' });
          safeEnd(
            res,
            JSON.stringify({
              models: customModels.map((m) => ({
                name: m.name,
                displayName: m.displayName,
                description: m.description,
                supportedGenerationMethods: ['generateContent'],
              })),
            }),
          );
        }
      });
      googleReq.end();
      return;
    }

    // 3. Intercept Cloud Code generation stream or non-stream requests
    const isCloudCodeStream =
      req.url!.includes('/v1internal:streamGenerateContent') || req.url!.includes('/v1internal:generateContent');
    if (req.method === 'POST' && isCloudCodeStream) {
      try {
        const reqJson = JSON.parse(bodyStr) as Record<string, unknown>;
        const modelName = reqJson.model as string | undefined;
        const modelId = (reqJson.modelId || reqJson.model_id) as string | undefined;
        log.info(
          `[Proxy] Cloud Code generation request model: ${modelName}, modelId: ${modelId}, url: ${req.url}, bodyKeys: ${Object.keys(reqJson).join(',')}`,
        );
        if (modelName) {
          const customModels = loadCustomModels();
          const matchedCustomModel = customModels.find((m) => {
            const enumName = generateModelPlaceholderId(m);
            return m.name === modelName || toSlug(m) === modelName || enumName === modelName || enumName === modelId;
          });
          if (matchedCustomModel) {
            log.info(
              `[Proxy] Intercepting Cloud Code generation for custom model: ${modelName} => ${matchedCustomModel.displayName}`,
            );
            const isStream = req.url!.includes('streamGenerateContent') || req.url!.includes('alt=sse');
            const actualGeminiBody = (reqJson.request || reqJson) as GeminiRequestBody;
            // Resolve fileData URIs then route to translator
            resolveFileData(actualGeminiBody, req.headers as Record<string, string | string[] | undefined>).then(() => {
              handleCustomModelRequest(res, matchedCustomModel, actualGeminiBody, isStream);
            });
            return;
          }
        }
      } catch (err) {
        log.error('[Proxy] Failed to parse Cloud Code stream body:', err);
      }
    }

    // 4. Intercept standard generateContent / streamGenerateContent request
    const generateMatch = req.url!.match(/\/(?:v1|v1beta)\/(models\/[^:]+):generateContent/);
    const streamMatch = req.url!.match(/\/(?:v1|v1beta)\/(models\/[^:]+):streamGenerateContent/);

    const isGenerate = !!generateMatch;
    const isStandardStream = !!streamMatch;

    if (req.method === 'POST' && (isGenerate || isStandardStream)) {
      const matchedModelName = isGenerate ? generateMatch![1] : streamMatch![1];
      const customModels = loadCustomModels();
      const matchedCustomModel = customModels.find((m) => {
        const enumName = generateModelPlaceholderId(m);
        return (
          m.name === matchedModelName ||
          toSlug(m) === matchedModelName ||
          enumName === matchedModelName ||
          'models/' + enumName === matchedModelName
        );
      });

      if (matchedCustomModel) {
        try {
          const geminiBody = JSON.parse(bodyStr) as GeminiRequestBody;
          resolveFileData(geminiBody, req.headers as Record<string, string | string[] | undefined>).then(() => {
            handleCustomModelRequest(res, matchedCustomModel, geminiBody, isStandardStream);
          });
          return;
        } catch (e) {
          log.error('[Proxy] JSON parse error in request body:', e);
          if (safeWriteHead(res, 400, { 'Content-Type': 'application/json' })) {
            safeEnd(res, JSON.stringify({ error: { message: 'Invalid JSON request body' } }));
          }
          return;
        }
      }
    }

    // 5. Fallback: transparent proxy to Google
    await proxyToGoogle(req, res, fullBody);
  });
}

// ─── Server Start/Stop ────────────────────────────────────────────────────

export function startProxy(): Promise<number> {
  return new Promise((resolve, reject) => {
    try {
      server = http.createServer(handleRequest);

      // P2: Make port/host configurable via env vars so the proxy can be
      // tuned per-machine without recompiling. Defaults preserve legacy behavior.
      const envPort = parseInt(process.env.AG_PROXY_PORT || '', 10);
      const defaultPort = Number.isFinite(envPort) && envPort > 0 ? envPort : 50999;
      const defaultHost = process.env.AG_PROXY_HOST || '127.0.0.1';

      let primaryPort = defaultPort;
      let primaryHost = defaultHost;

      // Build the ordered list of ports to try: env override → default → fallbacks → dynamic
      const portCandidates: number[] = [defaultPort];
      if (defaultPort === 50999) {
        // Only add fallbacks if the user did not override the port via env
        portCandidates.push(...FALLBACK_PROXY_PORTS);
      }
      portCandidates.push(0); // 0 = OS-assigned dynamic port (last resort)

      let attemptIdx = 0;

      const tryListen = (port: number, host: string): void => {
        server!.listen(port, host, () => {
          proxyPort = (server!.address() as import('net').AddressInfo).port;
          const isFallback = port !== defaultPort && port !== 0;
          const isDynamic = port === 0;
          if (isFallback) {
            log.warn(`[Proxy] Default port ${defaultPort} unavailable. Using fallback port ${proxyPort}.`);
            log.warn(`[Proxy] Set AG_PROXY_PORT=${proxyPort} in your environment to silence this warning.`);
          } else if (isDynamic) {
            log.warn(`[Proxy] All configured ports in use. Using OS-assigned dynamic port ${proxyPort}.`);
          } else {
            log.info(`[Proxy] Server listening on http://${host}:${proxyPort}`);
          }

          // Persist the active port so other processes (ag-doctor-ui, scripts)
          // can discover which port the proxy is actually bound to.
          try {
            const home = process.env.HOME || process.env.USERPROFILE || os.homedir();
            const portFile = path.join(home, ACTIVE_PORT_FILE);
            fs.mkdirSync(path.dirname(portFile), { recursive: true });
            fs.writeFileSync(portFile, String(proxyPort), 'utf-8');
            log.debug(`[Proxy] Active port persisted to ${portFile}`);
          } catch (err) {
            log.warn('[Proxy] Could not persist active port:', (err as Error).message);
          }

          // Execute cleanup initialization after the server is already listening
          // so that failures here don't prevent the port from binding.
          try {
            startCleanupInterval();
          } catch (err) {
            log.error('[Proxy] Failed to start cleanup interval:', err);
          }

          resolve(proxyPort);
        });
      };

      server.on('error', (err: NodeJS.ErrnoException) => {
        // Log full error details for diagnostics on new machines.
        log.error(`[Proxy] Server error: code=${err.code} message=${err.message} syscall=${err.syscall || ''} address=${(err as any).address || ''} port=${(err as any).port || ''}`);
        if (err.code === 'EADDRINUSE' && attemptIdx + 1 < portCandidates.length) {
          const triedPort = portCandidates[attemptIdx];
          const nextPort = portCandidates[attemptIdx + 1];
          log.warn(`[Proxy] Port ${triedPort} is already in use. Trying ${nextPort === 0 ? 'OS-assigned dynamic port' : 'port ' + nextPort}...`);
          attemptIdx += 1;
          tryListen(nextPort, primaryHost);
        } else if (err.code === 'EACCES') {
          // P2: Surface permission errors clearly instead of silently failing.
          log.error(`[Proxy] Permission denied binding to ${primaryHost}:${primaryPort}. Try a different port (AG_PROXY_PORT) or run with sufficient privileges.`);
          reject(err);
        } else {
          log.error('[Proxy] Startup failed:', err);
          reject(err);
        }
      });

      primaryPort = portCandidates[0];
      tryListen(primaryPort, primaryHost);
    } catch (err) {
      log.error('[Proxy] Unexpected error during startProxy:', err);
      reject(err);
    }
  });
}

export function stopProxy(): Promise<void> {
  return new Promise((resolve) => {
    // P1-9: Stop cleanup interval to prevent orphaned timers
    stopCleanupInterval();

    if (server) {
      server.close(() => {
        log.info('[Proxy] Server stopped');
        server = null;
        resolve();
      });
    } else {
      resolve();
    }
  });
}

export function getProxyPort(): number {
  return proxyPort;
}
