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

/** Default port for the local proxy server. Falls back to dynamic port if in use. */
export const DEFAULT_PROXY_PORT = 50999;

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

export const PROVIDERS = {
  GOOGLE: 'google',
  OPENAI: 'openai',
  ANTHROPIC: 'anthropic',
  OLLAMA: 'ollama',
  CUSTOM: 'custom',
  OPENROUTER: 'openrouter',
} as const;

/** Providers that use OpenAI-compatible API format. */
export const OPENAI_COMPATIBLE_PROVIDERS = [PROVIDERS.OPENAI, PROVIDERS.CUSTOM, PROVIDERS.OPENROUTER] as const;
