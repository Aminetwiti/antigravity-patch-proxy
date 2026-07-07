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
  fixable?: boolean;
  data?: unknown;
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
}

export interface ConnectivityResult {
  url: string;
  ok: boolean;
  latencyMs?: number;
  statusCode?: number;
  error?: string;
}

export interface CommandContext {
  json: boolean;
  verbose: boolean;
  yes: boolean;
  cwd: string;
}
