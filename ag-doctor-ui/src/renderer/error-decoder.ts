/**
 * Pure helpers extracted from `app.ts` so they can be unit-tested without a
 * browser/DOM. Keep this file dependency-free.
 */

/**
 * Format a byte count as a short, human-readable string (B / KB / MB / GB / TB).
 * Mirrors the implementation previously inlined in `app.ts`.
 */
export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.min(units.length - 1, Math.floor(Math.log(bytes) / Math.log(1024)));
  const value = bytes / Math.pow(1024, i);
  return `${value.toFixed(value < 10 && i > 0 ? 2 : value < 100 && i > 0 ? 1 : 0)} ${units[i]}`;
}

type ErrorAction =
  | 'open-mitm-view'
  | 'run-doctor'
  | 'show-retry-toast'
  | 'none';

interface DecodedError {
  matched: boolean;
  pattern: string;
  hint: string;
  action: ErrorAction;
}

interface ErrorPattern {
  pattern: string;
  hint: string;
  action: ErrorAction;
  matcher: (haystack: string) => boolean;
}

/**
 * Anchored MITM matcher: requires proxy/mitm/listen context before the port
 * to avoid false positives on legitimate port-443 traffic elsewhere in logs.
 */
const KNOWN_ERROR_PATTERNS: ErrorPattern[] = [
  {
    pattern: 'MITM proxy unreachable (127.0.0.1:443)',
    hint: 'The local MITM proxy is not reachable. The proxy is mandatory for the patch to work — open the MITM view to start it (HTTP on port 443 + HTTPS on port 8443).',
    action: 'open-mitm-view',
    matcher: (s) =>
      /(?:proxy|mitm|listen).*127\.0\.0\.1\s*:\s*443|EADDRNOTAVAIL.*127\.0\.0\.1.*443|ECONNREFUSED.*127\.0\.0\.1.*443/i.test(
        s,
      ),
  },
  {
    pattern: 'Missing Node module (Cannot find module)',
    hint: 'A dependency expected by the doctor CLI is missing. Run "npm install" in ag-doctor (or use the Repair action if available) and try again.',
    action: 'run-doctor',
    matcher: (s) => /Cannot find module|MODULE_NOT_FOUND|require\.resolve/i.test(s),
  },
  {
    pattern: 'Antigravity crash on launch',
    hint: 'Antigravity did not start cleanly after the patch (or before it). Verify the language_server binary is readable, the backup is intact and try again. If it keeps crashing, restore from backup.',
    action: 'show-retry-toast',
    matcher: (s) =>
      /Antigravity crash|antigravity.*crash(ed)? on launch|crash on startup|process exited unexpectedly/i.test(
        s,
      ),
  },
  {
    pattern: 'Port already in use (EADDRINUSE)',
    hint: 'A local port (e.g. 50999 / 443 / 8443) is already taken by another process. Close the application using that port (often a leftover Antigravity instance) and retry.',
    action: 'run-doctor',
    matcher: (s) => /EADDRINUSE|address already in use|bind:.*already in use|listen.*already in use/i.test(s),
  },
];

/**
 * Decode a CLI stderr/stdout pair into a structured, actionable error.
 * Returns `{ matched: false, ... }` when no known pattern matches.
 */
export function decodeError(stderr: string, stdout = ''): DecodedError {
  const haystack = `${stderr || ''}\n${stdout || ''}`;
  for (const def of KNOWN_ERROR_PATTERNS) {
    if (def.matcher(haystack)) {
      return {
        matched: true,
        pattern: def.pattern,
        hint: def.hint,
        action: def.action,
      };
    }
  }
  return { matched: false, pattern: '', hint: '', action: 'none' };
}
