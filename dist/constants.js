"use strict";
/**
 * Constants for the proxy module.
 * Centralizes magic numbers and configuration values to improve maintainability.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.DETAILED_PROVIDER_PRESETS = exports.PROVIDER_DEFAULT_URLS = exports.PROVIDERS_REQUIRING_API_KEY = exports.OPENAI_COMPATIBLE_PROVIDERS = exports.ALL_PROVIDERS = exports.PROVIDERS = exports.CONTENT_TYPES = exports.GOOGLE_HOSTS = exports.HTTP_STATUS = exports.PUBLIC_DNS_SERVERS = exports.PLACEHOLDER_ID_RANGE = exports.PLACEHOLDER_ID_BASE = exports.DEFAULT_TOP_K = exports.DEFAULT_TOP_P = exports.DEFAULT_TEMPERATURE = exports.CUSTOM_MODEL_MAX_OUTPUT_TOKENS = exports.CUSTOM_MODEL_MAX_TOKENS = exports.CACHE_REFRESH_BACKOFF_MS = exports.CACHE_REFRESH_MAX_FAILURES = exports.MAX_MAX_RETRIES = exports.MIN_MAX_RETRIES = exports.DEFAULT_MAX_RETRIES = exports.RETRY_BACKOFF_JITTER_FACTOR = exports.RETRY_BACKOFF_MULTIPLIER = exports.SERVER_ERROR_RETRY_BASE_DELAY_MS = exports.RATE_LIMIT_RETRY_BASE_DELAY_MS = exports.NON_STREAM_RETRY_BASE_DELAY_MS = exports.STREAM_RETRY_BASE_DELAY_MS = exports.DEFAULT_MODEL_REQUEST_TIMEOUT_MS = exports.STREAM_IDLE_TIMEOUT_MS = exports.FILE_DOWNLOAD_TIMEOUT_MS = exports.GOOGLE_FORWARD_TIMEOUT_MS = exports.GOOGLE_PROXY_TIMEOUT_MS = exports.MAX_REQUEST_BODY_SIZE = exports.ACTIVE_PORT_FILE = exports.STUB_PORT_DEFAULT = exports.FALLBACK_PROXY_PORTS = exports.DEFAULT_PROXY_PORT = exports.LS_CERT_FINGERPRINT = exports.LS_LOG_FILE_NAME = exports.DYNAMIC_PORT = exports.WINDOW_ORIGIN = void 0;
// ─── App Constants (used by main.ts, languageServer.ts, paths.ts) ─────────
/** Origin used by the main BrowserWindow. */
exports.WINDOW_ORIGIN = 'https://127.0.0.1';
/** Pass 0 to the LS so the OS assigns an available port automatically. */
exports.DYNAMIC_PORT = 0;
/** Log file name for the language server. */
exports.LS_LOG_FILE_NAME = 'language_server.log';
/** SHA-256 fingerprint of the bundled language server certificate. */
exports.LS_CERT_FINGERPRINT = 'sha256/sTZpQemOWEytaZqa7P/y/dNXbHMdOAzMvzHEhUwHZXw=';
// ─── Network ───────────────────────────────────────────────────────────────
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
exports.DEFAULT_PROXY_PORT = 50999;
/** Fallback ports tried in order when DEFAULT_PROXY_PORT is in use. */
exports.FALLBACK_PROXY_PORTS = [51000, 51001, 51002, 51003, 51004, 51005, 51006, 51007, 51008, 51009, 51010];
/**
 * Default port for the ag-doctor-ui emergency proxy stub.
 * Kept separate from DEFAULT_PROXY_PORT to prevent conflicts.
 */
exports.STUB_PORT_DEFAULT = 51999;
/** Path (relative to home) where the active proxy port is persisted for IPC. */
exports.ACTIVE_PORT_FILE = '.gemini/antigravity/active_port';
/** Maximum request body size accepted by the proxy (10 MB). Prevents memory exhaustion DoS. */
exports.MAX_REQUEST_BODY_SIZE = 10 * 1024 * 1024;
/** Timeout for Google proxy requests (60 seconds). */
exports.GOOGLE_PROXY_TIMEOUT_MS = 60000;
/** Timeout for forwarding requests to upstream Google APIs (30 seconds). */
exports.GOOGLE_FORWARD_TIMEOUT_MS = 30000;
/** Timeout for downloading file content from external URIs (30 seconds). */
exports.FILE_DOWNLOAD_TIMEOUT_MS = 30000;
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
exports.STREAM_IDLE_TIMEOUT_MS = 60000;
/**
 * Default request timeout for custom model requests.
 *
 * Lowered from 120_000 to 30_000 to bound the worst-case blocking time
 * of an upstream connection (3 attempts × 30s = 90s max). Combined with
 * DEFAULT_MAX_RETRIES = 1, a fully-failing model holds the proxy open
 * for at most 60s before giving up, freeing connections for the rest of
 * the dropdown models.
 */
