/**
 * Constants for the proxy module.
 * Centralizes magic numbers and configuration values to improve maintainability.
 */
/** Origin used by the main BrowserWindow. */
export declare const WINDOW_ORIGIN = "https://127.0.0.1";
/** Pass 0 to the LS so the OS assigns an available port automatically. */
export declare const DYNAMIC_PORT = 0;
/** Log file name for the language server. */
export declare const LS_LOG_FILE_NAME = "language_server.log";
/** SHA-256 fingerprint of the bundled language server certificate. */
export declare const LS_CERT_FINGERPRINT = "sha256/sTZpQemOWEytaZqa7P/y/dNXbHMdOAzMvzHEhUwHZXw=";
/**
 * Default port for the local proxy server.
 *
 * IMPORTANT: This port is reserved for the MAIN Antigravity proxy.
 * The ag-doctor-ui emergency stub uses port 51999 (see STUB_PORT_DEFAULT)
 * to avoid conflicts when both run simultaneously.
 *
 * Override via the AG_PROXY_PORT environment variable. If the default is in
 * use, the proxy will try the FALLBACK_PROXY_PORTS in order, then bind to a
 * random dynamic port as a last resort.
 */
export declare const DEFAULT_PROXY_PORT = 50999;
/** Fallback ports tried in order when DEFAULT_PROXY_PORT is in use. */
export declare const FALLBACK_PROXY_PORTS: readonly number[];
/**
 * Default port for the ag-doctor-ui emergency proxy stub.
 * Kept separate from DEFAULT_PROXY_PORT to prevent conflicts.
 */
export declare const STUB_PORT_DEFAULT = 51999;
/** Path (relative to home) where the active proxy port is persisted for IPC. */
export declare const ACTIVE_PORT_FILE = ".gemini/antigravity/active_port";
/** Maximum request body size accepted by the proxy (10 MB). Prevents memory exhaustion DoS. */
export declare const MAX_REQUEST_BODY_SIZE: number;
/** Timeout for Google proxy requests (60 seconds). */
export declare const GOOGLE_PROXY_TIMEOUT_MS = 60000;
/** Timeout for forwarding requests to upstream Google APIs (30 seconds). */
export declare const GOOGLE_FORWARD_TIMEOUT_MS = 30000;
/** Timeout for downloading file content from external URIs (30 seconds). */
export declare const FILE_DOWNLOAD_TIMEOUT_MS = 30000;
/**
 * Per-chunk idle timeout for streaming upstream responses.
 *
 * If no new SSE chunk arrives within this window, the proxy treats the
 * upstream as stuck and aborts the request. This is fundamentally different
 * from a *total* request timeout (which `request.setTimeout()` enforces):
 * a total timeout kills healthy streams that legitimately take several
 * minutes; the idle timeout only fires when the upstream *stops saying
 * anything* mid-stream.
 *
 * Ported from vscode-unify-chat-provider's `withIdleTimeout` (vendors/...).
 * Default: 60 seconds — generous enough for slow reasoning models, short
 * enough that a stuck upstream doesn't tie up the proxy indefinitely.
 */
export declare const STREAM_IDLE_TIMEOUT_MS = 60000;
/**
 * Default request timeout for custom model requests.
 *
 * Lowered from 120_000 to 30_000 to bound the worst-case blocking time
 * of an upstream connection (3 attempts × 30s = 90s max). Combined with
 * DEFAULT_MAX_RETRIES = 1, a fully-failing model holds the proxy open
 * for at most 60s before giving up, freeing connections for the rest of
 * the dropdown models.
 */
export declare const DEFAULT_MODEL_REQUEST_TIMEOUT_MS = 30000;
/** Default retry delay for streaming errors (1 second). */
export declare const STREAM_RETRY_BASE_DELAY_MS = 1000;
/** Default retry delay for non-streaming errors (1 second). */
export declare const NON_STREAM_RETRY_BASE_DELAY_MS = 1000;
/** Base delay for 429 rate-limit retries (2 seconds). */
export declare const RATE_LIMIT_RETRY_BASE_DELAY_MS = 2000;
/** Base delay for 5xx server error retries (1 second). */
export declare const SERVER_ERROR_RETRY_BASE_DELAY_MS = 1000;
/**
 * Exponential backoff multiplier (AWS-style decorrelated jitter).
 *
 * The delay for attempt N is roughly:
 *     min(initialDelay * MULTIPLIER^N, maxDelay) * (1 +/- JITTER)
 *
 * 2x is the AWS-recommended default — fast enough to recover from transient
 * errors, gentle enough to avoid pile-up.
 */
export declare const RETRY_BACKOFF_MULTIPLIER = 2;
/**
 * Jitter factor in [0, 1]. With 0.1, each delay is randomly scaled within
 * +/-10% of its computed value, preventing retry-wave synchronization when
 * many concurrent requests hit the same upstream at the same time.
 *
 * Inspired by `vscode-unify-chat-provider`'s DEFAULT_CHAT_RETRY_CONFIG.
 */
