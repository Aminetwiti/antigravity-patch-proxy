import { describe, expect, it } from 'vitest';

/**
 * Unit tests for SmartBannerManager logic and Patch Verdict evaluation.
 */

interface SystemPatchState {
  proxyListening: boolean;
  proxyResponding: boolean;
  mitmListening: boolean;
  mitmCaInstalled: boolean;
  customModelsLoaded: number;
  startProxyErrors: number;
}

interface PatchVerdict {
  label: string;
  severity: 'ok' | 'warn' | 'error';
  action?: 'patch' | 'launch-mitm' | 'repair' | 'install-ca' | 'add-model';
  message: string;
}

function computeVerdict(state: SystemPatchState): PatchVerdict {
  if (!state.proxyListening) {
    return { label: 'Proxy OFF', severity: 'error', action: 'patch', message: 'Local proxy is down. Run repair to start proxy.' };
  }
  if (!state.mitmListening) {
    return { label: 'MITM REQUIS', severity: 'error', action: 'launch-mitm', message: 'MITM proxy on port 443 is required but not listening.' };
  }
  if (state.startProxyErrors > 0) {
    return { label: 'PATCH KAPUT', severity: 'error', action: 'repair', message: 'Proxy startup errors detected in main.log.' };
  }
  if (!state.mitmCaInstalled) {
    return { label: 'CA NOT TRUSTED', severity: 'warn', action: 'install-ca', message: 'MITM root CA certificate is not installed in OS trust store.' };
  }
  if (state.customModelsLoaded === 0) {
    return { label: 'NO CUSTOM MODELS', severity: 'warn', action: 'add-model', message: 'No custom model providers configured.' };
  }
  return { label: 'PATCH OK', severity: 'ok', message: 'System is fully operational.' };
}

function formatCountdown(sec: number): string {
  if (sec <= 0) return 'Reset ready';
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  return `Resets in ${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
}

describe('SmartBannerManager computeVerdict logic', () => {
  it('returns Proxy OFF when local proxy is down', () => {
    const v = computeVerdict({
      proxyListening: false,
      proxyResponding: false,
      mitmListening: true,
      mitmCaInstalled: true,
      customModelsLoaded: 2,
      startProxyErrors: 0,
    });
    expect(v.label).toBe('Proxy OFF');
    expect(v.severity).toBe('error');
    expect(v.action).toBe('patch');
  });

  it('returns MITM REQUIS when port 443 is not listening', () => {
    const v = computeVerdict({
      proxyListening: true,
      proxyResponding: true,
      mitmListening: false,
      mitmCaInstalled: true,
      customModelsLoaded: 2,
      startProxyErrors: 0,
    });
    expect(v.label).toBe('MITM REQUIS');
    expect(v.severity).toBe('error');
    expect(v.action).toBe('launch-mitm');
  });

  it('returns PATCH KAPUT when startup errors exist', () => {
    const v = computeVerdict({
      proxyListening: true,
      proxyResponding: true,
      mitmListening: true,
      mitmCaInstalled: true,
      customModelsLoaded: 2,
      startProxyErrors: 3,
    });
    expect(v.label).toBe('PATCH KAPUT');
    expect(v.severity).toBe('error');
    expect(v.action).toBe('repair');
  });

  it('returns CA NOT TRUSTED when root CA is not in OS trust store', () => {
    const v = computeVerdict({
      proxyListening: true,
      proxyResponding: true,
      mitmListening: true,
      mitmCaInstalled: false,
      customModelsLoaded: 2,
      startProxyErrors: 0,
    });
    expect(v.label).toBe('CA NOT TRUSTED');
    expect(v.severity).toBe('warn');
    expect(v.action).toBe('install-ca');
  });

  it('returns NO CUSTOM MODELS when 0 providers configured', () => {
    const v = computeVerdict({
      proxyListening: true,
      proxyResponding: true,
      mitmListening: true,
      mitmCaInstalled: true,
      customModelsLoaded: 0,
      startProxyErrors: 0,
    });
    expect(v.label).toBe('NO CUSTOM MODELS');
    expect(v.severity).toBe('warn');
    expect(v.action).toBe('add-model');
  });

  it('returns PATCH OK when system is fully operational', () => {
    const v = computeVerdict({
      proxyListening: true,
      proxyResponding: true,
      mitmListening: true,
      mitmCaInstalled: true,
      customModelsLoaded: 3,
      startProxyErrors: 0,
    });
    expect(v.label).toBe('PATCH OK');
    expect(v.severity).toBe('ok');
    expect(v.action).toBeUndefined();
  });
});

describe('SmartBannerManager countdown formatting', () => {
  it('formats remaining seconds to MM:SS format', () => {
    expect(formatCountdown(125)).toBe('Resets in 02:05');
    expect(formatCountdown(59)).toBe('Resets in 00:59');
    expect(formatCountdown(0)).toBe('Reset ready');
    expect(formatCountdown(-10)).toBe('Reset ready');
  });
});
