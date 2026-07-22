/**
 * Version-specific binary patches for Antigravity language_server.
 *
 * Different Antigravity versions have different URL patterns in the binary.
 * This module detects the version and applies the appropriate patch.
 *
 * Auto-detection can be overridden by setting `patch.versionOverride` in the
 * user config (see `core/config.ts`). The override is exposed to the UI so
 * users can manually pin a range when:
 *   - auto-detection fails (binary stripped of version metadata)
 *   - the binary was modified by Google and no longer matches the registry
 *   - the user wants to test a patch range before it's officially supported
 */
import fs from 'fs';
import { getLanguageServerBinary, getLanguageServerBackup } from './paths';
import { detectAntigravityVersion } from './antigravity';
import { getPatchVersionOverride } from './config';
import type { PatchStatus } from '../types';

/**
 * Patch definitions for different Antigravity version ranges.
 * Each patch replaces an ORIGINAL_URL with a PATCHED_URL of the same length.
 */
export interface PatchDefinition {
  /** Version range this patch applies to (e.g., "2.0.x - 2.1.x") */
  versionRange: string;
  /** Minimum version (inclusive) */
  minVersion: string;
  /** Maximum version (inclusive, null = no upper limit) */
  maxVersion: string | null;
  /** Original URL to find in the binary */
  originalUrl: string;
  /** Replacement URL (must be same length as originalUrl) */
  patchedUrl: string;
  /** Human-readable description */
  description: string;
  /** Optional: extra JS-overlay instructions for this version range */
  extraInstructions?: {
    scriptName: string;
    missingJsModules?: string[];
    overwriteFiles?: string[];
    newRootFiles?: string[];
  };
}

/**
 * Registry of known patches for different Antigravity versions.
 * Ordered from newest to oldest.
 *
 * ⚠️ 2.3.x notes (added 2026-07-21):
 * - Binary URL pattern is UNCHANGED from 2.2.x (still `daily-cloudcode-pa.googleapis.com`)
 * - BUT: Google removed the entire `dist/proxy/*` tree + `cryptoStore` +
 *   `customModelStore` + `schemaValidator` + `proxy-runner.js` from the JS bundle.
 * - The repo's v2.2.x-patched `main.js`, `languageServer.js`, `ipcHandlers.js`,
 *   `preload.js`, `constants.js` still work as drop-in replacements (they contain
 *   the proxy integration hooks).
 * - The patch tool must therefore ALSO inject the 25 missing JS modules and
 *   overwrite the 5 stripped files. See `scripts/patch_2_3.js`.
 */
export const PATCH_REGISTRY: PatchDefinition[] = [
  {
    versionRange: '2.3.0+',
    minVersion: '2.3.0',
    maxVersion: null,
    originalUrl: 'https://daily-cloudcode-pa.googleapis.com',
    patchedUrl: 'http://localhost:50999/v1internal/xxxxxxx',
    description: 'Patch for Antigravity 2.3.0+ (41 bytes; binary URL unchanged — JS overlay required)',
    extraInstructions: {
      scriptName: 'patch_2_3.js',
      missingJsModules: [
        'cryptoStore', 'customModelStore', 'schemaValidator',
        'proxy',
        'proxy/dnsResolver', 'proxy/errorClassifier', 'proxy/idGenerator',
        'proxy/jsonRepair', 'proxy/modelLoader', 'proxy/modelUtils',
        'proxy/protoInjector', 'proxy/protobuf', 'proxy/registry',
        'proxy/retryStrategy', 'proxy/shared',
        'proxy/translators/anthropic', 'proxy/translators/google',
        'proxy/translators/ollama', 'proxy/translators/openai',
        'proxy/translators/utils', 'proxy/types', 'proxy/urlBuilder',
      ],
      overwriteFiles: [
        'dist/main.js', 'dist/languageServer.js', 'dist/ipcHandlers.js',
        'dist/preload.js', 'dist/constants.js',
      ],
      newRootFiles: ['proxy-runner.js'],
    },
  },
  {
    versionRange: '2.2.0 - 2.2.x',
    minVersion: '2.2.0',
    maxVersion: '2.2.99',
    originalUrl: 'https://daily-cloudcode-pa.googleapis.com',
    patchedUrl: 'http://localhost:50999/v1internal/xxxxxxx',
    description: 'Patch for Antigravity 2.2.0+ (41 bytes; 3 modules missing)',
    extraInstructions: {
      scriptName: 'patch_2_2_1.js',
      missingJsModules: [
        'cryptoStore', 'customModelStore', 'schemaValidator',
      ],
    },
  },
  {
    versionRange: '2.0.1 - 2.1.x',
    minVersion: '2.0.1',
    maxVersion: '2.1.99',
    originalUrl: 'https://daily-cloudcode-pa.googleapis.com',
    patchedUrl: 'http://localhost:50999/v1internal/xxxxxxx',
    description: 'Patch for Antigravity 2.0.1 to 2.1.x (41 bytes; full overlay OK)',
  },
];

