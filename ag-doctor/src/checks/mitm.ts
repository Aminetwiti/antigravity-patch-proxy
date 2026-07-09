/**
 * MITM check — reports CA installation, system proxy, and HTTPS interception status.
 * Added to the `doctor` command output.
 *
 * Special handling: if the system proxy is set but on the wrong port
 * (e.g. 443 instead of 50999), we report it as an explicit error with a
 * remediation hint, since this is the most common cause of
 * `ERR_HTTP_HEADERS_SENT` in the bundled proxy.
 */
import type { CheckResult } from '../types';
import { getMitmStatus, DEFAULT_MITM_PORT } from '../core/mitm';
import { getPatchStatus } from '../core/binary-patch';

export async function checkMitm(): Promise<CheckResult> {
  try {
    const s = await getMitmStatus();
    const parts: string[] = [];
    parts.push(s.caInstalled ? 'CA installed' : 'CA NOT installed');
    parts.push(s.proxyEnabled ? `proxy ${s.proxyHost}:${s.proxyPort}` : 'proxy OFF');
    if (s.interceptionOk !== null) {
      parts.push(s.interceptionOk ? 'interception OK' : 'interception FAILED');
    }
    const message = parts.join(' · ');
    const details = s.details.join('\n');

    // Detect the most common misconfiguration: proxy is set but on the wrong
    // port. This causes language_server to crash with ERR_HTTP_HEADERS_SENT
    // because nothing is listening on that port.
    const portMismatch =
      s.proxyEnabled &&
      s.proxyPort !== null &&
      s.proxyPort !== DEFAULT_MITM_PORT;

    // Check if the binary patch is active
    const patch = getPatchStatus();
    const isPatched = patch.applied;

    // Severity logic
    if (s.caInstalled && s.proxyEnabled && s.interceptionOk === true) {
      return {
        id: 'mitm',
        title: 'MITM (HTTPS interception)',
        status: 'ok',
        message,
        details,
        data: s,
      };
    }
    if (!s.caExists) {
      return {
        id: 'mitm',
        title: 'MITM (HTTPS interception)',
        status: 'info',
        message: 'CA not generated — interception unavailable',
        details,
        fixable: 'run `ag-doctor mitm install` to enable interception',
        data: s,
      };
    }
    if (portMismatch) {
      if (isPatched) {
        return {
          id: 'mitm',
          title: 'MITM (HTTPS interception)',
          status: 'warn',
          message: `System proxy is on port ${s.proxyPort} (Safe: binary patch bypasses system proxy)`,
          details:
            details +
            `\n\nNote: Antigravity is binary-patched to connect directly to the local proxy on ${DEFAULT_MITM_PORT}.\n` +
            `The system proxy is bypassed, so Antigravity works perfectly.\n` +
            `However, other system apps might fail if they try to use port ${s.proxyPort}.\n` +
            `If you want to clear it, run an elevated PowerShell and execute:\n` +
            `  netsh winhttp reset proxy`,
          fixable: false,
          data: s,
        };
      }
      return {
        id: 'mitm',
        title: 'MITM (HTTPS interception)',
        status: 'error',
        message: `System proxy is on port ${s.proxyPort} but MITM proxy listens on ${DEFAULT_MITM_PORT}`,
        details:
          details +
          `\n\nFix: run an elevated PowerShell and execute:\n` +
          `  netsh winhttp set proxy proxy-server="127.0.0.1:${DEFAULT_MITM_PORT}"`,
        fixable: false,
        data: s,
      };
    }
    return {
      id: 'mitm',
      title: 'MITM (HTTPS interception)',
      status: 'warn',
      message,
      details,
      fixable: !s.caInstalled ? 'run `ag-doctor mitm install`' : (!s.proxyEnabled ? 'run `ag-doctor mitm proxy-on`' : false),
      data: s,
    };
  } catch (e) {
    return {
      id: 'mitm',
      title: 'MITM (HTTPS interception)',
      status: 'error',
      message: `Check failed: ${(e as Error).message}`,
    };
  }
}