exports.DEFAULT_MODEL_REQUEST_TIMEOUT_MS = 30000;
/** Default retry delay for streaming errors (1 second). */
exports.STREAM_RETRY_BASE_DELAY_MS = 1000;
/** Default retry delay for non-streaming errors (1 second). */
exports.NON_STREAM_RETRY_BASE_DELAY_MS = 1000;
/** Base delay for 429 rate-limit retries (2 seconds). */
exports.RATE_LIMIT_RETRY_BASE_DELAY_MS = 2000;
/** Base delay for 5xx server error retries (1 second). */
exports.SERVER_ERROR_RETRY_BASE_DELAY_MS = 1000;
/**
 * Exponential backoff multiplier (AWS-style decorrelated jitter).
 *
 * The delay for attempt N is roughly:
 *     min(initialDelay * MULTIPLIER^N, maxDelay) * (1 +/- JITTER)
 *
 * 2x is the AWS-recommended default — fast enough to recover from transient
 * errors, gentle enough to avoid pile-up.
 */
exports.RETRY_BACKOFF_MULTIPLIER = 2;
/**
 * Jitter factor in [0, 1]. With 0.1, each delay is randomly scaled within
 * +/-10% of its computed value, preventing retry-wave synchronization when
 * many concurrent requests hit the same upstream at the same time.
 *
 * Inspired by `vscode-unify-chat-provider`'s DEFAULT_CHAT_RETRY_CONFIG.
 */
exports.RETRY_BACKOFF_JITTER_FACTOR = 0.1;
// ─── Retry Configuration ──────────────────────────────────────────────────
/**
 * Default maximum number of retries per model.
 *
 * Lowered from 3 to 1 to prevent retry storms: a stuck upstream used to
 * block the proxy for up to ~360s (3 × 120s) per model, which cascaded
 * across 8+ custom models and starved the rest of the dropdown.
 * With 1 retry, a fully-failing model gives up in ≤ 60s (2 × 30s).
 */
