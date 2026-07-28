import { describe, expect, it } from 'vitest';

/**
 * Unit tests for features.ts proxy monitor and uptime formatting primitives.
 */

function formatUptimeSec(sec?: number): string {
  if (typeof sec !== 'number' || !isFinite(sec) || sec < 0) return '—';
  const s = Math.floor(sec);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const ss = s % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${ss}s`;
  return `${ss}s`;
}

function getLatencyClass(latencyMs?: number): string {
  if (typeof latencyMs !== 'number') return 'proxy-stat-value';
  if (latencyMs < 500) return 'proxy-stat-value ok';
  if (latencyMs > 1500) return 'proxy-stat-value err';
  return 'proxy-stat-value';
}

function computeSparkPoints(values: number[], width = 200, height = 40, maxPoints = 60): string {
  const buf = values.slice(-maxPoints);
  if (buf.length === 0) return '';
  const max = Math.max(50, ...buf);
  const min = Math.min(0, ...buf);
  const range = Math.max(1, max - min);
  return buf
    .map((v, i) => {
      const x = (i / Math.max(1, maxPoints - 1)) * width;
      const y = height - ((v - min) / range) * height;
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .join(' ');
}

describe('features.ts formatUptimeSec', () => {
  it('formats invalid or missing uptime values as dash', () => {
    expect(formatUptimeSec(undefined)).toBe('—');
    expect(formatUptimeSec(-10)).toBe('—');
    expect(formatUptimeSec(NaN)).toBe('—');
    expect(formatUptimeSec(Infinity)).toBe('—');
  });

  it('formats seconds-only uptime (< 60s)', () => {
    expect(formatUptimeSec(0)).toBe('0s');
    expect(formatUptimeSec(45)).toBe('45s');
    expect(formatUptimeSec(59.9)).toBe('59s');
  });

  it('formats minutes and seconds uptime (60s to 3599s)', () => {
    expect(formatUptimeSec(60)).toBe('1m 0s');
    expect(formatUptimeSec(185)).toBe('3m 5s');
    expect(formatUptimeSec(3599)).toBe('59m 59s');
  });

  it('formats hours and minutes uptime (>= 3600s)', () => {
    expect(formatUptimeSec(3600)).toBe('1h 0m');
    expect(formatUptimeSec(3665)).toBe('1h 1m');
    expect(formatUptimeSec(86400)).toBe('24h 0m');
  });
});

describe('features.ts getLatencyClass classification', () => {
  it('classifies latency < 500ms as ok', () => {
    expect(getLatencyClass(50)).toBe('proxy-stat-value ok');
    expect(getLatencyClass(499)).toBe('proxy-stat-value ok');
  });

  it('classifies latency between 500ms and 1500ms as default', () => {
    expect(getLatencyClass(500)).toBe('proxy-stat-value');
    expect(getLatencyClass(1000)).toBe('proxy-stat-value');
    expect(getLatencyClass(1500)).toBe('proxy-stat-value');
  });

  it('classifies latency > 1500ms as error', () => {
    expect(getLatencyClass(1501)).toBe('proxy-stat-value err');
    expect(getLatencyClass(5000)).toBe('proxy-stat-value err');
  });

  it('returns default class when latency is undefined', () => {
    expect(getLatencyClass(undefined)).toBe('proxy-stat-value');
  });
});

describe('features.ts sparkline polyline SVG math', () => {
  it('generates scaled (x,y) polyline points array', () => {
    const pts = computeSparkPoints([0, 25, 50]);
    expect(pts).not.toBe('');
    const coords = pts.split(' ');
    expect(coords.length).toBe(3);
    // First point x=0.0
    expect(coords[0].startsWith('0.0,')).toBe(true);
  });

  it('returns empty string for empty buffer', () => {
    expect(computeSparkPoints([])).toBe('');
  });
});
