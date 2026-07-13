/**
 * Unit tests for `error-decoder.ts` (pure helpers).
 * Run with: `npx vitest run src/renderer/error-decoder.test.ts`
 *
 * These tests cover the pure helpers (formatBytes + decodeError) extracted
 * from `app.ts`. They are intentionally dependency-free so they can run in
 * any Node environment.
 */

import { describe, expect, it } from 'vitest';
import { decodeError, formatBytes } from './error-decoder';

describe('formatBytes', () => {
  it('returns "0 B" for 0', () => {
    expect(formatBytes(0)).toBe('0 B');
  });

  it('returns "0 B" for negative numbers', () => {
    expect(formatBytes(-100)).toBe('0 B');
  });

  it('returns "0 B" for NaN and Infinity', () => {
    expect(formatBytes(Number.NaN)).toBe('0 B');
    expect(formatBytes(Number.POSITIVE_INFINITY)).toBe('0 B');
  });

  it('formats 1024 as "1.00 KB"', () => {
    expect(formatBytes(1024)).toBe('1.00 KB');
  });

  it('formats 1_572_864 as "1.50 MB"', () => {
    expect(formatBytes(1_572_864)).toBe('1.50 MB');
  });

  it('formats sub-10 values with 2 decimals', () => {
    expect(formatBytes(5 * 1024)).toBe('5.00 KB');
  });

  it('formats sub-100 values with 1 decimal', () => {
    expect(formatBytes(52 * 1024)).toBe('52.0 KB');
  });

  it('formats large values with 0 decimals', () => {
    expect(formatBytes(500 * 1024)).toBe('500 KB');
  });
});

describe('decodeError', () => {
  it('matches the MITM proxy unreachable pattern', () => {
    const r = decodeError('Error: listen EADDRNOTAVAIL 127.0.0.1:443');
    expect(r.matched).toBe(true);
    expect(r.pattern).toContain('MITM');
    expect(r.action).toBe('open-mitm-view');
  });

  it('does NOT match a bare port-443 ref without proxy context (no false positive)', () => {
    const r = decodeError('Outbound request to https://example.com:443 succeeded');
    expect(r.matched).toBe(false);
    expect(r.action).toBe('none');
  });

  it('matches ECONNREFUSED on 127.0.0.1:443', () => {
    const r = decodeError('connect ECONNREFUSED 127.0.0.1:443');
    expect(r.matched).toBe(true);
    expect(r.action).toBe('open-mitm-view');
  });

  it('matches "Cannot find module" and suggests run-doctor', () => {
    const r = decodeError('Cannot find module "foo"');
    expect(r.matched).toBe(true);
    expect(r.action).toBe('run-doctor');
  });

  it('matches MODULE_NOT_FOUND', () => {
    const r = decodeError('Error: MODULE_NOT_FOUND');
    expect(r.action).toBe('run-doctor');
  });

  it('matches "Antigravity crash on launch" with show-retry-toast', () => {
    const r = decodeError('Antigravity crash on launch detected');
    expect(r.matched).toBe(true);
    expect(r.action).toBe('show-retry-toast');
  });

  it('matches EADDRINUSE with run-doctor', () => {
    const r = decodeError('Error: listen EADDRINUSE: address already in use :::50999');
    expect(r.matched).toBe(true);
    expect(r.action).toBe('run-doctor');
    expect(r.pattern).toContain('EADDRINUSE');
  });

  it('returns matched=false for unrelated errors', () => {
    const r = decodeError('Some completely random unrelated error');
    expect(r.matched).toBe(false);
    expect(r.action).toBe('none');
  });

  it('falls back to stdout when stderr is empty', () => {
    const r = decodeError('', 'Antigravity crash on startup');
    expect(r.matched).toBe(true);
    expect(r.action).toBe('show-retry-toast');
  });

  it('handles empty inputs gracefully', () => {
    const r = decodeError('', '');
    expect(r.matched).toBe(false);
    expect(r.pattern).toBe('');
    expect(r.hint).toBe('');
    expect(r.action).toBe('none');
  });
});