exports.DEFAULT_MAX_RETRIES = 1;
/** Minimum allowed retry count. */
exports.MIN_MAX_RETRIES = 0;
/** Maximum allowed retry count. */
exports.MAX_MAX_RETRIES = 5;
// ─── Circuit Breaker ──────────────────────────────────────────────────────
/** Maximum consecutive cache refresh failures before backing off. */
exports.CACHE_REFRESH_MAX_FAILURES = 3;
/** Backoff duration after circuit breaker trips (5 minutes). */
exports.CACHE_REFRESH_BACKOFF_MS = 5 * 60 * 1000;
// ─── Model Capabilities ────────────────────────────────────────────────────
/** Maximum input tokens for custom models. */
exports.CUSTOM_MODEL_MAX_TOKENS = 1048576;
/** Maximum output tokens for custom models. */
exports.CUSTOM_MODEL_MAX_OUTPUT_TOKENS = 4096;
/** Default sampling temperature for non-thinking models. */
exports.DEFAULT_TEMPERATURE = 0.7;
/** Default top-P sampling parameter. */
exports.DEFAULT_TOP_P = 0.9;
/** Default top-K sampling parameter. */
exports.DEFAULT_TOP_K = 40;
// ─── Model Placeholder ID Generation ──────────────────────────────────────
/** Base number for placeholder IDs (e.g., MODEL_PLACEHOLDER_M400). */
exports.PLACEHOLDER_ID_BASE = 400;
/** Range for placeholder IDs (e.g., 200 = IDs from 400 to 599). */
exports.PLACEHOLDER_ID_RANGE = 200;
// ─── DNS Resolution ───────────────────────────────────────────────────────
/** Public DNS servers used to bypass local DNS poisoning. */
exports.PUBLIC_DNS_SERVERS = ['8.8.8.8', '1.1.1.1', '8.8.4.4'];
// ─── HTTP Status Codes ────────────────────────────────────────────────────
exports.HTTP_STATUS = {
    OK: 200,
    BAD_REQUEST: 400,
    UNAUTHORIZED: 401,
    PAYMENT_REQUIRED: 402,
    FORBIDDEN: 403,
    PAYLOAD_TOO_LARGE: 413,
    TOO_MANY_REQUESTS: 429,
    INTERNAL_SERVER_ERROR: 500,
    BAD_GATEWAY: 502,
    GATEWAY_TIMEOUT: 504,
};
// ─── Google API Hosts ─────────────────────────────────────────────────────
exports.GOOGLE_HOSTS = {
    CLOUD_CODE: 'daily-cloudcode-pa.googleapis.com',
    GENERATIVE_LANGUAGE: 'generativelanguage.googleapis.com',
};
// ─── Content Types ────────────────────────────────────────────────────────
exports.CONTENT_TYPES = {
    JSON: 'application/json',
    EVENT_STREAM: 'text/event-stream',
    GRPC_WEB_PROTO: 'application/grpc-web+proto',
};
// ─── Provider Names ───────────────────────────────────────────────────────
// Single source of truth for all supported providers.
exports.PROVIDERS = {
    OPENAI: 'openai',
    OLLAMA: 'ollama',
    OPENROUTER: 'openrouter',
    CUSTOM: 'custom',
    GROQ: 'groq',
    MISTRAL: 'mistral',
    CEREBRAS: 'cerebras',
    NVIDIA: 'nvidia',
    OPENCODE: 'opencode',
    CODESTRAL: 'codestral',
    // Anthropic-compatible transport
    ANTHROPIC: 'anthropic',
    DEEPSEEK: 'deepseek',
    KIMI: 'kimi',
    FIREWORKS: 'fireworks',
    LMSTUDIO: 'lmstudio',
    LLAMACPP: 'llamacpp',
    WAFER: 'wafer',
    ZAI: 'zai',
    // Native
    GOOGLE: 'google',
};
/** All provider names as an array, useful for validation. */
exports.ALL_PROVIDERS = Object.values(exports.PROVIDERS);
/** Providers that use OpenAI-compatible API format (chat/completions). */
exports.OPENAI_COMPATIBLE_PROVIDERS = [
    exports.PROVIDERS.OPENAI,
    exports.PROVIDERS.CUSTOM,
    exports.PROVIDERS.OPENROUTER,
];
/** Providers that require an API key for authentication. */
exports.PROVIDERS_REQUIRING_API_KEY = [
    exports.PROVIDERS.OPENAI,
    exports.PROVIDERS.ANTHROPIC,
    exports.PROVIDERS.OPENROUTER,
    exports.PROVIDERS.GOOGLE,
    exports.PROVIDERS.DEEPSEEK,
    exports.PROVIDERS.GROQ,
    exports.PROVIDERS.MISTRAL,
    exports.PROVIDERS.CEREBRAS,
    exports.PROVIDERS.KIMI,
    exports.PROVIDERS.FIREWORKS,
    exports.PROVIDERS.NVIDIA,
    exports.PROVIDERS.OPENCODE,
    exports.PROVIDERS.CODESTRAL,
    exports.PROVIDERS.WAFER,
    exports.PROVIDERS.ZAI,
];
/** Default API URLs per provider. Override per-model via apiUrl in custom_models.json. */
exports.PROVIDER_DEFAULT_URLS = {
    [exports.PROVIDERS.OPENAI]: 'https://api.openai.com/v1/chat/completions',
    [exports.PROVIDERS.ANTHROPIC]: 'https://api.anthropic.com/v1/messages',
    [exports.PROVIDERS.OPENROUTER]: 'https://openrouter.ai/api/v1/chat/completions',
    [exports.PROVIDERS.OLLAMA]: 'http://localhost:11434/v1/chat/completions',
    [exports.PROVIDERS.GOOGLE]: 'https://generativelanguage.googleapis.com/v1beta/models/',
    [exports.PROVIDERS.CUSTOM]: '',
    [exports.PROVIDERS.DEEPSEEK]: 'https://api.deepseek.com/v1',
    [exports.PROVIDERS.GROQ]: 'https://api.groq.com/openai/v1',
    [exports.PROVIDERS.MISTRAL]: 'https://api.mistral.ai/v1',
    [exports.PROVIDERS.CEREBRAS]: 'https://api.cerebras.ai/v1',
    [exports.PROVIDERS.KIMI]: 'https://api.moonshot.ai/v1',
    [exports.PROVIDERS.FIREWORKS]: 'https://api.fireworks.ai/inference/v1',
    [exports.PROVIDERS.LMSTUDIO]: 'http://localhost:1234/v1',
    [exports.PROVIDERS.LLAMACPP]: 'http://localhost:8080/v1',
    [exports.PROVIDERS.NVIDIA]: 'https://integrate.api.nvidia.com/v1',
    [exports.PROVIDERS.OPENCODE]: '',
    [exports.PROVIDERS.CODESTRAL]: 'https://codestral.mistral.ai/v1',
    [exports.PROVIDERS.WAFER]: '',
    [exports.PROVIDERS.ZAI]: '',
};
exports.DETAILED_PROVIDER_PRESETS = [
    {
        id: exports.PROVIDERS.OPENAI,
        label: 'OpenAI',
        defaultApiUrl: 'https://api.openai.com/v1',
        suggestedModels: [
            { id: 'gpt-4o', displayName: 'GPT-4o (Omni)' },
            { id: 'gpt-4o-mini', displayName: 'GPT-4o Mini' },
            { id: 'o1', displayName: 'OpenAI o1 Reasoning' },
            { id: 'o3-mini', displayName: 'OpenAI o3-mini' },
        ],
    },
    {
        id: exports.PROVIDERS.DEEPSEEK,
        label: 'DeepSeek (Official)',
        defaultApiUrl: 'https://api.deepseek.com/v1',
        suggestedModels: [
            { id: 'deepseek-chat', displayName: 'DeepSeek-V3 (Chat)' },
            { id: 'deepseek-reasoner', displayName: 'DeepSeek-R1 (Reasoner)' },
        ],
    },
    {
        id: exports.PROVIDERS.OPENROUTER,
        label: 'OpenRouter',
        defaultApiUrl: 'https://openrouter.ai/api/v1',
        suggestedModels: [
            { id: 'deepseek/deepseek-r1', displayName: 'DeepSeek R1 (OpenRouter)' },
            { id: 'anthropic/claude-3.5-sonnet', displayName: 'Claude 3.5 Sonnet' },
            { id: 'meta-llama/llama-3.3-70b-instruct', displayName: 'Llama 3.3 70B' },
            { id: 'qwen/qwen-2.5-coder-32b-instruct', displayName: 'Qwen 2.5 Coder 32B' },
        ],
    },
    {
        id: exports.PROVIDERS.GROQ,
        label: 'Groq (Ultra Fast)',
        defaultApiUrl: 'https://api.groq.com/openai/v1',
        suggestedModels: [
            { id: 'llama-3.3-70b-versatile', displayName: 'Llama 3.3 70B Versatile' },
            { id: 'mixtral-8x7b-32768', displayName: 'Mixtral 8x7B (32k)' },
            { id: 'deepseek-r1-distill-llama-70b', displayName: 'DeepSeek R1 Distill 70B' },
        ],
    },
    {
        id: exports.PROVIDERS.OLLAMA,
        label: 'Ollama (Local)',
        defaultApiUrl: 'http://localhost:11434/v1',
        suggestedModels: [
            { id: 'llama3', displayName: 'Llama 3 Local' },
            { id: 'deepseek-r1:8b', displayName: 'DeepSeek R1 8B Local' },
            { id: 'qwen2.5-coder', displayName: 'Qwen 2.5 Coder Local' },
        ],
    },
    {
        id: exports.PROVIDERS.ANTHROPIC,
        label: 'Anthropic Claude',
        defaultApiUrl: 'https://api.anthropic.com/v1',
        suggestedModels: [
            { id: 'claude-3-5-sonnet-latest', displayName: 'Claude 3.5 Sonnet' },
            { id: 'claude-3-5-haiku-latest', displayName: 'Claude 3.5 Haiku' },
        ],
    },
    {
        id: exports.PROVIDERS.MISTRAL,
        label: 'Mistral AI',
        defaultApiUrl: 'https://api.mistral.ai/v1',
        suggestedModels: [
            { id: 'mistral-large-latest', displayName: 'Mistral Large' },
            { id: 'codestral-latest', displayName: 'Codestral (Code)' },
        ],
    },
    {
        id: exports.PROVIDERS.KIMI,
        label: 'Moonshot (Kimi)',
        defaultApiUrl: 'https://api.moonshot.ai/v1',
        suggestedModels: [
            { id: 'moonshot-v1-8k', displayName: 'Kimi Moonshot 8k' },
            { id: 'moonshot-v1-32k', displayName: 'Kimi Moonshot 32k' },
        ],
    },
];
//# sourceMappingURL=constants.js.map