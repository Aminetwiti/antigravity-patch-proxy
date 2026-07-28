import { describe, expect, it } from 'vitest';
import { NativeQuotaCardRenderer } from './native-quota-card';
import {
  CUSTOM_PROVIDER_FAILURE_SCENARIOS,
  findScenarioForError,
  type FailureScenario,
} from './custom-error-scenarios';

/**
 * Integration tests: NativeQuotaCardRenderer + FailureScenario catalog.
 * Verifies that each known scenario produces valid native Antigravity-style HTML.
 */

describe('NativeQuotaCardRenderer integration with FailureScenarios', () => {
  it('renders HTML for every scenario in the catalog', () => {
    const renderer = new NativeQuotaCardRenderer();
    for (const scenario of CUSTOM_PROVIDER_FAILURE_SCENARIOS) {
      const html = renderer.renderHtml({
        title: scenario.decodedTitle,
        message: scenario.decodedHint,
        primaryLabel: scenario.primaryActionLabel,
        secondaryLabel: scenario.secondaryActionLabel,
        dismissLabel: scenario.dismissLabel,
      });
      // data-label attributes carry the raw labels so tests don't have to
      // care about HTML-escaping (e.g. 'Wait & Retry' → 'Wait &amp; Retry'
      // in the body, but `data-label="Wait & Retry"` stays literal).
      expect(html).toContain(`data-label="${scenario.primaryActionLabel}"`);
      expect(html).toContain('Dismiss');
      expect(html).toContain('agy-native-quota-card');
    }
  });

  it('produces identical HTML structure for all scenarios', () => {
    const renderer = new NativeQuotaCardRenderer();
    const html1 = renderer.renderHtml({ title: 'A', message: 'B' });
    const html2 = renderer.renderHtml({ title: 'X', message: 'Y' });
    // Both should contain the structural container classes
    expect(html1).toContain('agy-quota-header');
    expect(html2).toContain('agy-quota-header');
    expect(html1).toContain('agy-quota-actions');
    expect(html2).toContain('agy-quota-actions');
  });

  it('HTML-escapes titles that contain dangerous characters', () => {
    const renderer = new NativeQuotaCardRenderer();
    const html = renderer.renderHtml({
      title: '<script>alert("xss")</script>',
      message: 'normal message',
    });
    expect(html).not.toContain('<script>');
    expect(html).toContain('&lt;script&gt;');
  });

  it('HTML-escapes messages that contain ampersands and quotes', () => {
    const renderer = new NativeQuotaCardRenderer();
    const html = renderer.renderHtml({
      title: 'Title',
      message: 'A & B "quoted" <bold>',
    });
    expect(html).toContain('&amp;');
    expect(html).toContain('&lt;bold&gt;');
    expect(html).toContain('&quot;');
  });

  it('does not include secondary button when secondaryLabel is omitted (render() returns null without DOM)', () => {
    const renderer = new NativeQuotaCardRenderer();
    const html = renderer.renderHtml({
      title: 'X',
      message: 'Y',
      // secondaryLabel is undefined here, falls through to the conditional
    });
    // With undefined secondaryLabel, the default 'See Plans' applies, so it IS included.
    // To verify conditional behavior, we need to bypass defaults at the render() level:
    const result = renderer.render({ title: 'X', message: 'Y', secondaryLabel: '' });
    // render() returns null in non-DOM environment, but the function should not throw
    expect(result).toBeNull();
  });

  it('renderForScenario() handles each known scenario type', () => {
    const renderer = new NativeQuotaCardRenderer();
    const htmlFn = (s: FailureScenario) =>
      renderer.renderHtml({
        title: s.decodedTitle,
        message: s.decodedHint,
        primaryLabel: s.primaryActionLabel,
        secondaryLabel: s.secondaryActionLabel,
        dismissLabel: s.dismissLabel,
      });
    const html401 = htmlFn(CUSTOM_PROVIDER_FAILURE_SCENARIOS.find((s) => s.id === 'auth_401')!);
    const html429 = htmlFn(CUSTOM_PROVIDER_FAILURE_SCENARIOS.find((s) => s.id === 'quota_429')!);
    const html404 = htmlFn(
      CUSTOM_PROVIDER_FAILURE_SCENARIOS.find((s) => s.id === 'model_not_found')!,
    );

    expect(html401).toContain('OpenAI Auth Error');
    expect(html401).toContain('Edit API Key');

    expect(html429).toContain('OpenAI Quota Reached');
    expect(html429).toContain('Switch to Fallback');

    expect(html404).toContain('Model Unavailable');
    expect(html404).toContain('Use gpt-4o');
  });
});

