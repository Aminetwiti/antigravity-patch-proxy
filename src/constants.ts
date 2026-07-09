/**
 * Constants for the proxy module.
 * Centralizes magic numbers and configuration values to improve maintainability.
 */

// ─── App Constants (used by main.ts, languageServer.ts, paths.ts) ─────────

/** Origin used by the main BrowserWindow. */
export const WINDOW_ORIGIN = 'https://127.0.0.1';

/** Pass 0 to the LS so the OS assigns an available port automatically. */
export const DYNAMIC_PORT = 0;

/** Log file name for the language server. */
export const LS_LOG_FILE_NAME = 'language_server.log';

/** SHA-256 fingerprint of the bundled language server certificate. */
export const LS_CERT_FINGERPRINT = 'sha256/sTZpQemOWEytaZqa7P/y/dNXbHMdOAzMvzHEhUwHZXw=';

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
export const DEFAULT_PROXY_PORT = 50999;

/** Fallback ports tried in order when DEFAULT_PROXY_PORT is in use. */
export const FALLBACK_PROXY_PORTS: readonly number[] = [51000, 51001, 51002, 51003, 51004, 51005, 51006, 51007, 51008, 51009, 51010];

/**
 * Default port for the ag-doctor-ui emergency proxy stub.
 * Kept separate from DEFAULT_PROXY_PORT to prevent conflicts.
 */
export const STUB_PORT_DEFAULT = 51999;

/** Path (relative to home) where the active proxy port is persisted for IPC. */
export const ACTIVE_PORT_FILE = '.gemini/antigravity/active_port';

/** Maximum request body size accepted by the proxy (10 MB). Prevents memory exhaustion DoS. */
export const MAX_REQUEST_BODY_SIZE = 10 * 1024 * 1024;

/** Timeout for Google proxy requests (60 seconds). */
export const GOOGLE_PROXY_TIMEOUT_MS = 60_000;

/** Timeout for forwarding requests to upstream Google APIs (30 seconds). */
export const GOOGLE_FORWARD_TIMEOUT_MS = 30_000;

/** Timeout for downloading file content from external URIs (30 seconds). */
export const FILE_DOWNLOAD_TIMEOUT_MS = 30_000;

/** Default request timeout for custom model requests (2 minutes). */
export const DEFAULT_MODEL_REQUEST_TIMEOUT_MS = 120_000;

/** Default retry delay for streaming errors (1 second). */
export const STREAM_RETRY_BASE_DELAY_MS = 1_000;

/** Default retry delay for non-streaming errors (1 second). */
export const NON_STREAM_RETRY_BASE_DELAY_MS = 1_000;

/** Base delay for 429 rate-limit retries (2 seconds). */
export const RATE_LIMIT_RETRY_BASE_DELAY_MS = 2_000;

/** Base delay for 5xx server error retries (1 second). */
export const SERVER_ERROR_RETRY_BASE_DELAY_MS = 1_000;

// ─── Retry Configuration ──────────────────────────────────────────────────

/** Default maximum number of retries per model. */
export const DEFAULT_MAX_RETRIES = 3;

/** Minimum allowed retry count. */
export const MIN_MAX_RETRIES = 0;

/** Maximum allowed retry count. */
export const MAX_MAX_RETRIES = 5;

// ─── Model Capabilities ────────────────────────────────────────────────────

/** Maximum input tokens for custom models. */
export const CUSTOM_MODEL_MAX_TOKENS = 1_048_576;

/** Maximum output tokens for custom models. */
export const CUSTOM_MODEL_MAX_OUTPUT_TOKENS = 4_096;

/** Default sampling temperature for non-thinking models. */
export const DEFAULT_TEMPERATURE = 0.7;

/** Default top-P sampling parameter. */
export const DEFAULT_TOP_P = 0.9;

/** Default top-K sampling parameter. */
export const DEFAULT_TOP_K = 40;

// ─── Model Placeholder ID Generation ──────────────────────────────────────

/** Base number for placeholder IDs (e.g., MODEL_PLACEHOLDER_M400). */
export const PLACEHOLDER_ID_BASE = 400;

/** Range for placeholder IDs (e.g., 200 = IDs from 400 to 599). */
export const PLACEHOLDER_ID_RANGE = 200;

// ─── DNS Resolution ───────────────────────────────────────────────────────

