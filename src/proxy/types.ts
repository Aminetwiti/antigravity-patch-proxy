/**
 * Shared types for the proxy module.
 */

/**
 * Configuration for a user-defined custom model.
 */
export interface CustomModel {
  name: string;
  displayName: string;
  description: string;
  provider: string;
  apiKey: string;
  apiUrl: string;
  externalModelName: string;
  allowUnauthorized?: boolean;
  encrypted?: boolean;
  _slug?: string;
  timeout?: number;
  maxRetries?: number;
}

/**
 * Shape of a Gemini-format request body.
 */
export interface GeminiRequestBody {
  model?: string;
  modelId?: string;
  model_id?: string;
  request?: GeminiRequestBody;
  systemInstruction?: { parts: { text?: string }[] };
  contents?: {
    parts?: { text?: string; functionCall?: unknown; functionResponse?: unknown; thought?: boolean }[];
    role?: string;
  }[];
  tools?: unknown[];
  generationConfig?: {
    temperature?: number;
    maxOutputTokens?: number;
  };
}

/**
 * Shape of a Gemini-format response candidate.
 */
export interface GeminiCandidate {
  content?: { parts?: unknown[]; role?: string };
  finishReason?: string;
  index?: number;
}

/**
 * Shape of a Cloud Code response envelope.
 */
export interface CloudCodeResponse {
  response: { candidates?: GeminiCandidate[] } | unknown;
  traceId?: string;
  metadata?: Record<string, unknown>;
}
