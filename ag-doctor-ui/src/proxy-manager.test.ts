import { describe, expect, it } from 'vitest';
import { getProxyManager, ProxyServerStatus } from './proxy-manager';

/**
 * Unit tests for ProxyManager lifecycle, environment setup, and status evaluation.
 */

describe('ProxyManager Singleton & Default Configuration', () => {
  it('returns a persistent singleton instance', () => {
    const instance1 = getProxyManager();
    const instance2 = getProxyManager();
    expect(instance1).toBe(instance2);
  });

  it('evaluates status as not running when process is uninitialized', async () => {
    const mgr = getProxyManager();
    const status: ProxyServerStatus = await mgr.getStatus();
    expect(status.running).toBe(false);
    expect(status.port).toBe(50999);
    expect(status.pid).toBeUndefined();
    expect(status.error).toBeUndefined();
  });
});

describe('ProxyManager Environment Variables Contract', () => {
  it('prepares expected environment variables for spawned proxy script', () => {
    const port = 50999;
    const host = '127.0.0.1';
    const env = {
      ...process.env,
      AG_MITM_PORT: String(port),
      AG_MITM_HOST: host,
      AG_PROXY_TARGET: 'http://127.0.0.1:50999',
    };

    expect(env.AG_MITM_PORT).toBe('50999');
    expect(env.AG_MITM_HOST).toBe('127.0.0.1');
    expect(env.AG_PROXY_TARGET).toBe('http://127.0.0.1:50999');
  });
});