/** Public DNS servers used to bypass local DNS poisoning. */
export const PUBLIC_DNS_SERVERS = ['8.8.8.8', '1.1.1.1', '8.8.4.4'];

// ─── HTTP Status Codes ────────────────────────────────────────────────────

export const HTTP_STATUS = {
  OK: 200,
  BAD_REQUEST: 400,
  PAYLOAD_TOO_LARGE: 413,
  GATEWAY_TIMEOUT: 504,
  BAD_GATEWAY: 502,
  INTERNAL_SERVER_ERROR: 500,
} as const;

// ─── Google API Hosts ─────────────────────────────────────────────────────

export const GOOGLE_HOSTS = {
  CLOUD_CODE: 'daily-cloudcode-pa.googleapis.com',
  GENERATIVE_LANGUAGE: 'generativelanguage.googleapis.com',
} as const;

// ─── Content Types ────────────────────────────────────────────────────────

export const CONTENT_TYPES = {
  JSON: 'application/json',
  EVENT_STREAM: 'text/event-stream',
  GRPC_WEB_PROTO: 'application/grpc-web+proto',
} as const;

// ─── Provider Names ───────────────────────────────────────────────────────
// Single source of truth for all supported providers.

export const PROVIDERS = {
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
} as const;

export type ProviderName = (typeof PROVIDERS)[keyof typeof PROVIDERS];

/** All provider names as an array, useful for validation. */
export const ALL_PROVIDERS: readonly ProviderName[] = Object.values(PROVIDERS);

/** Providers that use OpenAI-compatible API format (chat/completions). */
export const OPENAI_COMPATIBLE_PROVIDERS = [
  PROVIDERS.OPENAI,
  PROVIDERS.CUSTOM,
  PROVIDERS.OPENROUTER,
] as const;

/** Providers that require an API key for authentication. */
export const PROVIDERS_REQUIRING_API_KEY: readonly ProviderName[] = [
  PROVIDERS.OPENAI,
  PROVIDERS.ANTHROPIC,
  PROVIDERS.OPENROUTER,
  PROVIDERS.GOOGLE,
  PROVIDERS.DEEPSEEK,
  PROVIDERS.GROQ,
  PROVIDERS.MISTRAL,
  PROVIDERS.CEREBRAS,
  PROVIDERS.KIMI,
  PROVIDERS.FIREWORKS,
  PROVIDERS.NVIDIA,
  PROVIDERS.OPENCODE,
  PROVIDERS.CODESTRAL,
  PROVIDERS.WAFER,
  PROVIDERS.ZAI,
];

/** Default API URLs per provider. Override per-model via apiUrl in custom_models.json. */
export const PROVIDER_DEFAULT_URLS: Record<ProviderName, string> = {
  [PROVIDERS.OPENAI]: 'https://api.openai.com/v1/chat/completions',
  [PROVIDERS.ANTHROPIC]: 'https://api.anthropic.com/v1/messages',
  [PROVIDERS.OPENROUTER]: 'https://openrouter.ai/api/v1/chat/completions',
  [PROVIDERS.OLLAMA]: 'http://localhost:11434/v1/chat/completions',
  [PROVIDERS.GOOGLE]: 'https://generativelanguage.googleapis.com/v1beta/models/',
  [PROVIDERS.CUSTOM]: '',
  [PROVIDERS.DEEPSEEK]: 'https://api.deepseek.com/anthropic',
  [PROVIDERS.GROQ]: 'https://api.groq.com/openai/v1',
  [PROVIDERS.MISTRAL]: 'https://api.mistral.ai/v1',
  [PROVIDERS.CEREBRAS]: 'https://api.cerebras.ai/v1',
  [PROVIDERS.KIMI]: 'https://api.moonshot.ai/anthropic/v1',
  [PROVIDERS.FIREWORKS]: 'https://api.fireworks.ai/inference/v1',
  [PROVIDERS.LMSTUDIO]: 'http://localhost:1234/v1',
  [PROVIDERS.LLAMACPP]: 'http://localhost:8080/v1',
  [PROVIDERS.NVIDIA]: 'https://integrate.api.nvidia.com/v1',
  [PROVIDERS.OPENCODE]: '',
  [PROVIDERS.CODESTRAL]: '',
  [PROVIDERS.WAFER]: '',
  [PROVIDERS.ZAI]: '',
};
