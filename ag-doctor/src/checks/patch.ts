/**
 * Patch check — verifies the binary patch is applied.
 */
import type { CheckResult } from '../types';
import { getPatchStatus } from '../core/binary-patch';

export function checkPatch(): CheckResult {
  const status = getPatchStatus();
  if (!status.binaryPath) {
    return {
      id: 'patch',
      title: 'Binary patch',
      status: 'warn',
      message: 'Language server binary not found, skipping patch check',
      fixable: false,
    };
  }
  if (!status.exists) {
    return {
      id: 'patch',
      title: 'Binary patch',
      status: 'error',
      message: `Binary not found at ${status.binaryPath}`,
      fixable: false,
    };
  }
  if (status.applied) {
    return {
      id: 'patch',
      title: 'Binary patch',
      status: 'ok',
      message: 'Patched (Google URL → local proxy)',
      data: status,
    };
  }
  return {
    id: 'patch',
    title: 'Binary patch',
    status: 'warn',
    message: 'Not applied — custom models will not appear in the chat dropdown',
    details: 'Run `ag-doctor patch apply` to apply the patch',
    fixable: true,
    data: status,
  };
}
