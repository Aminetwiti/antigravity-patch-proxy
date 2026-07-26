/**
 * Provider Configuration Import / Export & Base64 Exchange.
 * Allows users to share configurations via Base64 strings, files, or deep-links,
 * with conflict resolution strategies (overwrite, merge, skip).
 */

import type { ProviderFileEntry } from './customModelStore';

export type MergeStrategy = 'overwrite' | 'merge' | 'skip';

export interface ImportResult {
  success: boolean;
  importedCount: number;
  skippedCount: number;
  mergedCount: number;
  providers: ProviderFileEntry[];
  error?: string;
}

/**
 * Encodes an array of ProviderFileEntry objects to a compressed Base64 string for URL or clipboard sharing.
 */
export function exportProvidersToBase64(providers: ProviderFileEntry[]): string {
  const jsonStr = JSON.stringify({ version: 1, providers });
  return Buffer.from(jsonStr, 'utf-8').toString('base64');
}

/**
 * Decodes a Base64 configuration string back into ProviderFileEntry objects.
 */
export function parseProvidersFromBase64(base64Str: string): ProviderFileEntry[] {
  if (!base64Str || typeof base64Str !== 'string') {
    throw new Error('Invalid Base64 input string');
  }

  let jsonStr: string;
  try {
    jsonStr = Buffer.from(base64Str.trim(), 'base64').toString('utf-8');
  } catch (err) {
    throw new Error(`Failed to decode Base64 string: ${(err as Error).message}`);
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(jsonStr);
  } catch (err) {
    throw new Error(`Failed to parse decoded JSON: ${(err as Error).message}`);
  }

  if (typeof parsed === 'object' && parsed !== null && 'providers' in parsed && Array.isArray((parsed as { providers: unknown }).providers)) {
    return (parsed as { providers: ProviderFileEntry[] }).providers;
  }

  if (Array.isArray(parsed)) {
    return parsed as ProviderFileEntry[];
  }

  throw new Error('Decoded JSON does not contain a valid providers array');
}

/**
 * Merges incoming provider configurations into existing provider configurations using the chosen strategy.
 */
export function mergeProviderConfigs(
  existing: ProviderFileEntry[],
  incoming: ProviderFileEntry[],
  strategy: MergeStrategy = 'merge',
): ImportResult {
  const existingMap = new Map<string, ProviderFileEntry>();
  existing.forEach((p) => existingMap.set(p.id, { ...p }));

  let importedCount = 0;
  let skippedCount = 0;
  let mergedCount = 0;

  for (const inc of incoming) {
    if (!inc || !inc.id || !inc.name) continue;

    if (!existingMap.has(inc.id)) {
      existingMap.set(inc.id, { ...inc });
      importedCount++;
    } else {
      if (strategy === 'skip') {
        skippedCount++;
      } else if (strategy === 'overwrite') {
        existingMap.set(inc.id, { ...inc });
        mergedCount++;
      } else if (strategy === 'merge') {
        const prev = existingMap.get(inc.id)!;
        // Merge models deduplicated by id
        const modelMap = new Map<string, typeof prev.models[0]>();
        prev.models.forEach((m) => modelMap.set(m.id, m));
        inc.models.forEach((m) => modelMap.set(m.id, m));

        existingMap.set(inc.id, {
          ...prev,
          ...inc,
          models: Array.from(modelMap.values()),
        });
        mergedCount++;
      }
    }
  }

  const finalProviders = Array.from(existingMap.values());
  return {
    success: true,
    importedCount,
    skippedCount,
    mergedCount,
    providers: finalProviders,
  };
}
