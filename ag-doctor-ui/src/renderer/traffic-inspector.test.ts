import { describe, expect, it } from 'vitest';
import { TrafficInspectorEngine } from './traffic-inspector';
import { exportProvidersToJson, importProvidersFromJson, ExportableProviderConfig } from './config-export-import';
import { evaluateSystemHealth, SystemHealthState } from './health-sentinel';

/**
 * Unit tests for Traffic Inspector, Config Export/Import & Health Sentinel Modules.
 */

describe('Traffic Inspector Engine', () => {
  it('logs network traffic entry and prepends to entries list', () => {
    const engine = new TrafficInspectorEngine();
    const entry = engine.logTraffic({
      method: 'POST',
      path: '/v1beta/models/gemini-1.5-pro:generateContent',
      targetModel: 'gemini-1.5-pro',
      translatedProvider: 'OpenAI',
      statusCode: 200,
      latencyMs: 145,
    });

    expect(entry.id).toMatch(/^tr-/);
    expect(engine.getEntries()).toHaveLength(1);
    expect(engine.getEntries()[0].statusCode).toBe(200);
  });

  it('filters traffic entries by provider name or search query', () => {
    const engine = new TrafficInspectorEngine();
    engine.logTraffic({
      method: 'POST',
      path: '/v1/chat/completions',
      targetModel: 'gpt-4o',
      translatedProvider: 'OpenAI',
      statusCode: 200,
      latencyMs: 180,
    });
    engine.logTraffic({
      method: 'POST',
      path: '/v1/messages',
      targetModel: 'claude-3-5-sonnet',
      translatedProvider: 'Anthropic',
      statusCode: 200,
      latencyMs: 240,
    });

    const openaiMatches = engine.filterEntries('gpt', 'OpenAI');
    expect(openaiMatches).toHaveLength(1);
    expect(openaiMatches[0].targetModel).toBe('gpt-4o');

    const allAnthropic = engine.filterEntries('', 'Anthropic');
    expect(allAnthropic).toHaveLength(1);
    expect(allAnthropic[0].translatedProvider).toBe('Anthropic');
  });

  it('clears traffic entries list', () => {
    const engine = new TrafficInspectorEngine();
    engine.logTraffic({
      method: 'POST',
      path: '/test',
      targetModel: 'm',
      translatedProvider: 'p',
      statusCode: 200,
      latencyMs: 10,
    });
    engine.clear();
    expect(engine.getEntries()).toHaveLength(0);
  });
});

describe('Config Export & Import Manager', () => {
  const sampleProviders: ExportableProviderConfig[] = [
    {
      id: 'p-1',
      name: 'My OpenAI API',
      provider: 'openai',
      apiUrl: 'https://api.openai.com/v1',
      apiKey: 'sk-1234567890abcdef',
      allowUnauthorized: false,
      models: ['gpt-4o'],
    },
  ];

  it('exports provider config bundle with key sanitization', () => {
    const jsonStr = exportProvidersToJson(sampleProviders, true);
    expect(jsonStr).toContain('2.2.0');
    expect(jsonStr).toContain('My OpenAI API');
    expect(jsonStr).toContain('sk-1...cdef'); // sanitized key
  });

  it('imports valid JSON provider bundle successfully', () => {
    const jsonStr = exportProvidersToJson(sampleProviders, false);
    const res = importProvidersFromJson(jsonStr);
    expect(res.valid).toBe(true);
    expect(res.providers).toHaveLength(1);
    expect(res.providers![0].name).toBe('My OpenAI API');
  });

  it('rejects corrupt JSON strings or invalid schemas', () => {
    const res1 = importProvidersFromJson('{ corrupt json');
    expect(res1.valid).toBe(false);
    expect(res1.error).toContain('JSON Parse error');

    const res2 = importProvidersFromJson('{"version": "1.0"}');
    expect(res2.valid).toBe(false);
    expect(res2.error).toContain('missing "providers" array');
  });
});

describe('Health Sentinel Monitor', () => {
  it('detects Antigravity IDE update when modified timestamp advances', () => {
    const state: SystemHealthState = {
      lastModified: 1700005000,
      asarStatus: 'clean',
      proxyActive: true,
      mitmActive: true,
    };

    const sentinel = evaluateSystemHealth(state, 1700000000);
    expect(sentinel.healthy).toBe(false);
    expect(sentinel.updateDetected).toBe(true);
    expect(sentinel.statusText).toContain('IDE update detected');
  });

  it('reports healthy when proxy services are active and no binary update occurred', () => {
    const state: SystemHealthState = {
      lastModified: 1700000000,
      asarStatus: 'clean',
      proxyActive: true,
      mitmActive: true,
    };

    const sentinel = evaluateSystemHealth(state, 1700000000);
    expect(sentinel.healthy).toBe(true);
    expect(sentinel.updateDetected).toBe(false);
    expect(sentinel.statusText).toBe('All systems operational');
  });
});
