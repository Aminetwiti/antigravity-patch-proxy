import { describe, expect, it } from 'vitest';
import { NativeQuotaCardRenderer } from './native-quota-card';

/**
 * Unit tests for NativeQuotaCardRenderer component.
 */

describe('NativeQuotaCardRenderer Component', () => {
  it('renders native quota card HTML with default title, message, and action labels', () => {
    const renderer = new NativeQuotaCardRenderer();
    const html = renderer.renderHtml();

    expect(html).toContain('class="agy-native-quota-card"');
    expect(html).toContain('role="alert"');
    expect(html).toContain('Baseline model quota reached');
    expect(html).toContain('Dismiss');
    expect(html).toContain('Switch Model');
    expect(html).toContain('See Plans');
  });

  it('customizes card title, message, and buttons dynamically', () => {
    const renderer = new NativeQuotaCardRenderer();
    const html = renderer.renderHtml({
      title: 'Custom Model Rate Limit Reached',
      message: 'Rate limit reached on Claude 3.5 Sonnet. Resets in 02:00.',
      primaryLabel: 'Switch to Fallback',
      secondaryLabel: 'Edit API Key',
      dismissLabel: 'Close',
    });

    expect(html).toContain('Custom Model Rate Limit Reached');
    expect(html).toContain('Rate limit reached on Claude 3.5 Sonnet');
    expect(html).toContain('Switch to Fallback');
    expect(html).toContain('Edit API Key');
    expect(html).toContain('Close');
  });

  it('destroys card element safely when DOM element is uninitialized', () => {
    const renderer = new NativeQuotaCardRenderer();
    renderer.destroy();
    expect(renderer['cardElement']).toBeNull();
  });
});
