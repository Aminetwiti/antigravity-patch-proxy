/**
 * Centralized custom model storage.
 *
 * Single source of truth for reading, writing, masking and fallback
 * generation of custom_models.json. Eliminates duplication between
 * ipcHandlers.ts and proxy.ts and makes file/parse failures explicit.
 */

import * as fs from 'fs/promises';
import * as fsSync from 'fs';
import * as path from 'path';
import { app } from 'electron';
import log from 'electron-log/main';

import * as cryptoStore from './cryptoStore';

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
  latencyMs?: number;
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
  usage?: {
    promptTokens: number;
    completionTokens: number;
    totalRequests: number;
    lastUsed?: number;
  };
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
      if (!p) continue;
      if (p.enabled === false) continue;
      const models = Array.isArray(p.models) ? p.models : [];
      for (const m of models) {
        if (!m || m.enabled === false) continue;
        flatModels.push({
           name: `${p.id || 'provider-unknown'}-${m.id}`,
           displayName: m.displayName || m.id,
           provider: p.provider || 'openai',
           apiKey: p.apiKey || 'none',
           apiUrl: p.apiUrl || '',
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
  const existing = readExistingJson(filePath);
  existing.models = models;
  await atomicWriteJson(filePath, existing);
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

function atomicWriteJson(filePath: string, payload: unknown): Promise<void> {
  return (async () => {
    await fs.mkdir(path.dirname(filePath), { recursive: true });
    const tmp = `${filePath}.${process.pid}.${Date.now()}.tmp`;
    await fs.writeFile(tmp, JSON.stringify(payload, null, 2), 'utf-8');
    await fs.rename(tmp, filePath);
  })();
}

function readExistingJson(filePath: string): Record<string, unknown> {
  try {
    const content = fsSync.readFileSync(filePath, 'utf-8');
    return JSON.parse(stripBom(content)) as Record<string, unknown>;
  } catch {
    return {};
  }
}

export async function saveProviders(providers: ProviderFileEntry[]): Promise<void> {
  const filePath = getCustomModelsPath();
  const existing = readExistingJson(filePath);
  existing.providers = providers;
  await atomicWriteJson(filePath, existing);
}

/**
 * Increments request count and token statistics for a specified provider.
 */
export async function recordProviderUsage(providerId: string, promptTokens: number = 0, completionTokens: number = 0): Promise<void> {
  try {
    const providers = await loadProviders();
    const target = providers.find((p) => p.id === providerId || `provider-${p.id}` === providerId);
    if (!target) return;

    if (!target.usage) {
      target.usage = { promptTokens: 0, completionTokens: 0, totalRequests: 0 };
    }
    target.usage.promptTokens += Math.max(0, promptTokens);
    target.usage.completionTokens += Math.max(0, completionTokens);
    target.usage.totalRequests += 1;
    target.usage.lastUsed = Date.now();

    await saveProviders(providers);
  } catch (err) {
    log.error('[CustomModelStore] Failed to record provider usage:', err);
  }
}

/**
 * Removes a model by name and persists the remaining models. (Legacy)
 *
 * For provider-backed models (name format `providerId-modelId`), this removes
 * the model entry from the corresponding provider rather than rewriting the
 * legacy `models` array, which would clobber the entire `providers` block.
 */
export async function deleteCustomModel(modelName: string): Promise<void> {
  const providers = await loadProviders();
  let mutated = false;
  for (const p of providers) {
    const prefix = `${p.id}-`;
    if (modelName.startsWith(prefix)) {
      const modelId = modelName.slice(prefix.length);
      const before = p.models.length;
      p.models = p.models.filter((m) => m.id !== modelId);
      if (p.models.length !== before) {
        mutated = true;
      }
    }
  }
  if (mutated) {
    await saveProviders(providers);
    return;
  }
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
