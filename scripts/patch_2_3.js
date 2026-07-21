#!/usr/bin/env node
/**
 * patch_2_3.js — Surgical patcher for Antigravity v2.3.x app.asar.
 *
 * ════════════════════════════════════════════════════════════════════════════
 * VERSION DIFFERENCE (the WHY this script exists)
 * ════════════════════════════════════════════════════════════════════════════
 *
 * Antigravity 2.0.x / 2.1.0  ───────────────────────────────────────────────
 *   • Full bundle ships with `dist/proxy.js` + `dist/proxy/translators/`
 *   • `proxy-runner.js` lives at the root
 *   • `dist/main.js` has TLS bypass + `require('../proxy-runner')` integrated
 *   • Custom models work out of the box if proxy.js is configured
 *
 * Antigravity 2.2.x (since 2026-06)  ─────────────────────────────────────────
 *   • Google REMOVED `dist/proxy.js` + `dist/proxy/translators/` from the
 *     official bundle. The custom-model proxy code is NOT shipped anymore.
 *   • `proxy-runner.js` still present at the root (kept by Google as a hook)
 *   • `dist/main.js` still has TLS bypass + `require('../proxy-runner')`
 *   • But the proxy implementation is missing → proxy-runner loads
 *     `dist/proxy.js` → MODULE_NOT_FOUND
 *   • Fix: re-inject 3 modules (cryptoStore, customModelStore, schemaValidator)
 *     via `patch_2_2_1.js`.
 *
 * Antigravity 2.3.x (since 2026-07, e.g. 2.3.1)  ────────────────────────────
 *   • Google went MUCH further. They removed:
 *       1. The entire `dist/proxy/*` tree (22 modules)
 *       2. `dist/cryptoStore.js`, `dist/customModelStore.js`,
 *          `dist/schemaValidator.js`
 *       3. `proxy-runner.js` at the asar root
 *       4. ALL proxy integration hooks from `dist/main.js` (TLS bypass,
 *          `require('../proxy-runner')`)
 *       5. ALL `startProxy()` calls from `dist/languageServer.js`
 *       6. ALL custom-model IPC handlers from `dist/ipcHandlers.js`
 *          (file shrank from 34 KB to 9 KB)
 *       7. ALL Custom Models UI from `dist/preload.js`
 *          (file shrank from 75 KB to 5 KB)
 *       8. PROVIDERS list and config from `dist/constants.js`
 *          (file shrank from 9.9 KB to 355 B)
 *
 *   • The binary URL pattern is UNCHANGED: `daily-cloudcode-pa.googleapis.com`
 *     still appears in `language_server.exe` (1 occurrence) → binary patch
 *     still works the same way.
 *
 * What the patch needs to do for 2.3.x  ──────────────────────────────────────
 *   1. Re-inject the 25 missing JS modules (22 in `dist/proxy/*` + cryptoStore,
 *      customModelStore, schemaValidator).
 *   2. Re-create `proxy-runner.js` at the asar root.
 *   3. OVERWRITE 5 stripped files with the repo's v2.2.x-patched versions
 *      (which still have proxy integration hooks baked in):
 *        - dist/main.js            (TLS bypass + require proxy-runner)
 *        - dist/languageServer.js  (startProxy() call)
 *        - dist/ipcHandlers.js     (custom-model IPC handlers)
 *        - dist/preload.js         (Custom Models UI injection)
 *        - dist/constants.js       (PROVIDERS list)
 *
 *   These 5 files are NOT re-implemented; they come from the repo `dist/`
 *   which is the v2.2.x final state with proxy hooks intact. If you ever
 *   upgrade the repo past 2.2.x, ensure the repo files retain their proxy
 *   integration hooks.
 *
 * What the patch does NOT do  ───────────────────────────────────────────────
 *   • Does NOT touch the binary (binary patch is a separate step).
 *   • Does NOT add `dist/__mocks__/*` (would crash Electron module resolution).
 *   • Does NOT include `*.test.js` (test pollution).
 *
 * ════════════════════════════════════════════════════════════════════════════
 *
 * Usage:
 *   node patch_2_3.js <asar-in> <build-dir> <asar-out>
 *
 *   <asar-in>   Path to the existing app.asar (typically the deployed one
 *               under %LOCALAPPDATA%\Programs\Antigravity\resources\)
 *   <build-dir> Staging directory for the patched contents (will be wiped
 *               and recreated — DO NOT point at anything you want to keep)
 *   <asar-out>  Where to write the patched asar
 *
 * Env:
 *   AG_REPO_DIR  Override the project root (default: parent of this script).
 *                The project must contain a built `dist/` and `proxy-runner.js`.
 *
 * Exit codes:
 *   0  Success
 *   1  Bad CLI args, missing input file, missing source modules
 *   2  require('@electron/asar') failed
 *   3  asar.createPackage failed (repack error)
 */
