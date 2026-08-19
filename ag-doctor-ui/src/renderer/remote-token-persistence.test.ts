import { describe, expect, it, beforeEach } from 'vitest';

describe('Doctor UI — Remote Token Persistence & Formatting', () => {
  let mockStorage: Record<string, string> = {};

  beforeEach(() => {
    mockStorage = {};
  });

  const getSavedToken = (): string => {
    return mockStorage['ag_remote_auth_token'] || '';
  };

  const saveToken = (token: string): void => {
    mockStorage['ag_remote_auth_token'] = token.trim();
  };

  const resolveEffectiveToken = (inputToken?: string): string => {
    const raw = (inputToken !== undefined ? inputToken : getSavedToken()).trim();
    return raw.length > 0 ? raw : '11';
  };

  const formatRemoteWsUrl = (hostOrIp: string, port: number, isTunnel: boolean, token: string): string => {
    const effectiveToken = resolveEffectiveToken(token);
    if (isTunnel) {
      const cleanHost = hostOrIp.replace(/^https?:\/\//, '').replace(/\/+$/, '');
      return `wss://${cleanHost}/ws?token=${encodeURIComponent(effectiveToken)}`;
    }
    return `ws://${hostOrIp}:${port}/ws?token=${encodeURIComponent(effectiveToken)}`;
  };

  it('restores empty token when nothing is saved and defaults to 11', () => {
    expect(getSavedToken()).toBe('');
    expect(resolveEffectiveToken()).toBe('11');
  });

  it('saves custom auth token and restores it permanently', () => {
    saveToken('my-super-secret-token');
    expect(getSavedToken()).toBe('my-super-secret-token');
    expect(resolveEffectiveToken()).toBe('my-super-secret-token');
  });

  it('formats local network WebSocket URL with saved token', () => {
    saveToken('pin1234');
    const wsUrl = formatRemoteWsUrl('192.168.1.50', 8090, false, getSavedToken());
    expect(wsUrl).toBe('ws://192.168.1.50:8090/ws?token=pin1234');
  });

  it('formats Cloudflare tunnel WSS URL with saved token and escapes query params', () => {
    saveToken('custom_token_42');
    const wsUrl = formatRemoteWsUrl('https://my-tunnel.trycloudflare.com', 8090, true, getSavedToken());
    expect(wsUrl).toBe('wss://my-tunnel.trycloudflare.com/ws?token=custom_token_42');
  });

  it('generates a random alphanumeric token and saves it', () => {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    let rand = '';
    for (let i = 0; i < 8; i++) {
      rand += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    expect(rand).toHaveLength(8);
    saveToken(rand);
    expect(getSavedToken()).toBe(rand);
    expect(resolveEffectiveToken()).toBe(rand);
  });
});
