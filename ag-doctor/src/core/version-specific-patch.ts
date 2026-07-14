/**
 * Version-specific binary patches for Antigravity language_server.
 * 
 * Different Antigravity versions have different URL patterns in the binary.
 * This module detects the version and applies the appropriate patch.
 */
import fs from 'fs';
import { getLanguageServerBinary, getLanguageServerBackup } from './paths';
import { detectAntigravityVersion } from './antigravity';
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
}

/**
 * Registry of known patches for different Antigravity versions.
 * Ordered from newest to oldest.
 */
export const PATCH_REGISTRY: PatchDefinition[] = [
  {
    versionRange: '2.2.0+',
    minVersion: '2.2.0',
    maxVersion: null,
    originalUrl: 'https://daily-cloudcode-pa.googleapis.com',
    patchedUrl: 'http://localhost:50999/v1internal/xxxxxxx',
    description: 'Patch for Antigravity 2.2.0+ (41 bytes)',
  },
  {
    versionRange: '2.0.1 - 2.1.x',
    minVersion: '2.0.1',
    maxVersion: '2.1.99',
    originalUrl: 'https://daily-cloudcode-pa.googleapis.com',
    patchedUrl: 'http://localhost:50999/v1internal/xxxxxxx',
    description: 'Patch for Antigravity 2.0.1 to 2.1.x (41 bytes)',
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
  recommendedPatch: PatchDefinition | null;
  detectedPatches: PatchDefinition[];
  compatible: boolean;
  warningMessage?: string;
}

/**
 * Get version-aware patch status.
 * This checks the Antigravity version and determines the correct patch to use.
 */
export function getVersionAwarePatchStatus(installDir?: string): VersionAwarePatchStatus {
  const binaryPath = getLanguageServerBinary(installDir);
  const backupPath = getLanguageServerBackup(installDir);
  
  // Base status
  const baseStatus: PatchStatus = {
    binaryPath: binaryPath ?? null,
    exists: binaryPath ? fs.existsSync(binaryPath) : false,
    applied: false,
    backupExists: backupPath ? fs.existsSync(backupPath) : false,
  };

  if (!binaryPath || !baseStatus.exists) {
    return {
      ...baseStatus,
      antigravityVersion: null,
      recommendedPatch: null,
      detectedPatches: [],
      compatible: false,
      warningMessage: 'Language server binary not found',
    };
  }

  // Detect Antigravity version
  const versionInfo = detectAntigravityVersion(installDir);
  const version = versionInfo?.version ?? 'unknown';

  // Find recommended patch for this version
  const recommendedPatch = version !== 'unknown' ? findPatchForVersion(version) : null;

  // Detect which patches are available in the binary
  const detectedPatches = detectAvailablePatches(binaryPath);

  // Check if any patch is applied
  const buf = fs.readFileSync(binaryPath);
  const haystack = buf.toString('binary');
  const applied = detectedPatches.some(p => haystack.includes(p.patchedUrl));

  // Check compatibility
  let compatible = true;
  let warningMessage: string | undefined;

  if (version === 'unknown') {
    compatible = false;
    warningMessage = 'Cannot determine Antigravity version. Patch compatibility unknown.';
  } else if (!recommendedPatch) {
    compatible = false;
    warningMessage = `No patch available for Antigravity ${version}. This version may not be supported yet.`;
  } else if (detectedPatches.length === 0) {
    compatible = false;
    warningMessage = `Binary does not contain expected URL pattern for version ${version}. The binary may have been modified by Google.`;
  } else if (!detectedPatches.some(p => p === recommendedPatch)) {
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
    originalUrl: recommendedPatch?.originalUrl,
    patchedUrl: recommendedPatch?.patchedUrl,
  };
}

/**
 * Apply version-specific patch based on detected Antigravity version.
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

  // Check if already patched
  const buf = fs.readFileSync(binaryPath);
  const haystack = buf.toString('binary');
  
  if (haystack.includes(patch.patchedUrl)) {
    return { 
      ok: true, 
      message: `Already patched (${patch.versionRange})` 
    };
  }

  // Find original URL
  const idx = haystack.indexOf(patch.originalUrl);
  if (idx === -1) {
    return { 
      ok: false, 
      message: `Original URL not found in binary. Expected: ${patch.originalUrl}` 
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
        message: 'language_server is running. Close Antigravity and retry.' 
      };
    }
    return { ok: false, message: `Failed to write binary: ${err.message}` };
  }

  return { 
    ok: true, 
    message: `Patched with ${patch.description} (backup at ${backupPath})` 
  };
}
