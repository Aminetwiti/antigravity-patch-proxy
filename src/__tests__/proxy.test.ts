import { describe, it, expect, vi } from 'vitest';
import * as path from 'path';
import { generateModelPlaceholderId, toSlug, parseRetryAfter } from '../proxy';

// We need to mock the external dependencies that proxy.ts imports at module level
vi.mock('electron', () => ({
  app: {
    getPath: vi.fn((name: string) => {
      if (name === 'home') return '/mock/home';
      return '/mock/' + name;
    }),
  },
  safeStorage: {
    isEncryptionAvailable: vi.fn(() => false),
    encryptString: vi.fn((s: string) => Buffer.from(s)),
    decryptString: vi.fn((b: Buffer) => b.toString()),
  },
}));

// Mock cryptoStore using the same path proxy.ts uses (./cryptoStore)
// Vitest matches mocks by the resolved module path, not the specifier string
vi.mock('./cryptoStore', () => ({
  isEncryptionAvailable: vi.fn(() => false),
  encryptString: vi.fn((s: string) => s),
  decryptString: vi.fn((s: string) => s),
  encryptModels: vi.fn((models: unknown[]) => models),
  decryptModels: vi.fn((models: unknown[]) => models),
  backupFile: vi.fn(),
}));

vi.mock('electron-log', () => ({
  default: {
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
  },
}));

// ─── Tests ────────────────────────────────────────────────────────────────

describe('generateModelPlaceholderId', () => {
  it('generates deterministic IDs for the same input', () => {
    const id1 = generateModelPlaceholderId({ name: 'gpt-4o', displayName: 'GPT-4o' });
    const id2 = generateModelPlaceholderId({ name: 'gpt-4o', displayName: 'GPT-4o' });
    expect(id1).toBe(id2);
  });

  it('produces IDs in the MODEL_PLACEHOLDER_M format', () => {
    const id = generateModelPlaceholderId({ name: 'gpt-4o' });
    expect(id).toMatch(/^MODEL_PLACEHOLDER_M\d+$/);
  });

  it('produces different IDs for different models', () => {
    const id1 = generateModelPlaceholderId({ name: 'gpt-4o' });
    const id2 = generateModelPlaceholderId({ name: 'claude-3-5-sonnet' });
    expect(id1).not.toBe(id2);
  });

  it('uses displayName over name', () => {
    const id1 = generateModelPlaceholderId({ name: 'models/gpt-4o', displayName: 'My GPT-4o' });
    const id2 = generateModelPlaceholderId({ name: 'models/gpt-4o', displayName: 'Different Name' });
    expect(id1).not.toBe(id2);
  });

  it('falls back to name when displayName is missing', () => {
    const id = generateModelPlaceholderId({ name: 'gpt-4o' });
    expect(id).toBeTruthy();
  });

  it('falls back to "custom-model" when both name and displayName missing', () => {
    const id = generateModelPlaceholderId({});
    expect(id).toBeTruthy();
  });

  it('placeholder number is within range [400, 599]', () => {
    const id = generateModelPlaceholderId({ name: 'gpt-4o' });
    const num = parseInt(id.replace('MODEL_PLACEHOLDER_M', ''), 10);
    expect(num).toBeGreaterThanOrEqual(400);
    expect(num).toBeLessThanOrEqual(599);
  });

  it('lowercases the input before hashing', () => {
    const id1 = generateModelPlaceholderId({ name: 'GPT-4O' });
    const id2 = generateModelPlaceholderId({ name: 'gpt-4o' });
    expect(id1).toBe(id2);
  });
});

describe('toSlug', () => {
  it('prefixes with "custom-"', () => {
    const slug = toSlug({ name: 'gpt-4o' });
    expect(slug).toMatch(/^custom-/);
  });

  it('removes "models/" prefix from externalModelName', () => {
    const slug = toSlug({ externalModelName: 'models/gpt-4o' });
    expect(slug).toBe('custom-gpt-4o');
  });

  it('replaces non-alphanumeric chars with hyphens', () => {
    const slug = toSlug({ name: 'GPT 4o (Latest)' });
    expect(slug).toBe('custom-gpt-4o-latest');
  });

  it('removes leading and trailing hyphens', () => {
    const slug = toSlug({ name: '--test--' });
    expect(slug).toBe('custom-test');
  });

  it('lowercases the result', () => {
    const slug = toSlug({ name: 'GPT-4O' });
    expect(slug).toBe('custom-gpt-4o');
  });

  it('uses externalModelName over name', () => {
    const slug = toSlug({ name: 'gpt-4o', externalModelName: 'openai/gpt-4o' });
    expect(slug).toBe('custom-openai-gpt-4o');
  });

  it('handles OpenRouter model format (provider/model)', () => {
    const slug = toSlug({ externalModelName: 'openai/gpt-4o' });
    expect(slug).toBe('custom-openai-gpt-4o');
  });
});

describe('parseRetryAfter', () => {
  it('returns 0 when no Retry-After header', () => {
    expect(parseRetryAfter({})).toBe(0);
  });

  it('parses delta-seconds format (integer)', () => {
    expect(parseRetryAfter({ 'retry-after': '120' })).toBe(120_000);
  });

  it('parses delta-seconds with whitespace', () => {
    expect(parseRetryAfter({ 'retry-after': '  60  ' })).toBe(60_000);
  });

  it('returns 0 for negative delta-seconds', () => {
    expect(parseRetryAfter({ 'retry-after': '-5' })).toBe(0);
  });

  it('parses HTTP-date format for future date', () => {
    const futureDate = new Date(Date.now() + 60_000).toUTCString();
    const result = parseRetryAfter({ 'retry-after': futureDate });
    expect(result).toBeGreaterThan(0);
    expect(result).toBeLessThanOrEqual(61_000); // allow 1s tolerance
  });

  it('returns 0 for past HTTP-date', () => {
    const pastDate = new Date(Date.now() - 60_000).toUTCString();
    expect(parseRetryAfter({ 'retry-after': pastDate })).toBe(0);
  });

  it('handles array value (takes first element)', () => {
    expect(parseRetryAfter({ 'retry-after': ['30', '60'] })).toBe(30_000);
  });

  it('returns 0 for invalid string', () => {
    expect(parseRetryAfter({ 'retry-after': 'not-a-number' })).toBe(0);
  });

  it('returns 0 for empty string', () => {
    expect(parseRetryAfter({ 'retry-after': '' })).toBe(0);
  });
});