/** Parse semantic version string to comparable number array [major, minor, patch] */
function parseVersion(version: string): number[] {
  const match = version.match(/^(\d+)\.(\d+)\.(\d+)/);
  if (!match) {
    // Try X.Y format
    const match2 = version.match(/^(\d+)\.(\d+)/);
    if (!match2) return [0, 0, 0];
    return [parseInt(match2[1], 10), parseInt(match2[2], 10), 0];
  }
  return [parseInt(match[1], 10), parseInt(match[2], 10), parseInt(match[3], 10)];
}

/** Compare two version arrays. Returns -1 if a < b, 0 if equal, 1 if a > b */
function compareVersions(a: number[], b: number[]): number {
  for (let i = 0; i < 3; i++) {
    if (a[i] < b[i]) return -1;
    if (a[i] > b[i]) return 1;
  }
  return 0;
}

/** Check if a version string is within a patch's version range */
function versionInRange(version: string, patch: PatchDefinition): boolean {
  const v = parseVersion(version);
  const min = parseVersion(patch.minVersion);
  const max = patch.maxVersion ? parseVersion(patch.maxVersion) : null;

  if (compareVersions(v, min) < 0) return false;
  if (max && compareVersions(v, max) > 0) return false;
  return true;
}

/**
 * Find the appropriate patch definition for the given Antigravity version.
 * Returns null if no matching patch is found.
 */
export function findPatchForVersion(version: string): PatchDefinition | null {
  for (const patch of PATCH_REGISTRY) {
    if (versionInRange(version, patch)) {
      return patch;
    }
  }
  return null;
}

/**
 * Detect which patch URLs are present in the binary.
 * Returns an array of found patch definitions.
 */
export function detectAvailablePatches(binaryPath: string): PatchDefinition[] {
  if (!fs.existsSync(binaryPath)) return [];
  
  const buf = fs.readFileSync(binaryPath);
  const haystack = buf.toString('binary');
  
  return PATCH_REGISTRY.filter(patch => {
    return haystack.includes(patch.originalUrl) || haystack.includes(patch.patchedUrl);
  });
}

/**
 * Enhanced patch status with version-specific information.
 */
export interface VersionAwarePatchStatus extends PatchStatus {
  antigravityVersion: string | null;
  /** Patch range the UI should highlight / the user selected (after override resolution). */
  recommendedPatch: PatchDefinition | null;
  /** All patch definitions whose URL pattern is found in the live binary. */
  detectedPatches: PatchDefinition[];
  compatible: boolean;
  warningMessage?: string;
  /** True when the recommended patch came from the user override, not auto-detection. */
  overrideActive?: boolean;
  /** Source of the recommended patch (for UI display). */
  recommendedSource?: 'auto' | 'override' | 'none';
  /** Override metadata (only present when overrideActive). */
  overrideInfo?: {
    range: string;
    reason: string | null;
    setAt: string | null;
  };
  /** All known ranges so the UI can render the version-selector cards. */
  availableRanges?: PatchDefinition[];
}

/**
 * Get version-aware patch status.
 * This checks the Antigravity version and determines the correct patch to use.
 *
 * Resolution order for `recommendedPatch`:
 *   1. If the user has set `patch.versionOverride` in config.json and that
 *      range is known, use it (marked `overrideActive=true`).
 *   2. Otherwise auto-detect from the binary and version.
 *   3. If neither works, return `null`.
 *
 * In all cases we ALSO return `availableRanges` so the UI can render the
 * version-selector cards, and `detectedPatches` so the UI can show which
 * ranges are actually present in the binary.
 */
