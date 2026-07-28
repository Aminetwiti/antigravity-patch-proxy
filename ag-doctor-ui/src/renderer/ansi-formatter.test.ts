import { describe, expect, it } from 'vitest';

/**
 * Unit tests for ANSI escape code conversion and HTML sanitization.
 */

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function ansiToHtml(s: string): string {
  return escapeHtml(s)
    .replace(/\x1b\[32m/g, '<span class="t-ok">')
    .replace(/\x1b\[33m/g, '<span class="t-warn">')
    .replace(/\x1b\[31m/g, '<span class="t-err">')
    .replace(/\x1b\[36m/g, '<span class="t-info">')
    .replace(/\x1b\[90m/g, '<span class="t-dim">')
    .replace(/\x1b\[1m/g, '<span class="t-bold">')
    .replace(/\x1b\[22m/g, '</span>')
    .replace(/\x1b\[39m/g, '</span>')
    .replace(/\x1b\[0m/g, '</span>');
}

describe('ansiToHtml formatting & XSS sanitization', () => {
  it('converts ANSI color escape codes to styled HTML spans', () => {
    const raw = '\x1b[32mOK\x1b[0m \x1b[31mFAIL\x1b[0m \x1b[33mWARN\x1b[0m';
    const html = ansiToHtml(raw);
    expect(html).toBe('<span class="t-ok">OK</span> <span class="t-err">FAIL</span> <span class="t-warn">WARN</span>');
  });

  it('converts info, dim, and bold formatting', () => {
    const raw = '\x1b[36mINFO\x1b[39m \x1b[90mDIM\x1b[39m \x1b[1mBOLD\x1b[22m';
    const html = ansiToHtml(raw);
    expect(html).toBe('<span class="t-info">INFO</span> <span class="t-dim">DIM</span> <span class="t-bold">BOLD</span>');
  });

  it('escapes raw HTML tags to prevent XSS script injection', () => {
    const malicious = '\x1b[32m<script>alert("xss")</script>\x1b[0m';
    const html = ansiToHtml(malicious);
    expect(html).not.toContain('<script>');
    expect(html).toBe('<span class="t-ok">&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;</span>');
  });

  it('handles plain unformatted text cleanly', () => {
    const plain = 'Hello world 123';
    expect(ansiToHtml(plain)).toBe('Hello world 123');
  });
});
