"use strict";
// ─── Constants ─────────────────────────────────────────────────────────────
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.toSlug = exports.generateModelPlaceholderId = void 0;
exports.parseRetryAfter = parseRetryAfter;
exports.startProxy = startProxy;
exports.stopProxy = stopProxy;
exports.getProxyPort = getProxyPort;
const http = __importStar(require("http"));
const https = __importStar(require("https"));
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
const os = __importStar(require("os"));
const electron_log_1 = __importDefault(require("electron-log"));
let server = null;
let proxyPort = 0;
const constants_1 = require("./constants");
// ─── Module Imports ───────────────────────────────────────────────────────
// Shared cross-turn state
const shared_1 = require("./proxy/shared");
// Model configuration & capability detection
const modelUtils_1 = require("./proxy/modelUtils");
// Provider translator registry (auto-discovers translators from proxy/translators/)
const registry = __importStar(require("./proxy/registry"));
// Protobuf injection (extracted from proxy.ts)
const protoInjector_1 = require("./proxy/protoInjector");
// Custom model loading (extracted from proxy.ts)
const modelLoader_1 = require("./proxy/modelLoader");
const customModelStore_1 = require("./customModelStore");
const errorClassifier_1 = require("./proxy/errorClassifier");
const retryStrategy_1 = require("./proxy/retryStrategy");
const circuitBreaker_1 = require("./proxy/circuitBreaker");
const idleTimeout_1 = require("./proxy/idleTimeout");
const agentPool_1 = require("./proxy/agentPool");
const emptyStream_1 = require("./proxy/emptyStream");
function generateGracefulMarkdown(diagnostic) {
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
const urlBuilder_1 = require("./proxy/urlBuilder");
// ID generation (extracted from proxy.ts)
const idGenerator_1 = require("./proxy/idGenerator");
Object.defineProperty(exports, "generateModelPlaceholderId", { enumerable: true, get: function () { return idGenerator_1.generateModelPlaceholderId; } });
Object.defineProperty(exports, "toSlug", { enumerable: true, get: function () { return idGenerator_1.toSlug; } });
// DNS resolution bypasses the poisoned hosts file (extracted from proxy.ts)
const dnsResolver_1 = require("./proxy/dnsResolver");
// ─── Safe Response Helpers ─────────────────────────────────────────────────
// Guard flag pattern to prevent ERR_HTTP_HEADERS_SENT when timeout and
// upstream response race. Returns true if the operation succeeded, false if
// the response was already terminated.
function safeWriteHead(res, status, headers) {
    if (res.headersSent || res.writableEnded) {
        return false;
    }
    try {
        res.writeHead(status, headers);
        return true;
    }
    catch (err) {
        electron_log_1.default.warn('[Proxy] safeWriteHead failed:', err.message);
        return false;
    }
}
function safeEnd(res, data) {
    if (res.writableEnded) {
        return false;
    }
    try {
        res.end(data);
        return true;
    }
    catch (err) {
        electron_log_1.default.warn('[Proxy] safeEnd failed:', err.message);
        return false;
    }
}
// ─── Model Helpers ────────────────────────────────────────────────────────
// generateModelPlaceholderId and toSlug are now in ./proxy/idGenerator.ts (re-exported above)
// ─── Google Proxy ─────────────────────────────────────────────────────────
async function proxyToGoogle(req, res, reqBody) {
    const isCloudCodeUrl = req.url.includes('v1internal') || req.url.includes('daily-cloudcode');
    const targetHost = isCloudCodeUrl ? 'daily-cloudcode-pa.googleapis.com' : 'generativelanguage.googleapis.com';
    const targetUrl = `https://${targetHost}`;
    const parsedUrl = new URL(req.url, targetUrl);
    try {
        const realIp = await (0, dnsResolver_1.resolveGoogleIp)(targetHost);
        parsedUrl.hostname = realIp;
    }
    catch (e) {
        electron_log_1.default.error(`[Proxy] Could not resolve upstream IP for ${targetHost}:`, e);
        if (safeWriteHead(res, 500, { 'Content-Type': 'application/json' })) {
            safeEnd(res, JSON.stringify({ error: { message: 'DNS resolution failed for ' + targetHost } }));
        }
        return;
    }
    const headers = {
        ...req.headers,
    };
    headers['host'] = targetHost;
    delete headers['connection'];
    delete headers['keep-alive'];
    const isGeneration = req.url.includes('generateContent') || req.url.includes('streamGenerateContent');
    const shouldBufferAndModify = isCloudCodeUrl && !isGeneration;
    if (shouldBufferAndModify) {
        delete headers['accept-encoding'];
    }
    const options = {
        method: req.method,
        headers: headers,
        servername: targetHost,
    };
    // Guard flag to prevent ERR_HTTP_HEADERS_SENT when timeout and response race
    const safeHead = (status, headers) => safeWriteHead(res, status, headers);
    const proxyReq = https.request(parsedUrl, options, (proxyRes) => {
        proxyReq.setTimeout(constants_1.GOOGLE_PROXY_TIMEOUT_MS, () => {
            electron_log_1.default.error(`[Proxy] Google proxy request timed out after ${constants_1.GOOGLE_PROXY_TIMEOUT_MS / 1000}s`);
            proxyReq.destroy();
            if (safeHead(504, { 'Content-Type': 'application/json' })) {
                safeEnd(res, JSON.stringify({ error: { message: 'Google API request timed out' } }));
            }
        });
        if (shouldBufferAndModify) {
            const responseChunks = [];
            proxyRes.on('data', (chunk) => responseChunks.push(chunk));
            proxyRes.on('end', () => {
                if (res.headersSent || res.writableEnded) {
                    electron_log_1.default.debug('[Proxy] Skipping buffered modify: response already terminated');
                    return;
                }
                const fullResBody = Buffer.concat(responseChunks);
                let text;
                const encoding = proxyRes.headers['content-encoding'];
                if (encoding === 'gzip') {
                    try {
                        const zlib = require('zlib');
                        text = zlib.gunzipSync(fullResBody).toString('utf-8');
                    }
                    catch (e) {
                        electron_log_1.default.error('[Proxy] gunzipSync failed:', e);
                        text = fullResBody.toString('utf-8');
                    }
                }
                else {
                    text = fullResBody.toString('utf-8');
                }
                electron_log_1.default.info(`[Proxy] Response for ${req.url} (status: ${proxyRes.statusCode}, encoding: ${encoding}, length: ${text.length})`);
                // P0-3: Response body content is NOT logged to disk. Only metadata.
                const proxyHost = req.headers.host || 'localhost';
                const proxyProto = proxyHost.endsWith('.googleapis.com') ? 'https:' : 'http:';
                text = text.replace(/https:(\/\/)daily-cloudcode-pa\.googleapis\.com/g, `${proxyProto}$1${proxyHost}`);
                text = text.replace(/https:(\/\/)cloudcode-pa\.googleapis\.com/g, `${proxyProto}$1${proxyHost}`);
                text = text.replace(/https:(\/\/)generativelanguage\.googleapis\.com/g, `${proxyProto}$1${proxyHost}`);
                const modifiedHeaders = { ...proxyRes.headers };
                delete modifiedHeaders['content-encoding'];
                delete modifiedHeaders['transfer-encoding'];
                const modifiedBuffer = Buffer.from(text, 'utf-8');
                modifiedHeaders['content-length'] = String(modifiedBuffer.length);
                if (safeWriteHead(res, proxyRes.statusCode || 200, modifiedHeaders)) {
                    safeEnd(res, modifiedBuffer);
                }
            });
        }
        else {
            if (safeHead(proxyRes.statusCode || 200, proxyRes.headers)) {
                proxyRes.pipe(res);
            }
        }
    });
    proxyReq.on('error', (err) => {
        electron_log_1.default.error('[Proxy] Google Forwarding Error:', err);
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
async function resolveFileData(body, reqHeaders) {
    const contents = body.contents;
    if (!contents)
        return;
    const authHeader = (reqHeaders['authorization'] || reqHeaders['Authorization'] || '');
    for (const item of contents) {
        if (!item.parts)
            continue;
        for (let i = 0; i < item.parts.length; i++) {
            const p = item.parts[i];
            const fd = p.fileData;
            if (!fd?.fileUri)
                continue;
            // Keep image fileData intact so provider translators can map it natively.
            if (fd.mimeType?.startsWith('image/'))
                continue;
            try {
                const uri = fd.fileUri;
                let fileContent = '';
                if (uri.startsWith('file://')) {
                    const fp = uri.replace('file://', '').replace(/\//g, path.sep);
                    if (fs.existsSync(fp))
                        fileContent = fs.readFileSync(fp, 'utf-8');
                }
                else if (authHeader && uri.startsWith('https://')) {
                    fileContent = await downloadFileContent(uri, authHeader);
                }
                if (fileContent) {
                    item.parts[i] = { text: '[File content]:\n\n' + fileContent };
                }
            }
            catch (e) {
                electron_log_1.default.warn('[Proxy] File resolve failed:', e.message);
            }
        }
    }
}
function downloadFileContent(url, authHeader) {
    return new Promise((resolve, reject) => {
        const u = new URL(url);
        (u.protocol === 'https:' ? https : http).request({
            hostname: u.hostname, path: u.pathname + u.search,
            method: 'GET', headers: { 'Authorization': authHeader }, timeout: constants_1.FILE_DOWNLOAD_TIMEOUT_MS,
        }, (res) => {
            if (res.statusCode !== 200) {
                reject(new Error('HTTP ' + res.statusCode));
                return;
            }
            let d = '';
            res.on('data', (c) => d += c.toString());
            res.on('end', () => resolve(d));
        }).on('error', reject).end();
    });
}
// ─── Custom Model Request Handler ─────────────────────────────────────────
/**
 * Parses the Retry-After header from upstream responses (RFC 7231 §7.1.3).
 * Returns delay in milliseconds, or 0 if no valid header is present.
 */
function parseRetryAfter(headers) {
    const val = headers['retry-after'];
    if (!val)
        return 0;
    const raw = Array.isArray(val) ? val[0] : val;
    if (!raw)
        return 0;
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
function handleCustomModelRequest(res, model, geminiBody, isStream, retryCount = 0, fallbackDepth = 0) {
    // P3-18: Configurable max retries per model (default 1, min 0, max 5).
    // Lowered from 3 to 1 to prevent retry storms saturating the proxy.
    const MAX_RETRIES = (0, urlBuilder_1.resolveMaxRetries)(model);
    const REQUEST_TIMEOUT_MS = (0, urlBuilder_1.resolveRequestTimeout)(model);
    // Circuit breaker: if this model just failed hard, short-circuit before
    // touching the upstream. This keeps the proxy responsive so the rest of
    // the model dropdown (and fetchAvailableModels) keeps working.
    const openBreaker = (0, circuitBreaker_1.getOpenBreaker)(model);
    if (openBreaker && retryCount === 0 && fallbackDepth === 0) {
        const cached = (0, errorClassifier_1.classifyError)(openBreaker.errorType === 'rate_limit' ? 429 : 500, openBreaker.errorType, undefined, model.provider);
        electron_log_1.default.warn(`[Proxy] Circuit OPEN for ${model.name} (${openBreaker.errorType}, tripped ${Math.round((Date.now() - openBreaker.trippedAt) / 1000)}s ago). Short-circuiting request.`);
        // attemptFallback is defined as a nested closure below; it shares
        // res/model/geminiBody/isStream/fallbackDepth via lexical scope.
        const breakerAttemptFallback = (res, _model, _body, _isStream, diagnostic, _depth) => {
            if (fallbackDepth >= 2)
                return false;
            try {
                const allModels = (0, modelLoader_1.loadCustomModels)();
                for (const m of allModels) {
                    if (m.name !== model.name && m.apiKey && !m.apiKey.startsWith('fallback:')) {
                        const toName = m.displayName || m.name;
                        electron_log_1.default.warn(`[Proxy] Circuit-OPEN fallback: ${model.name} -> ${toName} (reason: ${diagnostic.errorType})`);
                        handleCustomModelRequest(res, m, _body, _isStream, 0, fallbackDepth + 1);
                        return true;
                    }
                }
            }
            catch (e) {
                electron_log_1.default.error('[Proxy] Circuit-OPEN fallback exception:', e);
            }
            return false;
        };
        if (breakerAttemptFallback(res, model, geminiBody, isStream, cached, fallbackDepth)) {
            return;
        }
        const statusCode = openBreaker.errorType === 'rate_limit' ? 429 : 503;
        if (safeWriteHead(res, statusCode, {
            'Content-Type': 'application/json',
            'X-AG-Error-Type': cached.errorType,
            'X-AG-Circuit': 'open',
        })) {
            safeEnd(res, JSON.stringify({
                error: {
                    message: `Model ${model.name} is temporarily unavailable (${cached.title}). Retried shortly.`,
                },
                _agDiagnostic: cached,
            }));
        }
        return;
    }
    function attemptFallback(diagnostic) {
        if (fallbackDepth >= 2)
            return false;
        const isEligibleForFallback = diagnostic.errorType === 'rate_limit' ||
            diagnostic.errorType === 'server' ||
            diagnostic.errorType === 'network' ||
            diagnostic.errorType === 'billing' ||
            diagnostic.errorType === 'timeout';
        if (!isEligibleForFallback)
            return false;
        try {
            const allModels = (0, modelLoader_1.loadCustomModels)();
            for (const m of allModels) {
                if (m.name !== model.name && m.apiKey && !m.apiKey.startsWith('fallback:')) {
                    const fromName = model.displayName || model.name;
                    const toName = m.displayName || m.name;
                    electron_log_1.default.warn(`[Proxy] Auto-fallback: ${fromName} → ${toName} (reason: ${diagnostic.errorType} — ${diagnostic.title})`);
                    // L-1: Notify the user in the stream so the fallback is transparent.
                    // We send a brief markdown notice as the first SSE event before
                    // delegating to the fallback model handler.
                    if (isStream && !res.headersSent) {
                        if (safeWriteHead(res, 200, {
                            'Content-Type': 'text/event-stream',
                            'Cache-Control': 'no-cache',
                            Connection: 'keep-alive',
                            'X-Accel-Buffering': 'no',
                            'X-AG-Fallback': 'true',
                        })) {
                            const notice = {
                                response: {
                                    candidates: [{
                                            content: {
                                                parts: [{ text: `> ⚠️ **Auto-fallback:** \`${fromName}\` failed (${diagnostic.errorType}). Retrying with \`${toName}\`…\n\n` }],
                                                role: 'model',
                                            },
                                            finishReason: 'STOP',
                                            index: 0,
                                        }],
                                },
                                traceId: '',
                                metadata: {},
                            };
                            res.write('data: ' + JSON.stringify(notice) + '\n\n');
                        }
                    }
                    handleCustomModelRequest(res, m, geminiBody, isStream, 0, fallbackDepth + 1);
                    return true;
                }
            }
        }
        catch (e) {
            electron_log_1.default.error('[Proxy] Auto-fallback exception:', e);
        }
        return false;
    }
    const provider = (0, urlBuilder_1.resolveProvider)(model);
    const cleanModelName = (0, urlBuilder_1.getBaseModelId)(model.externalModelName);
    const payload = registry.translateRequest(provider, geminiBody, cleanModelName, model.extraBody);
    const headers = registry.getProviderHeaders(provider, model.apiKey, model.extraHeaders);
    if (isStream && registry.supportsStreaming(provider)) {
        payload.stream = true;
    }
    const finalUrlStr = (0, urlBuilder_1.resolveCustomModelUrl)(model, isStream, (apiUrl, externalModelName, stream, translator) => registry.getProviderUrl(apiUrl, externalModelName, stream, translator));
    const url = new URL(finalUrlStr);
    // Phase 3: per-host connection pooling via the agent cache. This avoids
    // a fresh TLS handshake on every chat turn (vendor pattern ported from
    // vscode-unify-chat-provider's `undici.Agent` cache). Default Node
    // globalAgent has keepAlive=false on Node 18+, so we use a stable,
    // keep-alive enabled agent per (scheme, host, port) tuple.
    const { client: pooledClient, agent } = (0, agentPool_1.resolveClientForUrl)(finalUrlStr, !!model.allowUnauthorized);
    const options = {
        method: 'POST',
        headers: headers,
        agent,
    };
    // P0-2: SSL bypass ONLY when user explicitly opts in via allowUnauthorized.
    // Custom providers no longer bypass SSL automatically.
    if (model.allowUnauthorized) {
        electron_log_1.default.warn(`[Proxy] SSL verification DISABLED for ${model.name} (allowUnauthorized=true). Connection is vulnerable to MITM.`);
        options.rejectUnauthorized = false;
    }
    electron_log_1.default.info(`[Proxy] Routing ${model.name} to ${model.provider} (${model.apiUrl}) (isStream: ${!!isStream})${retryCount > 0 ? ` (retry ${retryCount})` : ''}`);
    const request = pooledClient.request(finalUrlStr, options, (apiRes) => {
        apiRes.on('error', (err) => {
            electron_log_1.default.error(`[Proxy] Upstream stream error for ${model.name}:`, err.message);
            const diagnostic = (0, errorClassifier_1.classifyError)(500, err, undefined, model.provider);
            if (safeWriteHead(res, 500, {
                'Content-Type': 'application/json',
                'X-AG-Error-Type': diagnostic.errorType
            })) {
                safeEnd(res, JSON.stringify({ error: { message: 'Upstream connection error: ' + err.message }, _agDiagnostic: diagnostic }));
            }
            else if (!res.writableEnded) {
                safeEnd(res);
            }
        });
        const status = apiRes.statusCode || 0;
        // P3: Log 401 errors with detailed diagnostic context to help users
        // understand why their custom endpoint rejected the request.
        // Common causes: missing API key, wrong header name, expired token,
        // wrong endpoint URL, account suspended.
        if (status === 401) {
            // S-2: Never log actual key material — only presence and length bucket.
            const apiKeyInfo = model.apiKey && model.apiKey !== 'none'
                ? `<set, len=${model.apiKey.length > 50 ? '>50' : model.apiKey.length <= 20 ? '≤20' : '21-50'}>`
                : '<empty or none>';
            electron_log_1.default.error(`[Proxy] 401 Unauthorized from ${model.name} (${model.provider})`);
            electron_log_1.default.error(`[Proxy]   URL: ${finalUrlStr}`);
            electron_log_1.default.error(`[Proxy]   API key: ${apiKeyInfo}`);
            electron_log_1.default.error(`[Proxy]   Headers sent: ${Object.keys(headers).join(', ')}`);
            electron_log_1.default.error(`[Proxy]   Possible causes:`);
            electron_log_1.default.error(`[Proxy]     - Missing or invalid API key (check custom_models.json)`);
            electron_log_1.default.error(`[Proxy]     - Wrong header name for this provider (e.g. 'Authorization' vs 'x-api-key')`);
            electron_log_1.default.error(`[Proxy]     - Expired or revoked token`);
            electron_log_1.default.error(`[Proxy]     - Account suspended or rate-limited`);
            electron_log_1.default.error(`[Proxy]     - Wrong endpoint URL (${finalUrlStr})`);
            electron_log_1.default.error(`[Proxy]   Upstream response: ${JSON.stringify(apiRes.headers).slice(0, 200)}`);
        }
        if (isStream) {
            // Check for API errors BEFORE writing streaming headers
            if (apiRes.statusCode >= 400) {
                let errorBody = '';
                apiRes.on('data', (chunk) => errorBody += chunk.toString());
                apiRes.on('end', () => {
                    electron_log_1.default.error(`[Proxy] Stream API error (${apiRes.statusCode}) for ${model.name}: ${errorBody.substring(0, 300)}`);
                    const streamDiagnostic = (0, errorClassifier_1.classifyError)(apiRes.statusCode, null, errorBody, model.provider);
                    // Trip the breaker on the first hard failure so subsequent
                    // requests short-circuit instead of piling up against a stuck upstream.
                    if (streamDiagnostic.errorType === 'server' ||
                        streamDiagnostic.errorType === 'rate_limit' ||
                        streamDiagnostic.errorType === 'timeout' ||
                        streamDiagnostic.errorType === 'network') {
                        (0, circuitBreaker_1.recordFailure)(model, streamDiagnostic.errorType);
                    }
                    if ((0, retryStrategy_1.shouldRetryStatus)(apiRes.statusCode, retryCount, MAX_RETRIES)) {
                        electron_log_1.default.warn(`[Proxy] Stream error, retrying (${retryCount + 1}/${MAX_RETRIES})...`);
                        setTimeout(() => handleCustomModelRequest(res, model, geminiBody, isStream, retryCount + 1), 1000 * (retryCount + 1));
                        return;
                    }
                    const diagnostic = streamDiagnostic;
                    if (attemptFallback(diagnostic))
                        return;
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
                    }
                    catch {
                        // not JSON
                    }
                    if (typeof responseJson === 'object' && responseJson !== null) {
                        responseJson._agDiagnostic = diagnostic;
                    }
                    if (safeWriteHead(res, apiRes.statusCode, {
                        'Content-Type': 'application/json',
                        'X-AG-Error-Type': diagnostic.errorType
                    })) {
                        safeEnd(res, JSON.stringify(responseJson));
                    }
                });
                return;
            }
            if (apiRes.statusCode === 200) {
                // Any successful response proves the upstream is healthy again;
                // clear the breaker so subsequent requests don't short-circuit.
                (0, circuitBreaker_1.recordSuccess)(model);
            }
            if (!safeWriteHead(res, 200, {
                'Content-Type': 'text/event-stream',
                'Cache-Control': 'no-cache',
                Connection: 'keep-alive',
                'X-Accel-Buffering': 'no',
            })) {
                return;
            }
            // Phase 2: Per-chunk idle timeout guard. Vendor pattern from
            // `withIdleTimeout`'s stream wrapper. If no SSE chunk arrives for
            // STREAM_IDLE_TIMEOUT_MS, treat the upstream as stuck and abort.
            const idleGuard = new idleTimeout_1.IdleTimeoutGuard(apiRes, {
                idleTimeoutMs: constants_1.STREAM_IDLE_TIMEOUT_MS,
                label: model.name,
                onTimeout: (err) => {
                    electron_log_1.default.warn(`[Proxy] ${err.message} — aborting request for ${model.name}`);
                    (0, circuitBreaker_1.recordFailure)(model, 'timeout');
                    try {
                        request.destroy(err);
                    }
                    catch { /* already destroyed */ }
                },
            });
            // Phase 4: Empty-stream guard. Track raw chunks + SSE frames so we can
            // detect a 200 OK stream that contains no usable content (e.g. upstream
            // returns `[DONE]` immediately, or only keep-alive comments, or zero
            // non-empty chunks). Vendor pattern: "did we get something useful?" AND
            // gate from `vscode-unify-chat-provider`.
            const emptyGuard = new emptyStream_1.EmptyStreamGuard();
            let buffer = '';
            apiRes.on('data', (chunk) => {
                // Observe first, then forward. The guard splits SSE frames on
                // newlines so a frame that spans two chunks is still counted.
                emptyGuard.observe(chunk);
                buffer += chunk.toString('utf-8');
                const lines = buffer.split('\n');
                buffer = lines.pop() || '';
                for (const line of lines) {
                    const trimmed = line.trim();
                    if (!trimmed)
                        continue;
                    if (trimmed.startsWith('data: ')) {
                        const dataStr = trimmed.substring(6).trim();
                        if (dataStr === '[DONE]')
                            continue;
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
                        }
                        catch (err) {
                            // Partial/invalid JSON chunks are normal during streaming; debug-level only
                            electron_log_1.default.debug(`[Proxy] Stream chunk parse warning for ${model.name}:`, err.message);
                        }
                    }
                }
            });
            apiRes.on('end', () => {
                idleGuard.dispose();
                emptyGuard.observe(Buffer.from('')); // no-op, but tightens API
                // Phase 4: Detect empty streams BEFORE finalizing the response.
                // An empty stream is a 200 OK response with no SSE data frames.
                // We retry once (unless MAX_RETRIES is already exhausted) to give
                // flaky upstreams a second chance before surfacing an error.
                const verdict = emptyGuard.finalize({ statusCode: apiRes.statusCode ?? 0 });
                if (verdict.isEmpty && retryCount < MAX_RETRIES) {
                    electron_log_1.default.warn(`[Proxy] Empty stream from ${model.name}: ${verdict.reason} ` +
                        `(0 frames, ${verdict.bytesReceived}B) — retrying (${retryCount + 1}/${MAX_RETRIES}).`);
                    (0, circuitBreaker_1.recordFailure)(model, 'empty_stream');
                    setTimeout(() => handleCustomModelRequest(res, model, geminiBody, isStream, retryCount + 1), 500 * (retryCount + 1));
                    return;
                }
                if (verdict.isEmpty) {
                    electron_log_1.default.warn(`[Proxy] Empty stream from ${model.name}: ${verdict.reason} ` +
                        `(0 frames, ${verdict.bytesReceived}B) — max retries exhausted.`);
                }
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
                        }
                        catch (e) {
                            electron_log_1.default.debug(`[Proxy] Stream buffer drain parse warning for ${model.name}:`, e.message);
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
                const pId = model.name.includes('-') ? model.name.split('-')[0] : model.provider;
                void (0, customModelStore_1.recordProviderUsage)(pId, 100, 150);
            });
        }
        else {
            let body = '';
            apiRes.on('data', (chunk) => (body += chunk));
            apiRes.on('end', () => {
                // Retry if eligible based on status code
                if ((0, retryStrategy_1.shouldRetryStatus)(apiRes.statusCode, retryCount, MAX_RETRIES)) {
                    const retryAfter = parseRetryAfter(apiRes.headers);
                    const delay = retryAfter > 0 ? retryAfter : (apiRes.statusCode === 429 ? 2000 : 1000) * Math.pow(2, retryCount);
                    electron_log_1.default.warn(`[Proxy] Upstream error status ${apiRes.statusCode} for ${model.name}, retrying in ${delay}ms (${retryCount + 1}/${MAX_RETRIES})...`);
                    setTimeout(() => handleCustomModelRequest(res, model, geminiBody, isStream, retryCount + 1), delay);
                    return;
                }
                if (apiRes.statusCode >= 400) {
                    // P0-3: Only log status code and model name, NOT response body content
                    electron_log_1.default.error(`[Proxy] API error (${apiRes.statusCode}) for ${model.name}`);
                    const diagnostic = (0, errorClassifier_1.classifyError)(apiRes.statusCode, null, body, model.provider);
                    // Trip the breaker on hard failures so subsequent requests
                    // short-circuit instead of piling up against a stuck upstream.
                    if (diagnostic.errorType === 'server' ||
                        diagnostic.errorType === 'rate_limit' ||
                        diagnostic.errorType === 'timeout' ||
                        diagnostic.errorType === 'network') {
                        (0, circuitBreaker_1.recordFailure)(model, diagnostic.errorType);
                    }
                    if (attemptFallback(diagnostic))
                        return;
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
                    }
                    catch {
                        // not JSON
                    }
                    if (typeof responseJson === 'object' && responseJson !== null) {
                        responseJson._agDiagnostic = diagnostic;
                    }
                    if (safeWriteHead(res, apiRes.statusCode, {
                        'Content-Type': 'application/json',
                        'X-AG-Error-Type': diagnostic.errorType
                    })) {
                        safeEnd(res, JSON.stringify(responseJson));
                    }
                    return;
                }
                try {
                    const parsed = JSON.parse(body);
                    const reasoning = parsed.choices?.[0]
                        ?.message?.reasoning_content ||
                        parsed.choices?.[0]
                            ?.message?.reasoning;
                    if (reasoning) {
                        shared_1.modelReasoningContent.set(model.name, reasoning);
                        (0, shared_1.touchStateTimestamp)(shared_1.stateTimestamps.reasoning, model.name);
                    }
                    const providerForResponse = model.provider === 'custom' || model.provider === 'openrouter' ? 'openai' : model.provider;
                    const mapped = registry.translateResponse(providerForResponse, parsed, model.name);
                    const cloudCodeResponse = {
                        response: mapped,
                        traceId: '',
                        metadata: {},
                    };
                    // Successful 2xx response — clear breaker for this model.
                    (0, circuitBreaker_1.recordSuccess)(model);
                    if (safeWriteHead(res, 200, { 'Content-Type': 'application/json' })) {
                        safeEnd(res, JSON.stringify(cloudCodeResponse));
                    }
                }
                catch (e) {
                    electron_log_1.default.error('[Proxy] Failed to map response:', e);
                    if (retryCount < MAX_RETRIES) {
                        electron_log_1.default.warn(`[Proxy] Parse error for ${model.name}, retrying (${retryCount + 1}/${MAX_RETRIES})...`);
                        setTimeout(() => handleCustomModelRequest(res, model, geminiBody, isStream, retryCount + 1), 1000 * (retryCount + 1));
                        return;
                    }
                    const diagnostic = (0, errorClassifier_1.classifyError)(500, e, body, model.provider);
                    if (attemptFallback(diagnostic))
                        return;
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
        electron_log_1.default.error(`[Proxy] Request timeout (${REQUEST_TIMEOUT_MS}ms) for ${model.name}`);
        request.destroy();
        // Trip the breaker immediately on timeout — these are the worst offender
        // in retry storms (the request holds the proxy open for the full timeout).
        (0, circuitBreaker_1.recordFailure)(model, 'timeout');
        if (retryCount < MAX_RETRIES) {
            electron_log_1.default.warn(`[Proxy] Timeout for ${model.name}, retrying (${retryCount + 1}/${MAX_RETRIES})...`);
            setTimeout(() => handleCustomModelRequest(res, model, geminiBody, isStream, retryCount + 1), 1000 * (retryCount + 1));
            return;
        }
        const diagnostic = (0, errorClassifier_1.classifyError)(504, 'ETIMEDOUT', undefined, model.provider);
        if (attemptFallback(diagnostic))
            return;
        if (safeWriteHead(res, 504, {
            'Content-Type': 'application/json',
            'X-AG-Error-Type': diagnostic.errorType
        })) {
            safeEnd(res, JSON.stringify({ error: { message: `Request timeout after ${REQUEST_TIMEOUT_MS / 1000}s` }, _agDiagnostic: diagnostic }));
        }
    });
    request.on('error', (err) => {
        electron_log_1.default.error('[Proxy] Custom Model Request Error:', err);
        // Trip the breaker on network errors so the proxy stops hammering the
        // dead upstream. Use the error's code when present, default to 'network'.
        const code = err.code?.toUpperCase();
        const breakerType = code === 'ETIMEDOUT' || code === 'ESOCKETTIMEDOUT' ? 'timeout' :
            code === 'ENOTFOUND' || code === 'EAI_AGAIN' ? 'dns' :
                'network';
        (0, circuitBreaker_1.recordFailure)(model, breakerType);
        if (retryCount < MAX_RETRIES) {
            electron_log_1.default.warn(`[Proxy] Network error for ${model.name}, retrying (${retryCount + 1}/${MAX_RETRIES})...`);
            setTimeout(() => handleCustomModelRequest(res, model, geminiBody, isStream, retryCount + 1), 1000 * (retryCount + 1));
            return;
        }
        const diagnostic = (0, errorClassifier_1.classifyError)(undefined, err, undefined, model.provider);
        if (attemptFallback(diagnostic))
            return;
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
        }
        else {
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
function handleGetAvailableModelsProxy(res, reqBody, lsUrl) {
    const lsParsed = new URL(lsUrl);
    const client = lsParsed.protocol === 'https:' ? https : http;
    const options = {
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
            electron_log_1.default.error('[Proxy] LS error for GetAvailableModels:', err.message);
            if (!res.headersSent && !res.writableEnded) {
                safeWriteHead(res, 502);
                safeEnd(res);
            }
        });
        const chunks = [];
        lsRes.on('data', (chunk) => chunks.push(chunk));
        lsRes.on('end', () => {
            // Guard: timeout or error may have already terminated the response
            if (lsResErrored || res.headersSent || res.writableEnded) {
                electron_log_1.default.debug('[Proxy] GetAvailableModels: skipping end handler (response terminated)');
                return;
            }
            const responseBuf = Buffer.concat(chunks);
            const customModels = (0, modelLoader_1.loadCustomModels)();
            const { buffer: modifiedBuf } = (0, protoInjector_1.injectCustomModelsIntoResponse)(responseBuf, customModels);
            if (safeWriteHead(res, lsRes.statusCode || 200, {
                'Content-Type': 'application/grpc-web+proto',
                'Content-Length': String(modifiedBuf.length),
            })) {
                safeEnd(res, modifiedBuf);
            }
        });
    });
    lsReq.setTimeout(30000, () => {
        electron_log_1.default.error('[Proxy] GetAvailableModels forward timed out');
        lsReq.destroy();
        if (!res.headersSent && !res.writableEnded) {
            safeWriteHead(res, 504);
            safeEnd(res);
        }
    });
    lsReq.on('error', (err) => {
        electron_log_1.default.error('[Proxy] GetAvailableModels forward error:', err.message);
        if (!res.headersSent && !res.writableEnded) {
            safeWriteHead(res, 502);
            safeEnd(res);
        }
    });
    lsReq.write(reqBody);
    lsReq.end();
}
// ─── Main Request Handler ─────────────────────────────────────────────────
function isAllowedOrigin(req) {
    const host = (req.headers.host || '').toLowerCase();
    const origin = (req.headers.origin || req.headers.referer || '').toLowerCase();
    // 1. Validate Host header — local loopback or googleapis upstream
    const allowedHostPrefixes = ['127.0.0.1', 'localhost', '::1'];
    const isHostAllowed = allowedHostPrefixes.some((h) => host.startsWith(h)) || host.endsWith('.googleapis.com');
    if (!isHostAllowed)
        return false;
    // 2. Direct requests without Origin/Referer (Language Server Go, internal gRPC/HTTP)
    if (!origin)
        return true;
    // 3. Validate Origin/Referer header against known trusted local and Google origins
    return (origin.startsWith('https://127.0.0.1') ||
        origin.startsWith('http://127.0.0.1') ||
        origin.startsWith('http://localhost') ||
        origin.includes('googleapis.com'));
}
function handleRequest(req, res) {
    // CSRF / Origin Guard: Reject unauthorized external origins attempting local proxy abuse
    if (!isAllowedOrigin(req)) {
        electron_log_1.default.warn(`[Proxy] Blocked request with unauthorized Host/Origin: host=${req.headers.host} origin=${req.headers.origin}`);
        res.writeHead(403, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: { message: 'Forbidden: Unauthorized origin' } }));
        return;
    }
    // Health check — keep this FIRST so the LS sees a live port even if other
    // initialization (padding strip, model loading, etc.) is delayed or fails.
    if (req.method === 'GET' && (req.url === '/health' || req.url === '/healthz')) {
        electron_log_1.default.info(`[Proxy] /health hit from ${req.socket.remoteAddress || 'unknown'}`);
        const memUsage = process.memoryUsage();
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
            status: 'ok',
            uptime: process.uptime(),
            port: proxyPort,
            memory: {
                rssMB: Math.round(memUsage.rss / 1024 / 1024),
                heapUsedMB: Math.round(memUsage.heapUsed / 1024 / 1024),
                heapTotalMB: Math.round(memUsage.heapTotal / 1024 / 1024),
            },
            state: {
                activeStreamContexts: shared_1.activeStreamContexts.size,
                modelToolCallIds: shared_1.modelToolCallIds.size,
                translatedToolCalls: shared_1.translatedToolCalls.size,
                modelReasoningContent: shared_1.modelReasoningContent.size,
            },
            timestamp: new Date().toISOString(),
        }));
        return;
    }
    // Per-model health status — returns circuit breaker state for each custom
    // model so the renderer dropdown can show live green/red indicators.
    // Reads only in-memory state, no upstream calls, ~1ms response time.
    if (req.method === 'GET' && req.url === '/model-health') {
        const customModels = (0, modelLoader_1.loadCustomModels)();
        const statuses = {};
        for (const m of customModels) {
            const placeholderId = (0, idGenerator_1.generateModelPlaceholderId)(m);
            const breaker = (0, circuitBreaker_1.getOpenBreaker)(m);
            if (breaker) {
                statuses[placeholderId] = {
                    status: 'error',
                    errorType: breaker.errorType,
                    trippedAt: breaker.trippedAt,
                    failures: breaker.failures,
                };
            }
            else {
                statuses[placeholderId] = { status: 'healthy' };
            }
        }
        res.writeHead(200, {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
        });
        res.end(JSON.stringify({ models: statuses, timestamp: Date.now() }));
        return;
    }
    req.url = req.url.replace(/^.*\/dummy_path_padding/, '');
    // Strip binary patch padding (from LS hostname replacement)
    req.url = req.url.replace(/\/v1internal\/x{7}/, '');
    // P0-4: Enforce maximum request body size to prevent memory exhaustion DoS
    const MAX_BODY_SIZE = 10 * 1024 * 1024; // 10 MB
    let bodyLength = 0;
    let bodyRejected = false;
    const bodyChunks = [];
    req.on('data', (chunk) => {
        bodyLength += chunk.length;
        if (bodyLength > MAX_BODY_SIZE) {
            if (!bodyRejected) {
                bodyRejected = true;
                electron_log_1.default.warn(`[Proxy] Request body exceeds ${MAX_BODY_SIZE / 1024 / 1024}MB limit (${req.method} ${req.url})`);
                req.destroy();
                if (!res.headersSent) {
                    res.writeHead(413, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ error: { message: `Request body too large. Maximum: ${MAX_BODY_SIZE / 1024 / 1024}MB` } }));
                }
            }
            return;
        }
        bodyChunks.push(chunk);
    });
    req.on('end', async () => {
        if (bodyRejected)
            return;
        const fullBody = Buffer.concat(bodyChunks);
        const bodyStr = fullBody.toString('utf-8');
        electron_log_1.default.info(`[Proxy] Request: ${req.method} ${req.url}`);
        // 0. Intercept GetAvailableModels (redirected from Electron webRequest)
        if (req.url.startsWith('/GetAvailableModels')) {
            const gavParsed = new URL(req.url, 'http://127.0.0.1');
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
        if (req.url.includes('/v1internal:fetchAvailableModels')) {
            electron_log_1.default.info('[Proxy] Intercepting fetchAvailableModels request');
            const targetHost = 'daily-cloudcode-pa.googleapis.com';
            const targetUrl = `https://${targetHost}`;
            let parsedUrl;
            try {
                const realIp = await (0, dnsResolver_1.resolveGoogleIp)(targetHost);
                parsedUrl = new URL(req.url, targetUrl);
                parsedUrl.hostname = realIp;
            }
            catch (e) {
                electron_log_1.default.error(`[Proxy] Could not resolve upstream IP for ${targetHost}:`, e);
                if (safeWriteHead(res, 500, { 'Content-Type': 'application/json' })) {
                    safeEnd(res, JSON.stringify({ error: { message: 'DNS resolution failed for ' + targetHost } }));
                }
                return;
            }
            const fwdHeaders = {
                ...req.headers,
            };
            fwdHeaders['host'] = targetHost;
            delete fwdHeaders['connection'];
            delete fwdHeaders['keep-alive'];
            delete fwdHeaders['accept-encoding'];
            const fwdOptions = {
                method: req.method,
                headers: fwdHeaders,
                servername: targetHost,
            };
            const googleReq = https.request(parsedUrl, fwdOptions, (googleRes) => {
                let googleResErrored = false;
                googleRes.on('error', (err) => {
                    googleResErrored = true;
                    electron_log_1.default.error('[Proxy] fetchAvailableModels upstream error:', err.message);
                });
                // P0-5: Timeout for fetchAvailableModels forward request (30s)
                googleReq.setTimeout(30000, () => {
                    electron_log_1.default.error('[Proxy] fetchAvailableModels forward request timed out');
                    googleReq.destroy();
                    if (!res.headersSent && !res.writableEnded) {
                        const customModels = (0, modelLoader_1.loadCustomModels)();
                        const mappedCustom = {};
                        customModels.forEach((m) => {
                            const slug = (0, idGenerator_1.toSlug)(m);
                            const pid = (0, idGenerator_1.generateModelPlaceholderId)(m);
                            mappedCustom[slug] = {
                                displayName: m.displayName,
                                maxTokens: 1048576,
                                maxOutputTokens: 4096,
                                model: pid,
                                planModel: pid,
                                requestedModel: pid,
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
                        electron_log_1.default.debug('[Proxy] fetchAvailableModels: skipping end handler (response terminated)');
                        return;
                    }
                    try {
                        electron_log_1.default.info(`[Proxy] fetchAvailableModels response status: ${googleRes.statusCode}, body length: ${googleBody.length}`);
                        const googleJson = JSON.parse(googleBody);
                        const customModels = (0, modelLoader_1.loadCustomModels)();
                        electron_log_1.default.info(`[Proxy] Loaded custom models count: ${customModels.length}`);
                        const mergeModels = (target) => {
                            if (Array.isArray(target)) {
                                const mapped = customModels.map((m) => {
                                    const cap = (0, modelUtils_1.detectModelCapabilities)(m, true);
                                    const pid = (0, idGenerator_1.generateModelPlaceholderId)(m);
                                    return {
                                        name: 'models/' + pid,
                                        model: pid,
                                        planModel: pid,
                                        requestedModel: pid,
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
                            }
                            else if (target && typeof target === 'object') {
                                const result = { ...target };
                                customModels.forEach((m) => {
                                    const slug = (0, idGenerator_1.toSlug)(m);
                                    const cap = (0, modelUtils_1.detectModelCapabilities)(m, true);
                                    const pid = (0, idGenerator_1.generateModelPlaceholderId)(m);
                                    const entry = {
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
                                        model: pid,
                                        planModel: pid,
                                        requestedModel: pid,
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
                                    }
                                    else {
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
                                    result[slug] = entry;
                                    m._slug = slug;
                                    electron_log_1.default.info(`[Proxy] Custom model "${m.displayName}" => slug: ${slug} => model: ${(0, idGenerator_1.generateModelPlaceholderId)(m)} => thinking: ${cap.isThinking} => images: ${cap.supportsImages}`);
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
                            const modelsMap = {};
                            customModels.forEach((m) => {
                                const slug = (0, idGenerator_1.toSlug)(m);
                                modelsMap[slug] = {
                                    displayName: m.displayName,
                                    recommended: true,
                                    maxTokens: 1048576,
                                    maxOutputTokens: 4096,
                                    tokenizerType: 'LLAMA_WITH_SPECIAL',
                                    model: (0, idGenerator_1.generateModelPlaceholderId)(m),
                                    apiProvider: 'API_PROVIDER_GOOGLE_GEMINI',
                                    modelProvider: 'MODEL_PROVIDER_GOOGLE',
                                };
                                m._slug = slug;
                            });
                            googleJson.models = modelsMap;
                        }
                        // Inject custom model slugs into agentModelSorts
                        const customSlugs = customModels.map((m) => m._slug).filter(Boolean);
                        if (customSlugs.length > 0) {
                            if (googleJson.agentModelSorts && Array.isArray(googleJson.agentModelSorts)) {
                                googleJson.agentModelSorts.forEach((sort) => {
                                    if (sort.groups && Array.isArray(sort.groups)) {
                                        sort.groups.forEach((group) => {
                                            if (group.modelIds && Array.isArray(group.modelIds)) {
                                                customSlugs.forEach((slug) => {
                                                    if (!group.modelIds.includes(slug)) {
                                                        group.modelIds.push(slug);
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
                            electron_log_1.default.warn(`[Proxy] fetchAvailableModels: stripping upstream error from response (status: ${googleRes.statusCode})`);
                            delete googleJson.error;
                        }
                        safeWriteHead(res, 200, { 'Content-Type': 'application/json' });
                        safeEnd(res, JSON.stringify(googleJson));
                    }
                    catch (err) {
                        electron_log_1.default.error('[Proxy] Parsing fetchAvailableModels failed, returning custom models:', err);
                        if (res.headersSent || res.writableEnded)
                            return;
                        const customModels = (0, modelLoader_1.loadCustomModels)();
                        const mappedCustom = {};
                        customModels.forEach((m) => {
                            const slug = (0, idGenerator_1.toSlug)(m);
                            const pid = (0, idGenerator_1.generateModelPlaceholderId)(m);
                            mappedCustom[slug] = {
                                displayName: m.displayName,
                                maxTokens: 1048576,
                                maxOutputTokens: 4096,
                                model: pid,
                                planModel: pid,
                                requestedModel: pid,
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
                electron_log_1.default.error('[Proxy] Forwarding fetchAvailableModels failed:', err);
                if (!res.headersSent && !res.writableEnded) {
                    const customModels = (0, modelLoader_1.loadCustomModels)();
                    const mappedCustom = {};
                    customModels.forEach((m) => {
                        const slug = (0, idGenerator_1.toSlug)(m);
                        const pid = (0, idGenerator_1.generateModelPlaceholderId)(m);
                        mappedCustom[slug] = {
                            displayName: m.displayName,
                            maxTokens: 1048576,
                            maxOutputTokens: 4096,
                            model: pid,
                            planModel: pid,
                            requestedModel: pid,
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
        if (req.method === 'GET' && (req.url.endsWith('/models') || req.url.includes('/models?'))) {
            electron_log_1.default.info('[Proxy] Intercepting models list request');
            const targetHost = 'generativelanguage.googleapis.com';
            const targetUrl = `https://${targetHost}`;
            let parsedUrl;
            try {
                const realIp = await (0, dnsResolver_1.resolveGoogleIp)(targetHost);
                parsedUrl = new URL(req.url, targetUrl);
                parsedUrl.hostname = realIp;
            }
            catch (e) {
                electron_log_1.default.error(`[Proxy] Could not resolve upstream IP for ${targetHost}:`, e);
                if (safeWriteHead(res, 500, { 'Content-Type': 'application/json' })) {
                    safeEnd(res, JSON.stringify({ error: { message: 'DNS resolution failed for ' + targetHost } }));
                }
                return;
            }
            const mdlHeaders = {
                ...req.headers,
            };
            mdlHeaders['host'] = targetHost;
            delete mdlHeaders['connection'];
            delete mdlHeaders['accept-encoding'];
            const mdlOptions = {
                method: 'GET',
                headers: mdlHeaders,
                servername: targetHost,
            };
            const googleReq = https.request(parsedUrl, mdlOptions, (googleRes) => {
                let googleResErrored = false;
                googleRes.on('error', (err) => {
                    googleResErrored = true;
                    electron_log_1.default.error('[Proxy] Models list upstream error:', err.message);
                });
                // P0-5: Timeout for models list forward request (30s)
                googleReq.setTimeout(30000, () => {
                    electron_log_1.default.error('[Proxy] Models list forward request timed out');
                    googleReq.destroy();
                    if (!res.headersSent && !res.writableEnded) {
                        const customModels = (0, modelLoader_1.loadCustomModels)();
                        safeWriteHead(res, 200, { 'Content-Type': 'application/json' });
                        safeEnd(res, JSON.stringify({
                            models: customModels.map((m) => ({
                                name: m.name,
                                displayName: m.displayName,
                                description: m.description,
                                supportedGenerationMethods: ['generateContent'],
                            })),
                        }));
                    }
                });
                let googleBody = '';
                googleRes.on('data', (chunk) => (googleBody += chunk));
                googleRes.on('end', () => {
                    // Guard: timeout or upstream error may have already terminated the response
                    if (googleResErrored || res.headersSent || res.writableEnded) {
                        electron_log_1.default.debug('[Proxy] Models list: skipping end handler (response terminated)');
                        return;
                    }
                    try {
                        const googleJson = JSON.parse(googleBody);
                        const customModels = (0, modelLoader_1.loadCustomModels)();
                        const mappedCustom = customModels.map((m) => ({
                            name: 'models/' + (0, idGenerator_1.generateModelPlaceholderId)(m),
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
                        }
                        else {
                            googleJson.models = mappedCustom;
                        }
                        safeWriteHead(res, 200, { 'Content-Type': 'application/json' });
                        safeEnd(res, JSON.stringify(googleJson));
                    }
                    catch (err) {
                        electron_log_1.default.error('[Proxy] Google list models failed, returning custom models list only:', err);
                        if (res.headersSent || res.writableEnded)
                            return;
                        const customModels = (0, modelLoader_1.loadCustomModels)();
                        const mappedCustom = customModels.map((m) => ({
                            name: 'models/' + (0, idGenerator_1.generateModelPlaceholderId)(m),
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
                electron_log_1.default.error('[Proxy] Google models list request error:', err);
                if (!res.headersSent && !res.writableEnded) {
                    const customModels = (0, modelLoader_1.loadCustomModels)();
                    safeWriteHead(res, 200, { 'Content-Type': 'application/json' });
                    safeEnd(res, JSON.stringify({
                        models: customModels.map((m) => ({
                            name: m.name,
                            displayName: m.displayName,
                            description: m.description,
                            supportedGenerationMethods: ['generateContent'],
                        })),
                    }));
                }
            });
            googleReq.end();
            return;
        }
        // 3. Intercept Cloud Code generation stream or non-stream requests
        const isCloudCodeStream = req.url.includes('/v1internal:streamGenerateContent') || req.url.includes('/v1internal:generateContent');
        if (req.method === 'POST' && isCloudCodeStream) {
            try {
                const reqJson = JSON.parse(bodyStr);
                const targetReq = (reqJson.request || reqJson);
                const candidateNames = [
                    reqJson.model,
                    reqJson.requestedModel,
                    reqJson.planModel,
                    reqJson.requested_model,
                    reqJson.plan_model,
                    reqJson.modelId,
                    reqJson.model_id,
                    targetReq.model,
                    targetReq.requestedModel,
                    targetReq.planModel,
                    targetReq.requested_model,
                    targetReq.plan_model,
                    targetReq.modelId,
                    targetReq.model_id,
                ].filter((x) => typeof x === 'string' && Boolean(x));
                electron_log_1.default.info(`[Proxy] Cloud Code generation request candidates: ${candidateNames.join(', ')}, url: ${req.url}, bodyKeys: ${Object.keys(reqJson).join(',')}`);
                if (candidateNames.length > 0) {
                    const customModels = (0, modelLoader_1.loadCustomModels)();
                    const matchedCustomModel = customModels.find((m) => {
                        const enumName = (0, idGenerator_1.generateModelPlaceholderId)(m);
                        return candidateNames.some((cn) => m.name === cn ||
                            (0, idGenerator_1.toSlug)(m) === cn ||
                            enumName === cn ||
                            `models/${enumName}` === cn ||
                            cn.endsWith(enumName));
                    });
                    if (matchedCustomModel) {
                        electron_log_1.default.info(`[Proxy] Intercepting Cloud Code generation for custom model: ${matchedCustomModel.displayName}`);
                        const isStream = req.url.includes('streamGenerateContent') || req.url.includes('alt=sse');
                        const actualGeminiBody = (reqJson.request || reqJson);
                        // Resolve fileData URIs then route to translator
                        resolveFileData(actualGeminiBody, req.headers).then(() => {
                            handleCustomModelRequest(res, matchedCustomModel, actualGeminiBody, isStream);
                        });
                        return;
                    }
                }
            }
            catch (err) {
                electron_log_1.default.error('[Proxy] Failed to parse Cloud Code stream body:', err);
            }
        }
        // 4. Intercept standard generateContent / streamGenerateContent request
        const generateMatch = req.url.match(/\/(?:v1|v1beta)\/(models\/[^:]+):generateContent/);
        const streamMatch = req.url.match(/\/(?:v1|v1beta)\/(models\/[^:]+):streamGenerateContent/);
        const isGenerate = !!generateMatch;
        const isStandardStream = !!streamMatch;
        if (req.method === 'POST' && (isGenerate || isStandardStream)) {
            const matchedModelName = isGenerate ? generateMatch[1] : streamMatch[1];
            const customModels = (0, modelLoader_1.loadCustomModels)();
            const matchedCustomModel = customModels.find((m) => {
                const enumName = (0, idGenerator_1.generateModelPlaceholderId)(m);
                return (m.name === matchedModelName ||
                    (0, idGenerator_1.toSlug)(m) === matchedModelName ||
                    enumName === matchedModelName ||
                    'models/' + enumName === matchedModelName);
            });
            if (matchedCustomModel) {
                try {
                    const geminiBody = JSON.parse(bodyStr);
                    resolveFileData(geminiBody, req.headers).then(() => {
                        handleCustomModelRequest(res, matchedCustomModel, geminiBody, isStandardStream);
                    });
                    return;
                }
                catch (e) {
                    electron_log_1.default.error('[Proxy] JSON parse error in request body:', e);
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
function startProxy() {
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
            const portCandidates = [defaultPort];
            if (defaultPort === 50999) {
                // Only add fallbacks if the user did not override the port via env
                portCandidates.push(...constants_1.FALLBACK_PROXY_PORTS);
            }
            portCandidates.push(0); // 0 = OS-assigned dynamic port (last resort)
            let attemptIdx = 0;
            const tryListen = (port, host) => {
                server.listen(port, host, () => {
                    proxyPort = server.address().port;
                    const isFallback = port !== defaultPort && port !== 0;
                    const isDynamic = port === 0;
                    if (isFallback) {
                        electron_log_1.default.warn(`[Proxy] Default port ${defaultPort} unavailable. Using fallback port ${proxyPort}.`);
                        electron_log_1.default.warn(`[Proxy] Set AG_PROXY_PORT=${proxyPort} in your environment to silence this warning.`);
                    }
                    else if (isDynamic) {
                        electron_log_1.default.warn(`[Proxy] All configured ports in use. Using OS-assigned dynamic port ${proxyPort}.`);
                    }
                    else {
                        electron_log_1.default.info(`[Proxy] Server listening on http://${host}:${proxyPort}`);
                    }
                    // Persist the active port so other processes (ag-doctor-ui, scripts)
                    // can discover which port the proxy is actually bound to.
                    try {
                        const home = process.env.HOME || process.env.USERPROFILE || os.homedir();
                        const portFile = path.join(home, constants_1.ACTIVE_PORT_FILE);
                        fs.mkdirSync(path.dirname(portFile), { recursive: true });
                        fs.writeFileSync(portFile, String(proxyPort), 'utf-8');
                        electron_log_1.default.debug(`[Proxy] Active port persisted to ${portFile}`);
                    }
                    catch (err) {
                        electron_log_1.default.warn('[Proxy] Could not persist active port:', err.message);
                    }
                    // Execute cleanup initialization after the server is already listening
                    // so that failures here don't prevent the port from binding.
                    try {
                        (0, shared_1.startCleanupInterval)();
                    }
                    catch (err) {
                        electron_log_1.default.error('[Proxy] Failed to start cleanup interval:', err);
                    }
                    resolve(proxyPort);
                });
            };
            server.on('error', (err) => {
                // Log full error details for diagnostics on new machines.
                electron_log_1.default.error(`[Proxy] Server error: code=${err.code} message=${err.message} syscall=${err.syscall || ''} address=${err.address || ''} port=${err.port || ''}`);
                if (err.code === 'EADDRINUSE' && attemptIdx + 1 < portCandidates.length) {
                    const triedPort = portCandidates[attemptIdx];
                    const nextPort = portCandidates[attemptIdx + 1];
                    electron_log_1.default.warn(`[Proxy] Port ${triedPort} is already in use. Trying ${nextPort === 0 ? 'OS-assigned dynamic port' : 'port ' + nextPort}...`);
                    attemptIdx += 1;
                    tryListen(nextPort, primaryHost);
                }
                else if (err.code === 'EACCES') {
                    // P2: Surface permission errors clearly instead of silently failing.
                    electron_log_1.default.error(`[Proxy] Permission denied binding to ${primaryHost}:${primaryPort}. Try a different port (AG_PROXY_PORT) or run with sufficient privileges.`);
                    reject(err);
                }
                else {
                    electron_log_1.default.error('[Proxy] Startup failed:', err);
                    reject(err);
                }
            });
            primaryPort = portCandidates[0];
            tryListen(primaryPort, primaryHost);
        }
        catch (err) {
            electron_log_1.default.error('[Proxy] Unexpected error during startProxy:', err);
            reject(err);
        }
    });
}
function stopProxy() {
    return new Promise((resolve) => {
        // P1-9: Stop cleanup interval to prevent orphaned timers
        (0, shared_1.stopCleanupInterval)();
        const finish = () => {
            // Phase 3: close per-host https/http agent pools so file descriptors
            // are released on graceful shutdown (mirrors undici.Agent.close()).
            (0, agentPool_1.disposeAll)()
                .then(() => resolve())
                .catch((err) => {
                electron_log_1.default.warn('[Proxy] Agent pool dispose error (non-fatal):', err);
                resolve();
            });
        };
        if (server) {
            // Forcefully close idle connections to release sockets immediately
            if (typeof server.closeIdleConnections === 'function') {
                server.closeIdleConnections();
            }
            server.close(() => {
                electron_log_1.default.info('[Proxy] Server stopped');
                server = null;
                finish();
            });
        }
        else {
            finish();
        }
    });
}
function getProxyPort() {
    return proxyPort;
}
//# sourceMappingURL=proxy.js.map