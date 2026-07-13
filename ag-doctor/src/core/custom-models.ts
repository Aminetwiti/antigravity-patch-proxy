/**
 * Read/write the custom_models.json file.
 *
 * Note: this module only handles the plaintext JSON representation.
 * Encryption is handled by the running Electron app via safeStorage.
 * For CLI inspection / migration purposes we read/write the file as-is.
 *
 * Improvements over the original:
 *   - `loadCustomModels` no longer throws on corrupt JSON — returns an empty
 *     file and logs a warning instead.
 *   - `looksEncrypted` uses a broader set of known key prefixes (was: only
 *     `sk-` and `AIza`, which missed Google, Groq, Mistral, etc.).
 *   - `validateCustomModels` now allows `apiKey` to be optional for providers
 *     that don't require authentication (e.g. Ollama, LM Studio).
 */
import fs from 'fs';
import path from 'path';
import { getCustomModelsPath, getAntigravityDataDir } from './paths';
import type { CustomModel, CustomModelsFile } from '../types';

const KNOWN_PROVIDERS = new Set([
  'openai',
  'anthropic',
  'openrouter',
  'ollama',
  'google',
  'custom',
  'deepseek',
  'groq',
  'mistral',
  'cerebras',
  'kimi',
  'kimchi', // internal OpenAI-compatible proxy
  'fireworks',
  'lmstudio',
  'llamacpp',
  'nvidia',
  'opencode',
  'codestral',
  'wafer',
  'zai',
]);

// Providers that don't require an API key (local servers, etc.)
const KEYLESS_PROVIDERS = new Set(['ollama', 'lmstudio', 'llamacpp']);

// Known plaintext API-key prefixes. Anything else is treated as encrypted
// (opaque blob produced by Electron's safeStorage).
const KNOWN_KEY_PREFIXES = [
  'sk-',         // OpenAI, OpenRouter, DeepSeek, Groq, Mistral, Cerebras, Fireworks, Kimi, Z.ai
  'AIza',        // Google AI Studio
  'gsk_',        // Groq (newer)
  'nvapi-',      // NVIDIA NIM
  'fk-',         // Fireworks (alt)
  'wafer-',      // Wafer
  'ant-',        // Anthropic (newer)
];

export function loadCustomModels(filePath?: string): CustomModelsFile {
  const fp = filePath ?? getCustomModelsPath();
  if (!fs.existsSync(fp)) {
    return { models: [] };
  }
  try {
    const raw = fs.readFileSync(fp, 'utf-8').replace(/^\uFEFF/, '');
    const parsed = JSON.parse(raw);
    if (!parsed || !Array.isArray(parsed.models)) {
      return { models: [] };
    }
    return { models: parsed.models as CustomModel[] };
  } catch (e) {
    // Corrupt JSON should not crash the CLI — log and return empty.
    console.warn(`[custom-models] failed to parse ${fp}: ${(e as Error).message}`);
    return { models: [] };
  }
}

export function saveCustomModels(
  file: CustomModelsFile,
  filePath?: string,
): void {
  const fp = filePath ?? getCustomModelsPath();
  fs.mkdirSync(path.dirname(fp), { recursive: true });
  fs.writeFileSync(fp, JSON.stringify(file, null, 2), 'utf-8');
}

/**
 * Returns a stable unique key for a custom model.
 * Two models are considered the same only when they share BOTH name and provider,
 * so users can register the same model name against different providers/endpoints.
 */
export function modelKey(model: CustomModel): string {
  return `${model.provider || 'custom'}::${model.name}`;
}

export function addCustomModel(model: CustomModel, filePath?: string): CustomModelsFile {
  const file = loadCustomModels(filePath);
  const key = modelKey(model);
  const idx = file.models.findIndex((m) => modelKey(m) === key);
  if (idx >= 0) {
    file.models[idx] = model;
  } else {
    file.models.push(model);
  }
  saveCustomModels(file, filePath);
  return file;
}

export function removeCustomModel(name: string, filePath?: string): CustomModelsFile {
  const file = loadCustomModels(filePath);
  // Match by name only when no provider is encoded, otherwise by full key.
  // Accept either the legacy plain name or the "provider::name" form.
  file.models = file.models.filter((m) => {
    if (name.includes('::')) return modelKey(m) !== name;
    return m.name !== name;
  });
  saveCustomModels(file, filePath);
  return file;
}

/**
 * Heuristic: detect if the file contains encrypted API keys (opaque strings).
 *
 * A key is considered "encrypted" if it's non-empty AND doesn't match any
 * known plaintext prefix. This catches safeStorage-encrypted blobs (which are
 * base64 with no recognizable prefix) without false-positives on legitimate
 * keys from any supported provider.
 */
export function looksEncrypted(filePath?: string): boolean {
  const fp = filePath ?? getCustomModelsPath();
  if (!fs.existsSync(fp)) return false;
  const file = loadCustomModels(fp);
  return file.models.some((m) => {
    if (typeof m.apiKey !== 'string' || m.apiKey.length === 0) return false;
    return !KNOWN_KEY_PREFIXES.some((p) => m.apiKey!.startsWith(p));
  });
}

export interface ValidationIssue {
  model: string;
  field: string;
  message: string;
}

export function validateCustomModels(file: CustomModelsFile): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  for (const m of file.models) {
    if (!m.name || !m.name.startsWith('models/')) {
      issues.push({ model: m.name ?? '<unnamed>', field: 'name', message: 'must start with "models/"' });
    }
    if (!m.provider) {
      issues.push({ model: m.name, field: 'provider', message: 'is required' });
    } else if (!KNOWN_PROVIDERS.has(m.provider)) {
      issues.push({ model: m.name, field: 'provider', message: `unknown provider "${m.provider}"` });
    }
    if (!m.apiUrl) {
      issues.push({ model: m.name, field: 'apiUrl', message: 'is required' });
    } else {
      try {
        new URL(m.apiUrl);
      } catch {
        issues.push({ model: m.name, field: 'apiUrl', message: 'is not a valid URL' });
      }
    }
    if (!m.externalModelName) {
      issues.push({ model: m.name, field: 'externalModelName', message: 'is required' });
    }
    // API key is required unless the provider is keyless (Ollama, LM Studio, etc.)
    if (!m.apiKey && m.provider && !KEYLESS_PROVIDERS.has(m.provider)) {
      issues.push({ model: m.name, field: 'apiKey', message: 'is required for this provider' });
    }
  }
  return issues;
}

/** Returns the data dir, creating it if needed. */
export function ensureDataDir(): string {
  const dir = getAntigravityDataDir();
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}