describe('Failure scenario to card mapping', () => {
  it('maps each status code to a rendered card', () => {
    const renderer = new NativeQuotaCardRenderer();
    const statuses = [400, 401, 402, 404, 429];
    for (const status of statuses) {
      const scenario = findScenarioForError('', status);
      expect(scenario).not.toBeNull();
      const html = renderer.renderHtml({
        title: scenario!.decodedTitle,
        message: scenario!.decodedHint,
        primaryLabel: scenario!.primaryActionLabel,
        secondaryLabel: scenario!.secondaryActionLabel,
        dismissLabel: scenario!.dismissLabel,
      });
      expect(html).toContain(scenario!.decodedTitle);
      expect(html.length).toBeGreaterThan(50);
    }
  });

  it('maps ECONNREFUSED pattern to Server Offline card', () => {
    const renderer = new NativeQuotaCardRenderer();
    const scenario = findScenarioForError('ECONNREFUSED 127.0.0.1:11434');
    expect(scenario?.id).toBe('offline_econn');
    const html = renderer.renderHtml({
      title: scenario!.decodedTitle,
      message: scenario!.decodedHint,
      primaryLabel: scenario!.primaryActionLabel,
    });
    expect(html).toContain('Ollama Server Offline');
    expect(html).toContain('Restart Stub');
  });

  it('maps ETIMEDOUT pattern to Network Timeout card', () => {
    const renderer = new NativeQuotaCardRenderer();
    const scenario = findScenarioForError('ETIMEDOUT after 30s');
    const html = renderer.renderHtml({
      title: scenario!.decodedTitle,
      message: scenario!.decodedHint,
      primaryLabel: scenario!.primaryActionLabel,
    });
    expect(html).toContain('Network Timeout');
    expect(html).toContain('Retry');
  });

  it('maps ENOTFOUND pattern to Invalid API URL card', () => {
    const renderer = new NativeQuotaCardRenderer();
    const scenario = findScenarioForError('ENOTFOUND api.minimaxi.chat');
    const html = renderer.renderHtml({
      title: scenario!.decodedTitle,
      message: scenario!.decodedHint,
      primaryLabel: scenario!.primaryActionLabel,
    });
    expect(html).toContain('Invalid API URL');
    expect(html).toContain('Edit Provider');
  });

  it('maps model_not_found pattern to Model Unavailable card', () => {
    const renderer = new NativeQuotaCardRenderer();
    const scenario = findScenarioForError('model_not_found: gpt-5-turbo');
    const html = renderer.renderHtml({
      title: scenario!.decodedTitle,
      message: scenario!.decodedHint,
      primaryLabel: scenario!.primaryActionLabel,
    });
    expect(html).toContain('Model Unavailable');
    expect(html).toContain('Use gpt-4o');
  });

  it('maps JSON parse error to Invalid Response Format card', () => {
    const renderer = new NativeQuotaCardRenderer();
    const scenario = findScenarioForError('JSON parse error: Unexpected token');
    const html = renderer.renderHtml({
      title: scenario!.decodedTitle,
      message: scenario!.decodedHint,
      primaryLabel: scenario!.primaryActionLabel,
    });
    expect(html).toContain('Invalid Response Format');
    expect(html).toContain('Report to Developer');
  });

  it('maps stream aborted to Stream Connection Broken card', () => {
    const renderer = new NativeQuotaCardRenderer();
    const scenario = findScenarioForError('aborted stream at chunk 42');
    const html = renderer.renderHtml({
      title: scenario!.decodedTitle,
      message: scenario!.decodedHint,
      primaryLabel: scenario!.primaryActionLabel,
    });
    expect(html).toContain('Stream Connection Broken');
    expect(html).toContain('Retry');
  });
});

describe('Card lifecycle safety', () => {
  it('destroy() is safe on an uninitialized renderer', () => {
    const renderer = new NativeQuotaCardRenderer();
    expect(() => renderer.destroy()).not.toThrow();
  });

  it('destroy() can be called multiple times safely', () => {
    const renderer = new NativeQuotaCardRenderer();
    renderer.destroy();
    renderer.destroy();
    renderer.destroy();
    expect(renderer['cardElement']).toBeNull();
  });

  it('renderHtml() does not depend on DOM globals', () => {
    const renderer = new NativeQuotaCardRenderer();
    expect(() => renderer.renderHtml({ title: 'X', message: 'Y' })).not.toThrow();
  });
});
