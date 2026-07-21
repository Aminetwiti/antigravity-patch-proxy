#!/usr/bin/env node
/**
 * patch-version.js — version-agnostic dispatcher.
 *
 * Detects the installed Antigravity version (from app.asar's package.json)
 * and dispatches to the appropriate version-specific patcher:
 *
 *   2.0.x / 2.1.x  → full-overlay patch (repack.ps1 handles this)
 *   2.2.x          → scripts/patch_2_2_1.js  (3 missing modules)
 *   2.3.x          → scripts/patch_2_3.js    (25 missing + 5 overwrites + 1 new)
 *   other          → error with guidance
 *
 * Usage:
 *   node patch-version.js <asar-in> <build-dir> <asar-out>
 *
 * Same arguments as the version-specific scripts.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const asar = require('@electron/asar');

const [, , asarIn, buildDir, asarOut] = process.argv;
if (!asarIn || !buildDir || !asarOut) {
  console.error('usage: node patch-version.js <asar-in> <build-dir> <asar-out>');
  process.exit(1);
}
if (!fs.existsSync(asarIn)) {
  console.error(`[patch-version] asar-in not found: ${asarIn}`);
  process.exit(1);
}

console.log(`[patch-version] reading ${asarIn} ...`);

// Extract to a temp dir to read package.json
const probeDir = path.join(path.dirname(asarOut), `_probe-${Date.now()}`);
fs.mkdirSync(probeDir, { recursive: true });
try {
  asar.extractAll(asarIn, probeDir);
} catch (err) {
  console.error(`[patch-version] extract failed: ${err.message}`);
  process.exit(1);
}

const pkgPath = path.join(probeDir, 'package.json');
let version = 'unknown';
try {
  const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
  version = pkg.version || 'unknown';
} catch (err) {
  console.error(`[patch-version] cannot read package.json: ${err.message}`);
}

// Clean up probe
fs.rmSync(probeDir, { recursive: true, force: true });

console.log(`[patch-version] detected Antigravity version: ${version}`);

// Dispatch
const scriptsDir = __dirname;
let targetScript;
let exitCode = 0;
if (version.startsWith('2.3.')) {
  targetScript = path.join(scriptsDir, 'patch_2_3.js');
  console.log(`[patch-version] dispatching to patch_2_3.js (full overlay + 25 modules + 5 overwrites)`);
} else if (version.startsWith('2.2.')) {
  targetScript = path.join(scriptsDir, 'patch_2_2_1.js');
  console.log(`[patch-version] dispatching to patch_2_2_1.js (3 missing modules)`);
} else if (version.startsWith('2.0.') || version.startsWith('2.1.')) {
  console.log(`[patch-version] Antigravity ${version} ships the full bundle — no overlay needed.`);
  console.log('  Use `repack.ps1` (full overlay) instead of patch-version.js.');
  process.exit(1);
} else {
  console.error(`[patch-version] Unsupported Antigravity version: ${version}`);
  console.error('  Known versions: 2.0.x, 2.1.x, 2.2.x, 2.3.x');
  console.error('  Update scripts/patch-version.js + create a new patch_<version>.js.');
  process.exit(1);
}

if (!fs.existsSync(targetScript)) {
  console.error(`[patch-version] dispatcher script missing: ${targetScript}`);
  process.exit(1);
}

// Spawn the version-specific patcher
const { spawnSync } = require('child_process');
const result = spawnSync(process.execPath, [targetScript, asarIn, buildDir, asarOut], {
  stdio: 'inherit',
});
exitCode = result.status ?? 1;
process.exit(exitCode);