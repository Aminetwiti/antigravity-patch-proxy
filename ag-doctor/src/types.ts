/**
 * Shared types for ag-doctor.
 */

export type Severity = 'ok' | 'warn' | 'error' | 'info';

export interface CheckResult {
  id: string;
  title: string;
  status: Severity;
  message: string;
  details?: string;
  fixable?: boolean | string;
  data?: unknown;
  source?: 'builtin' | 'plugin';
}

export interface CustomModel {
  name: string;
  displayName?: string;
  description?: string;
  provider: string;
  apiKey?: string;
  apiUrl: string;
  externalModelName: string;
  allowUnauthorized?: boolean;
  timeout?: number;
  maxRetries?: number;
}

export interface CustomModelsFile {
  models: CustomModel[];
}

export interface SystemInfo {
  platform: NodeJS.Platform;
  arch: string;
  nodeVersion: string;
  osRelease: string;
  homedir: string;
  username: string;
  cwd: string;
}

export interface PatchStatus {
  binaryPath: string | null;
  exists: boolean;
  applied: boolean;
  backupExists: boolean;
  originalUrl?: string;
  patchedUrl?: string;
  /**
   * Estimated size delta between the live binary and the candidate
   * patch (in bytes). Reported by `validateAsar()` when the live asar
   * is available; null otherwise. Positive when the candidate is larger.
   */
  deltaSizeBytes?: number | null;
}

export interface ConnectivityResult {
  url: string;
  ok: boolean;
  latencyMs?: number;
  statusCode?: number;
  error?: string;
  /** Response headers from the HTTP probe (for X-Proxy-Stub detection etc.) */
  headers?: Record<string, string>;
  /** First 512 chars of the response body (for diagnostics) */
  body?: string;
}

export interface CommandContext {
  json: boolean;
  verbose: boolean;
  yes: boolean;
  cwd: string;
  options: Record<string, string | boolean>;
}
