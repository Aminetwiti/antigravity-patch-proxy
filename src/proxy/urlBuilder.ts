/**
 * URL construction for custom model requests.
 * Pure functions — no I/O, no side effects, fully testable.
 */

import type { CustomModel } from './types';

/**
 * Resolves the effective provider for routing purposes.
 * `custom` and `openrouter` are translated as OpenAI-compatible.
 */
export function resolveProvider(model: CustomModel): string {
  return model.provider === 'custom' || model.provider === 'openrouter' ? 'openai' : model.provider;
}

/**
 * Resolves the effective URL for a custom model request, applying provider-specific
 * URL construction rules.
 *
 * - `google` / `ollama`: delegated to a provider-specific translator via the registry.
 * - `openai` / `custom` / `openrouter`: appends `/chat/completions` if missing.
 *
 * @param model          The custom model configuration.
 * @param isStream       Whether this is a streaming request.
 * @param getProviderUrl Provider-URL resolver (typically the registry).
 *                       For google/ollama, this is `registry.getProviderUrl(...)`.
 *                       For openai/custom/openrouter, this can be a no-op identity.
 */
export function resolveCustomModelUrl(
  model: CustomModel,
  isStream: boolean,
  getProviderUrl: (
    apiUrl: string,
    externalModelName: string,
    isStream: boolean,
    translator: unknown,
  ) => string,
): string {
  const provider = resolveProvider(model);
  let finalUrlStr = model.apiUrl;

  if (provider === 'google' || provider === 'ollama') {
    const providerTranslator = (model as unknown as { _translator?: unknown })._translator;
    finalUrlStr = getProviderUrl(finalUrlStr, model.externalModelName, isStream, providerTranslator);
  } else if (provider === 'openai' || model.provider === 'custom' || model.provider === 'openrouter') {
    const urlLower = finalUrlStr.toLowerCase();
    if (!urlLower.includes('/chat/completions') && !urlLower.includes('/completions')) {
      if (finalUrlStr.endsWith('/v1')) {
        finalUrlStr += '/chat/completions';
      } else if (!finalUrlStr.endsWith('/')) {
        finalUrlStr += '/v1/chat/completions';
      } else {
        finalUrlStr += 'v1/chat/completions';
      }
    }
  }

  return finalUrlStr;
}

/**
 * Resolves the effective max retries for a custom model request.
 * Clamped to [0, 5].
 */
export function resolveMaxRetries(model: CustomModel): number {
  return Math.min(Math.max(model.maxRetries ?? 3, 0), 5);
}

/**
 * Resolves the effective request timeout in milliseconds.
 */
export function resolveRequestTimeout(model: CustomModel): number {
  return model.timeout || 120_000;
}