'use strict';

const fs = require('fs');
const path = require('path');
const asar = require('@electron/asar');

// ─── The 25 modules that v2.3.x dropped and we need to re-inject ───────────
const MISSING_JS_MODULES = [
  // Standalone modules
  'cryptoStore',
  'customModelStore',
  'schemaValidator',
  // Main proxy entry point
  'proxy',
  // Proxy submodules
  'proxy/dnsResolver',
  'proxy/errorClassifier',
  'proxy/idGenerator',
  'proxy/jsonRepair',
  'proxy/modelLoader',
  'proxy/modelUtils',
  'proxy/protoInjector',
  'proxy/protobuf',
  'proxy/registry',
  'proxy/retryStrategy',
  'proxy/shared',
  'proxy/types',
  'proxy/urlBuilder',
  // Translators
  'proxy/translators/anthropic',
  'proxy/translators/google',
  'proxy/translators/ollama',
  'proxy/translators/openai',
  'proxy/translators/utils',
];

// ─── The 5 files that v2.3.x stripped and need to be OVERWRITTEN ───────────
// These come from the repo dist/ which retains v2.2.x proxy integration hooks.
const OVERWRITE_FILES = [
  'dist/main.js',
  'dist/languageServer.js',
  'dist/ipcHandlers.js',
  'dist/preload.js',
  'dist/constants.js',
];

// ─── The 1 root-level file that v2.3.x removed ─────────────────────────────
const NEW_ROOT_FILES = [
  'proxy-runner.js',
];

// Optional sibling files to copy alongside each .js module
const OPTIONAL_SIBLINGS = ['.d.ts', '.js.map', '.d.ts.map'];

function die(msg, code = 1) {
  console.error(`[patch_2_3] ${msg}`);
  process.exit(code);
}

function rimraf(p) {
  fs.rmSync(p, { recursive: true, force: true });
}

function ensureDir(p) {
  fs.mkdirSync(p, { recursive: true });
}

function copyFileIfExists(src, dst) {
  if (!fs.existsSync(src)) return false;
  ensureDir(path.dirname(dst));
  fs.copyFileSync(src, dst);
  return true;
}

function copySiblings(srcBase, dstBase) {
  // copy <name>.d.ts, <name>.js.map, <name>.d.ts.map if present
  const base = srcBase.replace(/\.js$/, '');
  const baseDst = dstBase.replace(/\.js$/, '');
  let count = 0;
  for (const ext of OPTIONAL_SIBLINGS) {
    const src = base + ext;
    const dst = baseDst + ext;
    if (copyFileIfExists(src, dst)) {
      count++;
      console.log(`            + ${path.basename(path.dirname(dst))}/${path.basename(dst)} (${fs.statSync(dst).size} B)`);
    }
  }
  return count;
}

