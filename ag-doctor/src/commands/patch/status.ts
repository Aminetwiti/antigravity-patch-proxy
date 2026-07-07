/**
 * `ag-doctor patch status` — show current patch state.
 */
import type { CommandContext } from '../../types';
import { getPatchStatus } from '../../core/binary-patch';
import { c, header, ok, warn, error, info } from '../../cli/output';

export function runPatchStatus(ctx: CommandContext): number {
  if (!ctx.json) header('Binary patch status');
  const s = getPatchStatus();
  if (ctx.json) {
    console.log(JSON.stringify(s, null, 2));
    return 0;
  }
  info(`Binary:   ${s.binaryPath ?? c.gray('(not found)')}`);
  info(`Exists:   ${s.exists ? c.green('yes') : c.red('no')}`);
  info(`Applied:  ${s.applied ? c.green('yes') : c.yellow('no')}`);
  info(`Backup:   ${s.backupExists ? c.green('yes') : c.gray('no')}`);
  console.log('');
  if (s.applied) ok('Patch is active');
  else if (s.exists) warn('Patch is NOT applied — run `ag-doctor patch apply`');
  else error('Binary not found');
  return s.applied ? 0 : 1;
}
