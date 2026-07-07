/**
 * Deterministic ID generation for custom models.
 * Pure functions — no I/O, no side effects, fully testable.
 */

import type { CustomModel } from './types';

/**
 * Base value for placeholder ID generation. Combined with a hash-derived offset
 * to produce IDs in the range [BASE, BASE + RANGE).
 */
export const PLACEHOLDER_ID_BASE = 400;
export const PLACEHOLDER_ID_RANGE = 200;

/**
 * Generates a deterministic placeholder ID for a custom model.
 * Used to inject models into the GetAvailableModels response.
 *
 * The same input always produces the same output (idempotent), enabling
 * consistent references across requests.
 */
export function generateModelPlaceholderId(model: CustomModel): string {
  const input = (model.displayName || model.name || 'custom-model').toLowerCase();
  let hash = 5381;
  for (let i = 0; i < input.length; i++) {
    hash = (hash << 5) + hash + input.charCodeAt(i);
    hash = hash & hash; // Force 32-bit integer
  }
  const placeholderNum = PLACEHOLDER_ID_BASE + (Math.abs(hash) % PLACEHOLDER_ID_RANGE);
  return `MODEL_PLACEHOLDER_M${placeholderNum}`;
}

/**
 * Generates a URL-safe slug for a custom model.
 * Used for routing and identification.
 */
export function toSlug(model: CustomModel): string {
  return (
    'custom-' +
    (model.externalModelName || model.name)
      .replace(/^models\//, '')
      .replace(/[^a-zA-Z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .toLowerCase()
  );
}