async function main() {
  const [, , asarIn, buildDir, asarOut] = process.argv;
  if (!asarIn || !buildDir || !asarOut) {
    die('usage: node patch_2_3.js <asar-in> <build-dir> <asar-out>');
  }
  if (!fs.existsSync(asarIn)) die(`asar-in not found: ${asarIn}`);

  const repoDir = process.env.AG_REPO_DIR
    || path.resolve(__dirname, '..', '..');
  const repoDist = path.join(repoDir, 'dist');

  if (!fs.existsSync(repoDist)) {
    die(`repo dist/ not found at ${repoDist} — run \`npm run build\` first`);
  }

  console.log(`[patch_2_3] asar-in   = ${asarIn}`);
  console.log(`[patch_2_3] build-dir = ${buildDir}`);
  console.log(`[patch_2_3] asar-out  = ${asarOut}`);
  console.log(`[patch_2_3] repo      = ${repoDir}`);

  // Step 1: extract the deployed asar (clean staging dir first)
  console.log('[patch_2_3] step 1/4 — extract');
  rimraf(buildDir);
  ensureDir(buildDir);
  asar.extractAll(asarIn, buildDir);

  // Step 2: inject the 25 missing JS modules
  console.log(`[patch_2_3] step 2/4 — inject ${MISSING_JS_MODULES.length} missing JS modules`);
  const buildDist = path.join(buildDir, 'dist');
  ensureDir(buildDist);

  let totalBytes = 0;
  let filesAdded = 0;
  for (const mod of MISSING_JS_MODULES) {
    const srcJs = path.join(repoDist, `${mod}.js`);
    const dstJs = path.join(buildDist, `${mod}.js`);
    if (!fs.existsSync(srcJs)) {
      die(`required source missing: ${srcJs}\n` +
          `  (you may need to run \`npm run build\` in the repo first)`);
    }
    // Ensure the destination subdirectory exists (e.g. dist/proxy/)
    ensureDir(path.dirname(dstJs));
    fs.copyFileSync(srcJs, dstJs);
    const size = fs.statSync(srcJs).size;
    totalBytes += size;
    filesAdded++;
    console.log(`            + dist/${mod}.js (${size} B)`);
    filesAdded += copySiblings(srcJs, dstJs);
  }
  console.log(`            sub-total: ${filesAdded} files, ${totalBytes} B`);

  // Step 3: OVERWRITE 5 stripped files with repo's patched versions
  console.log(`[patch_2_3] step 3/4 — overwrite ${OVERWRITE_FILES.length} stripped files`);
  let owBytes = 0;
  let owCount = 0;
  for (const rel of OVERWRITE_FILES) {
    const src = path.join(repoDir, rel);
    const dst = path.join(buildDir, rel);
    if (!fs.existsSync(src)) {
      die(`required overwrite source missing: ${src}`);
    }
    ensureDir(path.dirname(dst));
    fs.copyFileSync(src, dst);
    const size = fs.statSync(src).size;
    owBytes += size;
    owCount++;
    console.log(`            ~ ${rel} (${size} B)`);
  }
  console.log(`            sub-total: ${owCount} files, ${owBytes} B`);

  // Step 4: add NEW root-level files (proxy-runner.js)
  console.log(`[patch_2_3] step 4/4 — add ${NEW_ROOT_FILES.length} new root file(s)`);
  let nrBytes = 0;
  let nrCount = 0;
  for (const rel of NEW_ROOT_FILES) {
    const src = path.join(repoDir, rel);
    const dst = path.join(buildDir, rel);
    if (!fs.existsSync(src)) {
      die(`required root file missing: ${src}`);
    }
    ensureDir(path.dirname(dst));
    fs.copyFileSync(src, dst);
    const size = fs.statSync(src).size;
    nrBytes += size;
    nrCount++;
    console.log(`            + ${rel} (${size} B)`);
  }
  console.log(`            sub-total: ${nrCount} files, ${nrBytes} B`);

  // Step 5: repack
  console.log('[patch_2_3] step 5/5 — repack');
  if (fs.existsSync(asarOut)) fs.unlinkSync(asarOut);
  try {
    await asar.createPackage(buildDir, asarOut);
  } catch (err) {
    die(`asar.createPackage failed: ${err.stack || err.message}`, 3);
  }

  const inSize = fs.statSync(asarIn).size;
  const outSize = fs.statSync(asarOut).size;
  const delta = outSize - inSize;
  const grandTotal = totalBytes + owBytes + nrBytes;
  console.log(`[patch_2_3] done — ${asarOut}`);
  console.log(`            in:  ${inSize} B`);
  console.log(`            out: ${outSize} B (+${delta} B)`);
  console.log(`            patched: ${filesAdded + owCount + nrCount} files (~${grandTotal} B of source)`);
  // v2.3.x patch is larger than v2.2.x because it replaces 5 large files
  // (preload.js alone is ~75 KB). Expect ~500 KB growth.
  if (delta > 800 * 1024) {
    console.warn(`[patch_2_3] WARNING: output grew by ${(delta / 1024).toFixed(1)} KB (>800 KB).`);
    console.warn('            v2.3.x patch typically adds ~450 KB. If growth is much larger,');
    console.warn('            something unexpected got copied — abort and check the build-dir.');
  }
}

main().catch((err) => die(err.stack || err.message));