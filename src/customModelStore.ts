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

export interface ProviderModelEntry {
  id: string;
  displayName?: string;
  enabled: boolean;
}

export interface ProviderFileEntry {
  id: string;
  name: string;
  provider: string;
  apiUrl: string;
  apiKey: string;
  allowUnauthorized?: boolean;
  encrypted?: boolean;
  enabled: boolean;
  models: ProviderModelEntry[];
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
    const parsed = JSON.parse(stripBom(content)) as { models?: CustomModelFileEntry[], providers?: ProviderFileEntry[] };
    
    // Legacy migration case
    if (parsed.models && !parsed.providers) {
      return parsed.models;
    }

    if (parsed.providers) {
      const flatModels: CustomModelFileEntry[] = [];
      for (const p of parsed.providers) {
        if (!p.enabled) continue;
        for (const m of p.models) {
          if (!m.enabled) continue;
          flatModels.push({
             name: `${p.id}-${m.id}`,
             displayName: m.displayName || m.id,
             provider: p.provider,
             apiKey: p.apiKey,
             apiUrl: p.apiUrl,
             externalModelName: m.id,
             allowUnauthorized: p.allowUnauthorized,
             encrypted: p.encrypted
          });
        }
      }
      return flatModels;
    }
    return [];
  } catch (error) {
    if (isNodeError(error) && error.code === 'ENOENT') {
      log.info('[CustomModelStore] custom_models.json not found, returning empty list');
      return [];
    }
    log.error('[CustomModelStore] Failed to load custom_models.json:', error);
    return [];
  }
}

export async function saveCustomModels(models: CustomModelFileEntry[]): Promise<void> {
  const filePath = getCustomModelsPath();
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, JSON.stringify({ models }, null, 2), 'utf-8');
}

export async function loadProviders(): Promise<ProviderFileEntry[]> {
  const filePath = getCustomModelsPath();
  try {
    const content = await fs.readFile(filePath, 'utf-8');
    const parsed = JSON.parse(stripBom(content)) as { models?: CustomModelFileEntry[], providers?: ProviderFileEntry[] };
    
    if (parsed.providers) {
       return parsed.providers;
    }

    if (parsed.models && parsed.models.length > 0) {
       log.info('[CustomModelStore] Migrating legacy models to providers architecture');
       const providerMap = new Map<string, ProviderFileEntry>();
       let pId = 1;
       for (const m of parsed.models) {
         const pKey = m.apiUrl + '|' + m.provider + '|' + m.apiKey;
         if (!providerMap.has(pKey)) {
            providerMap.set(pKey, {
              id: `provider-${Date.now()}-${pId++}`,
              name: `Legacy ${m.provider}`,
              provider: m.provider,
              apiUrl: m.apiUrl,
              apiKey: m.apiKey,
              allowUnauthorized: m.allowUnauthorized,
              encrypted: m.encrypted,
              enabled: true,
              models: []
            });
         }
         const p = providerMap.get(pKey)!;
         p.models.push({
            id: m.externalModelName || m.name,
            displayName: m.displayName || m.name,
            enabled: true
         });
       }
       const migratedProviders = Array.from(providerMap.values());
       saveProviders(migratedProviders).catch(e => log.error('Failed to save migration', e));
       return migratedProviders;
    }
    return [];
  } catch (error) {
    if (isNodeError(error) && error.code === 'ENOENT') return [];
    log.error('[CustomModelStore] Failed to load providers:', error);
    return [];
  }
}

export async function saveProviders(providers: ProviderFileEntry[]): Promise<void> {
  const filePath = getCustomModelsPath();
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, JSON.stringify({ providers }, null, 2), 'utf-8');
}

/**
 * Removes a model by name and persists the remaining models. (Legacy)
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