export function getVersionAwarePatchStatus(installDir?: string): VersionAwarePatchStatus {
  const binaryPath = getLanguageServerBinary(installDir);
  const backupPath = getLanguageServerBackup(installDir);
  const override = getPatchVersionOverride();

  // Base status
  const baseStatus: PatchStatus = {
    binaryPath: binaryPath ?? null,
    exists: binaryPath ? fs.existsSync(binaryPath) : false,
    applied: false,
    backupExists: backupPath ? fs.existsSync(backupPath) : false,
  };

  // Always surface the available ranges so the UI can render the selector.
  const availableRanges = PATCH_REGISTRY;

  if (!binaryPath || !baseStatus.exists) {
    return {
      ...baseStatus,
      antigravityVersion: null,
      recommendedPatch: null,
      detectedPatches: [],
      compatible: false,
      warningMessage: 'Language server binary not found',
      availableRanges,
      recommendedSource: 'none',
    };
  }

  // Detect Antigravity version
  const versionInfo = detectAntigravityVersion(installDir);
  const version = versionInfo?.version ?? 'unknown';

  // Detect which patches are available in the binary
  const detectedPatches = detectAvailablePatches(binaryPath);

  // Auto-detected recommendation
  const autoRecommended = version !== 'unknown' ? findPatchForVersion(version) : null;

  // Apply override if present and valid; otherwise use auto-detection.
  let recommendedPatch: PatchDefinition | null = autoRecommended;
  let overrideActive = false;
  let recommendedSource: 'auto' | 'override' | 'none' = autoRecommended ? 'auto' : 'none';
  let overrideInfo: VersionAwarePatchStatus['overrideInfo'] | undefined;

  if (override.range) {
    const overridden = PATCH_REGISTRY.find((p) => p.versionRange === override.range);
    if (overridden) {
      recommendedPatch = overridden;
      overrideActive = true;
      recommendedSource = 'override';
      overrideInfo = {
        range: override.range,
        reason: override.reason,
        setAt: override.setAt,
      };
    }
  }

  // Check if any patch is applied
  const buf = fs.readFileSync(binaryPath);
  const haystack = buf.toString('binary');
  const applied = detectedPatches.some((p) => haystack.includes(p.patchedUrl));

  // Check compatibility (override bypasses auto-detect-specific warnings)
  let compatible = true;
  let warningMessage: string | undefined;

  if (!recommendedPatch) {
    compatible = false;
    warningMessage =
      version === 'unknown'
        ? 'Cannot determine Antigravity version. Pick a range manually below.'
        : `No patch available for Antigravity ${version}. This version may not be supported yet.`;
  } else if (detectedPatches.length === 0) {
    compatible = false;
    warningMessage = `Binary does not contain expected URL pattern. The binary may have been modified by Google.`;
  } else if (!overrideActive && !detectedPatches.some((p) => p === recommendedPatch)) {
    compatible = false;
    warningMessage = `Binary contains URL from ${detectedPatches[0].versionRange}, but Antigravity reports version ${version}. Version mismatch detected.`;
  }

  return {
    ...baseStatus,
    exists: true,
    applied,
    antigravityVersion: version,
    recommendedPatch,
    detectedPatches,
    compatible,
    warningMessage,
    overrideActive,
    recommendedSource,
    overrideInfo,
    availableRanges,
    originalUrl: recommendedPatch?.originalUrl,
    patchedUrl: recommendedPatch?.patchedUrl,
  };
}

/**
 * Apply version-specific patch based on detected Antigravity version.
 * If a user override is set in config.json, that range is used instead of
 * the auto-detected one.
 */
export function applyVersionSpecificPatch(installDir?: string): { ok: boolean; message: string } {
  const status = getVersionAwarePatchStatus(installDir);

  if (!status.exists) {
    return { ok: false, message: 'Language server binary not found' };
  }

  if (!status.compatible) {
    return { ok: false, message: status.warningMessage ?? 'Incompatible version' };
  }

  if (!status.recommendedPatch) {
    return { ok: false, message: 'No patch available for this Antigravity version' };
  }

  const binaryPath = status.binaryPath!;
  const patch = status.recommendedPatch;
  const source = status.overrideActive ? 'user override' : 'auto-detect';

  // Check if already patched
  const buf = fs.readFileSync(binaryPath);
  const haystack = buf.toString('binary');

  if (haystack.includes(patch.patchedUrl)) {
    return {
      ok: true,
      message: `Already patched (${patch.versionRange}, source: ${source})`,
    };
  }

  // Find original URL
  const idx = haystack.indexOf(patch.originalUrl);
  if (idx === -1) {
    return {
      ok: false,
      message: `Original URL not found in binary. Expected: ${patch.originalUrl} (source: ${source})`,
    };
  }

  // Create backup
  const backupPath = binaryPath + '.bak';
  if (!fs.existsSync(backupPath)) {
    try {
      fs.copyFileSync(binaryPath, backupPath);
    } catch (e) {
      return { ok: false, message: `Failed to create backup: ${(e as Error).message}` };
    }
  }

  // Apply patch
  const target = Buffer.from(patch.patchedUrl, 'binary');
  const out = Buffer.from(buf);
  target.copy(out, idx);

  try {
    fs.writeFileSync(binaryPath, out);
  } catch (e) {
    const err = e as NodeJS.ErrnoException;
    if (err.code === 'EBUSY') {
      return {
        ok: false,
        message: 'language_server is running. Close Antigravity and retry.',
      };
    }
    return { ok: false, message: `Failed to write binary: ${err.message}` };
  }

  return {
    ok: true,
    message: `Patched with ${patch.description} (source: ${source}; backup at ${backupPath})`,
  };
}