export declare const RETRY_BACKOFF_JITTER_FACTOR = 0.1;
/**
 * Default maximum number of retries per model.
 *
 * Lowered from 3 to 1 to prevent retry storms: a stuck upstream used to
 * block the proxy for up to ~360s (3 × 120s) per model, which cascaded
 * across 8+ custom models and starved the rest of the dropdown.
 * With 1 retry, a fully-failing model gives up in ≤ 60s (2 × 30s).
 */
export declare const DEFAULT_MAX_RETRIES = 1;
/** Minimum allowed retry count. */
export declare const MIN_MAX_RETRIES = 0;
/** Maximum allowed retry count. */
export declare const MAX_MAX_RETRIES = 5;
/** Maximum consecutive cache refresh failures before backing off. */
export declare const CACHE_REFRESH_MAX_FAILURES = 3;
/** Backoff duration after circuit breaker trips (5 minutes). */
export declare const CACHE_REFRESH_BACKOFF_MS: number;
/** Maximum input tokens for custom models. */
export declare const CUSTOM_MODEL_MAX_TOKENS = 1048576;
/** Maximum output tokens for custom models. */
export declare const CUSTOM_MODEL_MAX_OUTPUT_TOKENS = 4096;
/** Default sampling temperature for non-thinking models. */
export declare const DEFAULT_TEMPERATURE = 0.7;
/** Default top-P sampling parameter. */
export declare const DEFAULT_TOP_P = 0.9;
/** Default top-K sampling parameter. */
export declare const DEFAULT_TOP_K = 40;
/** Base number for placeholder IDs (e.g., MODEL_PLACEHOLDER_M400). */
export declare const PLACEHOLDER_ID_BASE = 400;
/** Range for placeholder IDs (e.g., 200 = IDs from 400 to 599). */
export declare const PLACEHOLDER_ID_RANGE = 200;
/** Public DNS servers used to bypass local DNS poisoning. */
export declare const PUBLIC_DNS_SERVERS: string[];
export declare const HTTP_STATUS: {
    readonly OK: 200;
    readonly BAD_REQUEST: 400;
    readonly UNAUTHORIZED: 401;
    readonly PAYMENT_REQUIRED: 402;
    readonly FORBIDDEN: 403;
    readonly PAYLOAD_TOO_LARGE: 413;
    readonly TOO_MANY_REQUESTS: 429;
    readonly INTERNAL_SERVER_ERROR: 500;
    readonly BAD_GATEWAY: 502;
    readonly GATEWAY_TIMEOUT: 504;
};
export declare const GOOGLE_HOSTS: {
    readonly CLOUD_CODE: "daily-cloudcode-pa.googleapis.com";
    readonly GENERATIVE_LANGUAGE: "generativelanguage.googleapis.com";
};
export declare const CONTENT_TYPES: {
    readonly JSON: "application/json";
    readonly EVENT_STREAM: "text/event-stream";
    readonly GRPC_WEB_PROTO: "application/grpc-web+proto";
};
export declare const PROVIDERS: {
    readonly OPENAI: "openai";
    readonly OLLAMA: "ollama";
    readonly OPENROUTER: "openrouter";
    readonly CUSTOM: "custom";
    readonly GROQ: "groq";
    readonly MISTRAL: "mistral";
    readonly CEREBRAS: "cerebras";
    readonly NVIDIA: "nvidia";
    readonly OPENCODE: "opencode";
    readonly CODESTRAL: "codestral";
    readonly ANTHROPIC: "anthropic";
    readonly DEEPSEEK: "deepseek";
    readonly KIMI: "kimi";
    readonly FIREWORKS: "fireworks";
    readonly LMSTUDIO: "lmstudio";
    readonly LLAMACPP: "llamacpp";
    readonly WAFER: "wafer";
    readonly ZAI: "zai";
    readonly GOOGLE: "google";
};
export type ProviderName = (typeof PROVIDERS)[keyof typeof PROVIDERS];
/** All provider names as an array, useful for validation. */
export declare const ALL_PROVIDERS: readonly ProviderName[];
/** Providers that use OpenAI-compatible API format (chat/completions). */
export declare const OPENAI_COMPATIBLE_PROVIDERS: readonly ["openai", "custom", "openrouter"];
/** Providers that require an API key for authentication. */
export declare const PROVIDERS_REQUIRING_API_KEY: readonly ProviderName[];
/** Default API URLs per provider. Override per-model via apiUrl in custom_models.json. */
export declare const PROVIDER_DEFAULT_URLS: Record<ProviderName, string>;
export interface SuggestedModel {
    id: string;
    displayName: string;
}
export interface DetailedProviderPreset {
    id: ProviderName;
    label: string;
    defaultApiUrl: string;
    suggestedModels: SuggestedModel[];
}
export declare const DETAILED_PROVIDER_PRESETS: DetailedProviderPreset[];
//# sourceMappingURL=constants.d.ts.map