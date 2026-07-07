import { describe, it, expect } from 'vitest';
import {
  generateModelPlaceholderId,
  toSlug,
  PLACEHOLDER_ID_BASE,
  PLACEHOLDER_ID_RANGE,
} from '../proxy/idGenerator';
import type { CustomModel } from '../proxy/types';

const baseModel: CustomModel = {
  name: 'models/gpt-4o',
  displayName: 'GPT-4o',
  provider: 'openai',
  apiKey: 'sk-test',
  apiUrl: 'https://api.openai.com/v1',
  externalModelName: 'gpt-4o',
};

describe('generateModelPlaceholderId', () => {
  it('produces a deterministic ID for the same input', () => {
    const id1 = generateModelPlaceholderId(baseModel);
    const id2 = generateModelPlaceholderId(baseModel);
    expect(id1).toBe(id2);
  });

  it('starts with MODEL_PLACEHOLDER_M prefix', () => {
    const id = generateModelPlaceholderId(baseModel);
    expect(id.startsWith('MODEL_PLACEHOLDER_M')).toBe(true);
  });

  it('produces IDs within the configured range', () => {
    for (let i = 0; i < 50; i++) {
      const model = {
        ...baseModel,
        displayName: `Test Model ${i}`,
      };
      const id = generateModelPlaceholderId(model);
      const numStr = id.replace('MODEL_PLACEHOLDER_M', '');
      const num = parseInt(numStr, 10);
      expect(num).toBeGreaterThanOrEqual(PLACEHOLDER_ID_BASE);
      expect(num).toBeLessThan(PLACEHOLDER_ID_BASE + PLACEHOLDER_ID_RANGE);
    }
  });

  it('produces different IDs for different display names', () => {
    const id1 = generateModelPlaceholderId({ ...baseModel, displayName: 'Model A' });
    const id2 = generateModelPlaceholderId({ ...baseModel, displayName: 'Model B' });
    expect(id1).not.toBe(id2);
  });

  it('falls back to name when displayName is missing', () => {
    const id1 = generateModelPlaceholderId({ ...baseModel, displayName: '', name: 'fallback-name' });
    const id2 = generateModelPlaceholderId({ ...baseModel, displayName: 'fallback-name' });
    expect(id1).toBe(id2);
  });

  it('uses "custom-model" as ultimate fallback', () => {
    const id = generateModelPlaceholderId({
      ...baseModel,
      displayName: '',
      name: '',
    });
    expect(id).toMatch(/^MODEL_PLACEHOLDER_M\d+$/);
  });

  it('is case-insensitive (lowercases input)', () => {
    const id1 = generateModelPlaceholderId({ ...baseModel, displayName: 'GPT-4O' });
    const id2 = generateModelPlaceholderId({ ...baseModel, displayName: 'gpt-4o' });
    expect(id1).toBe(id2);
  });

  it('handles unicode characters', () => {
    const id = generateModelPlaceholderId({ ...baseModel, displayName: 'Modèle Français 🤖' });
    expect(id).toMatch(/^MODEL_PLACEHOLDER_M\d+$/);
  });

  it('handles very long display names', () => {
    const longName = 'A'.repeat(1000);
    const id = generateModelPlaceholderId({ ...baseModel, displayName: longName });
    expect(id).toMatch(/^MODEL_PLACEHOLDER_M\d+$/);
  });

  it('produces integer hash (no overflow)', () => {
    for (let i = 0; i < 100; i++) {
      const id = generateModelPlaceholderId({ ...baseModel, displayName: `model-${i}` });
      const numStr = id.replace('MODEL_PLACEHOLDER_M', '');
      expect(Number.isInteger(parseInt(numStr, 10))).toBe(true);
    }
  });
});

describe('toSlug', () => {
  it('prepends "custom-" prefix', () => {
    expect(toSlug(baseModel)).toMatch(/^custom-/);
  });

  it('converts to lowercase', () => {
    const slug = toSlug({ ...baseModel, externalModelName: 'GPT-4O' });
    expect(slug).toBe('custom-gpt-4o');
  });

  it('replaces special characters with hyphens', () => {
    const slug = toSlug({ ...baseModel, externalModelName: 'gpt 4o turbo' });
    expect(slug).toBe('custom-gpt-4o-turbo');
  });

  it('removes "models/" prefix', () => {
    const slug = toSlug({ ...baseModel, externalModelName: 'models/gpt-4o' });
    expect(slug).toBe('custom-gpt-4o');
  });

  it('strips leading and trailing hyphens', () => {
    const slug = toSlug({ ...baseModel, externalModelName: '---gpt-4o---' });
    expect(slug).toBe('custom-gpt-4o');
  });

  it('handles underscores', () => {
    const slug = toSlug({ ...baseModel, externalModelName: 'gpt_4o' });
    expect(slug).toBe('custom-gpt-4o');
  });

  it('handles dots', () => {
    const slug = toSlug({ ...baseModel, externalModelName: 'gpt-4.0' });
    expect(slug).toBe('custom-gpt-4-0');
  });

  it('falls back to name when externalModelName is missing', () => {
    const slug = toSlug({ ...baseModel, externalModelName: '', name: 'fallback-model' });
    expect(slug).toBe('custom-fallback-model');
  });

  it('produces URL-safe output', () => {
    const slug = toSlug({ ...baseModel, externalModelName: 'GPT-4o (turbo) [preview]!' });
    expect(slug).toMatch(/^[a-z0-9-]+$/);
  });

  it('handles empty strings', () => {
    const slug = toSlug({ ...baseModel, externalModelName: '', name: '' });
    expect(slug).toBe('custom-');
  });
});

describe('PLACEHOLDER_ID_BASE and PLACEHOLDER_ID_RANGE', () => {
  it('exports valid constants', () => {
    expect(typeof PLACEHOLDER_ID_BASE).toBe('number');
    expect(typeof PLACEHOLDER_ID_RANGE).toBe('number');
    expect(PLACEHOLDER_ID_BASE).toBeGreaterThan(0);
    expect(PLACEHOLDER_ID_RANGE).toBeGreaterThan(0);
  });
});
