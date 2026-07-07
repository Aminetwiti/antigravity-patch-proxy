/**
 * Custom models check — validates custom_models.json structure.
 */
import type { CheckResult } from '../types';
import {
  loadCustomModels,
  validateCustomModels,
  looksEncrypted,
} from '../core/custom-models';
import { getCustomModelsPath } from '../core/paths';
import fs from 'fs';

export function checkModels(): CheckResult {
  const path = getCustomModelsPath();
  if (!fs.existsSync(path)) {
    return {
      id: 'models',
      title: 'Custom models',
      status: 'info',
      message: 'No custom_models.json found (no models configured yet)',
      details: path,
      fixable: false,
    };
  }
  const file = loadCustomModels();
  const issues = validateCustomModels(file);
  const encrypted = looksEncrypted();
  if (issues.length > 0) {
    return {
      id: 'models',
      title: 'Custom models',
      status: 'error',
      message: `${issues.length} validation issue(s) in ${file.models.length} model(s)`,
      details: issues.map((i) => `  ${i.model}.${i.field}: ${i.message}`).join('\n'),
      fixable: false,
      data: { count: file.models.length, issues, encrypted },
    };
  }
  return {
    id: 'models',
    title: 'Custom models',
    status: 'ok',
    message: `${file.models.length} model(s) configured${encrypted ? ' (encrypted)' : ''}`,
    data: { count: file.models.length, encrypted, models: file.models },
  };
}
