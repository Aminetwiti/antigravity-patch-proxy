"use strict";
/**
 * Constants for the proxy module.
 * Centralizes magic numbers and configuration values to improve maintainability.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.PROVIDER_DEFAULT_URLS = exports.PROVIDERS_REQUIRING_API_KEY = exports.OPENAI_COMPATIBLE_PROVIDERS = exports.ALL_PROVIDERS = exports.PROVIDERS = exports.CONTENT_TYPES = exports.GOOGLE_HOSTS = exports.HTTP_STATUS = exports.PUBLIC_DNS_SERVERS = exports.PLACEHOLDER_ID_RANGE = exports.PLACEHOLDER_ID_BASE = exports.DEFAULT_TOP_K = exports.DEFAULT_TOP_P = exports.DEFAULT_TEMPERATURE = exports.CUSTOM_MODEL_MAX_OUTPUT_TOKENS = exports.CUSTOM_MODEL_MAX_TOKENS = exports.MAX_MAX_RETRIES = exports.MIN_MAX_RETRIES = exports.DEFAULT_MAX_RETRIES = exports.SERVER_ERROR_RETRY_BASE_DELAY_MS = exports.RATE_LIMIT_RETRY_BASE_DELAY_MS = exports.NON_STREAM_RETRY_BASE_DELAY_MS = exports.STREAM_RETRY_BASE_DELAY_MS = exports.DEFAULT_MODEL_REQUEST_TIMEOUT_MS = exports.FILE_DOWNLOAD_TIMEOUT_MS = exports.GOOGLE_FORWARD_TIMEOUT_MS = exports.GOOGLE_PROXY_TIMEOUT_MS = exports.MAX_REQUEST_BODY_SIZE = exports.ACTIVE_PORT_FILE = exports.STUB_PORT_DEFAULT = exports.FALLBACK_PROXY_PORTS = exports.DEFAULT_PROXY_PORT = exports.LS_CERT_FINGERPRINT = exports.LS_LOG_FILE_NAME = exports.DYNAMIC_PORT = exports.WINDOW_ORIGIN = void 0;
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
/** Default request timeout for custom model requests (2 minutes). */
exports.DEFAULT_MODEL_REQUEST_TIMEOUT_MS = 120000;
/** Default retry delay for streaming errors (1 second). */
exports.STREAM_RETRY_BASE_DELAY_MS = 1000;
/** Default retry delay for non-streaming errors (1 second). */
exports.NON_STREAM_RETRY_BASE_DELAY_MS = 1000;
/** Base delay for 429 rate-limit retries (2 seconds). */
exports.RATE_LIMIT_RETRY_BASE_DELAY_MS = 2000;
/** Base delay for 5xx server error retries (1 second). */
exports.SERVER_ERROR_RETRY_BASE_DELAY_MS = 1000;
// ─── Retry Configuration ──────────────────────────────────────────────────
/** Default maximum number of retries per model. */
exports.DEFAULT_MAX_RETRIES = 3;
/** Minimum allowed retry count. */
exports.MIN_MAX_RETRIES = 0;
/** Maximum allowed retry count. */
exports.MAX_MAX_RETRIES = 5;
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
    [exports.PROVIDERS.DEEPSEEK]: 'https://api.deepseek.com/anthropic',
    [exports.PROVIDERS.GROQ]: 'https://api.groq.com/openai/v1',
    [exports.PROVIDERS.MISTRAL]: 'https://api.mistral.ai/v1',
    [exports.PROVIDERS.CEREBRAS]: 'https://api.cerebras.ai/v1',
    [exports.PROVIDERS.KIMI]: 'https://api.moonshot.ai/anthropic/v1',
    [exports.PROVIDERS.FIREWORKS]: 'https://api.fireworks.ai/inference/v1',
    [exports.PROVIDERS.LMSTUDIO]: 'http://localhost:1234/v1',
    [exports.PROVIDERS.LLAMACPP]: 'http://localhost:8080/v1',
    [exports.PROVIDERS.NVIDIA]: 'https://integrate.api.nvidia.com/v1',
    [exports.PROVIDERS.OPENCODE]: '',
    [exports.PROVIDERS.CODESTRAL]: '',
    [exports.PROVIDERS.WAFER]: '',
    [exports.PROVIDERS.ZAI]: '',
};
//# sourceMappingURL=constants.js.map