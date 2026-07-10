/**
 * Centralized custom model storage.
 *
 * Single source of truth for reading, writing, masking and fallback
 * generation of custom_models.json. Eliminates duplication between
 * ipcHandlers.ts and proxy.ts and makes file/parse failures explicit.
 */

import * as fs from 'fs/promises';
import * as path from 'path';
import { app } from 'electron';
import log from 'electron-log/main';

// eslint-disable-next-line @typescript-eslint/no-var-requires
const cryptoStore = require('./cryptoStore');

import {
  CUSTOM_MODEL_MAX_TOKENS,
  CUSTOM_MODEL_MAX_OUTPUT_TOKENS,
  PROVIDERS,
} from './constants';

export interface CustomModelFileEntry {
  name: string;
  displayName?: string;
  description?: string;
  provider: string;
  apiKey: string;
  apiUrl: string;
  externalModelName: string;
  allowUnauthorized?: boolean;
  encrypted?: boolean;
  [key: string]: unknown;
}

export interface TestModelParams {
  apiUrl: string;
  provider: string;
  apiKey?: string;
  allowUnauthorized?: boolean;
}

export interface ConnectionTestResult {
  success: boolean;
  status?: number;
  message?: string;
  error?: string;
}

export interface FallbackModelEntry {
  name: string;
  displayName: string;
  version: string;
  description: string;
  inputTokenLimit: number;
  outputTokenLimit: number;
  supportedGenerationMethods: string[];
  apiProvider: string;
}

/**
 * Returns the absolute path to custom_models.json.
 */
export function getCustomModelsPath(): string {
  const geminiDir = path.join(app.getPath('home'), '.gemini', 'antigravity');
  return path.join(geminiDir, 'custom_models.json');
}

/**
 * Reads and parses custom_models.json.
 * Returns an empty array if the file does not exist.
 * Logs and returns an empty array on parse or decryption errors.
 */
export async function loadCustomModels(): Promise<CustomModelFileEntry[]> {
  const filePath = getCustomModelsPath();

  try {
    const content = await fs.readFile(filePath, 'utf-8');
    const parsed = JSON.parse(stripBom(content)) as { models?: CustomModelFileEntry[] };
    return parsed.models ?? [];
  } catch (error) {
    if (isNodeError(error) && error.code === 'ENOENT') {
      log.info('[CustomModelStore] custom_models.json not found, returning empty list');
      return [];
    }
    log.error('[CustomModelStore] Failed to load custom_models.json:', error);
    return [];
  }
}

/**
 * Persists the full list of custom models to disk.
 */
export async function saveCustomModels(models: CustomModelFileEntry[]): Promise<void> {
  const filePath = getCustomModelsPath();
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, JSON.stringify({ models }, null, 2), 'utf-8');
}

/**
 * Removes a model by name and persists the remaining models.
 */
export async function deleteCustomModel(modelName: string): Promise<void> {
  const models = await loadCustomModels();
  const filtered = models.filter((model) => model.name !== modelName);
  await saveCustomModels(filtered);
}

/**
 * Masks an API key for display in the UI.
 * - 'none' is returned as-is.
 * - Keys of 8 chars or less become '********'.
 * - Longer keys become 'abcd...wxyz'.
 */
export function maskApiKey(encryptedKey: string): string {
  if (!encryptedKey || encryptedKey === 'none') {
    return encryptedKey;
  }

  try {
    const decrypted = cryptoStore.decryptString(encryptedKey) as string;
    if (decrypted.length <= 8) {
      return '********';
    }
    return `${decrypted.slice(0, 4)}...${decrypted.slice(-4)}`;
  } catch {
    // Key might not be encrypted; mask the raw value instead.
    if (encryptedKey.length <= 8) {
      return '********';
    }
    return `${encryptedKey.slice(0, 4)}...${encryptedKey.slice(-4)}`;
  }
}

/**
 * Encrypts a plaintext API key when it is not masked and not 'none'.
 */
export function encryptApiKeyIfNeeded(apiKey: string | undefined): {
  apiKey: string;
  encrypted: boolean;
} {
  if (!apiKey || apiKey === 'none' || isMaskedKey(apiKey)) {
    return { apiKey: apiKey ?? 'none', encrypted: false };
  }
  return {
    apiKey: cryptoStore.encryptString(apiKey),
    encrypted: true,
  };
}

/**
 * Builds a fallback model entry used when upstream model list requests
 * fail or time out. Keeps the proxy contract consistent everywhere.
 */
export function buildFallbackModelEntry(model: CustomModelFileEntry): FallbackModelEntry {
  return {
    name: model.name,
    displayName: model.displayName ?? model.name,
    version: model.name,
    description: model.description ?? `Custom ${model.provider} model`,
    inputTokenLimit: CUSTOM_MODEL_MAX_TOKENS,
    outputTokenLimit: CUSTOM_MODEL_MAX_OUTPUT_TOKENS,
    supportedGenerationMethods: ['generateContent', 'countTokens'],
    apiProvider: model.provider === PROVIDERS.GOOGLE ? 'API_PROVIDER_GOOGLE_GEMINI' : 'API_PROVIDER_CUSTOM',
  };
}

function stripBom(content: string): string {
  return content.charCodeAt(0) === 0xfeff ? content.slice(1) : content;
}

function isMaskedKey(key: string): boolean {
  return key.includes('...') || key.startsWith('***') || key === '********';
}

function isNodeError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && 'code' in error;
}
