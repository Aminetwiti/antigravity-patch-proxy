/**
 * `ag-doctor patch restore` — restore the language_server binary from backup.
 */
import type { CommandContext } from '../../types';
import { restorePatch } from '../../core/binary-patch';
import { confirm } from '../../cli/prompts';
import { ok, error, warn } from '../../cli/output';

export async function runPatchRestore(ctx: CommandContext): Promise<number> {
  if (!ctx.yes) {
    const ok2 = await confirm('Restore language_server from backup? This will undo the patch.', false);
    if (!ok2) {
      warn('Aborted');
      return 1;
    }
  }
  const r = restorePatch();
  if (!r.ok) {
    error(r.message);
    return 2;
  }
  ok(r.message);
  return 0;
}
