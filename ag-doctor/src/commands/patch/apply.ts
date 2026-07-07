/**
 * `ag-doctor patch apply` — apply the binary patch.
 */
import type { CommandContext } from '../../types';
import { applyPatch } from '../../core/binary-patch';
import { killAntigravityProcesses } from '../../core/process';
import { confirm } from '../../cli/prompts';
import { ok, error, warn, info } from '../../cli/output';

export async function runPatchApply(ctx: CommandContext): Promise<number> {
  info('Applying binary patch...');
  // Safety: kill Antigravity first so we don't patch a running binary
  const procs = await killAntigravityProcesses();
  if (procs.killed > 0) {
    info(`Killed ${procs.killed} Antigravity process(es)`);
  }
  if (!ctx.yes) {
    const ok2 = await confirm('Apply patch to language_server binary?', false);
    if (!ok2) {
      warn('Aborted');
      return 1;
    }
  }
  const r = applyPatch();
  if (!r.ok) {
    error(r.message);
    return 2;
  }
  ok(r.message);
  return 0;
}
