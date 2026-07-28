/**
 * Recent Models Store for Antigravity Proxy
 * Keeps track of the most recently used custom models to pin them to the top of the IDE dropdown with ⭐.
 */

import fs from 'fs';
import path from 'path';
import os from 'os';
import log from 'electron-log';

const STORE_PATH = path.join(os.tmpdir(), 'ag-recent-models.json');
const MAX_RECENT_MODELS = 3;

let recentModelSlugs: string[] = [];

// Initialize from disk
try {
  if (fs.existsSync(STORE_PATH)) {
    const raw = fs.readFileSync(STORE_PATH, 'utf-8');
    recentModelSlugs = JSON.parse(raw);
  }
} catch (_) {
  recentModelSlugs = [];
}

/** Record a model as recently used */
export function recordRecentModel(slugOrName: string): void {
  if (!slugOrName) return;
  recentModelSlugs = [slugOrName, ...recentModelSlugs.filter((s) => s !== slugOrName)].slice(0, MAX_RECENT_MODELS);
  try {
    fs.writeFileSync(STORE_PATH, JSON.stringify(recentModelSlugs));
  } catch (e) {
    log.warn('[RecentModels] Failed to save recent models:', e);
  }
}

/** Get list of recent model identifiers */
export function getRecentModels(): string[] {
  return [...recentModelSlugs];
}

/** Check if a model is in the recent/favorite list */
export function isRecentModel(slugOrName: string): boolean {
  return recentModelSlugs.includes(slugOrName);
}
