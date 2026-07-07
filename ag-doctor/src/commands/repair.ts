/**
 * `ag-doctor repair [--auto]` — automatically fix detected issues.
 *
 * Currently supports:
 *  - Re-applying the binary patch (when not applied)
 *  - Killing Antigravity processes holding port 50999
 *  - Rebuilding dist/ if missing (requires the patch repo on disk)
 */
import type { CommandContext } from '../types';
import { checkPatch } from '../checks/patch';
import { applyPatch } from '../core/binary-patch';
import { isPortInUse, killAntigravityProcesses } from '../core/process';
import { ensureDataDir } from '../core/custom-models';
import { c, header, ok, warn, error, info } from '../cli/output';
import { confirm } from '../cli/prompts';
import { Spinner } from '../cli/spinner';

export async function runRepair(ctx: CommandContext): Promise<number> {
  header('ag-doctor — repair');
  const patch = checkPatch();
  const actions: string[] = [];

  // 1. Patch
  if (patch.data && !(patch.data as { applied: boolean }).applied) {
    actions.push('apply binary patch');
  }
  // 2. Port
  const portBusy = await isPortInUse(50999);
  if (portBusy) {
    actions.push('free port 50999 (kill Antigravity)');
  }
  // 3. Data dir
  ensureDataDir();

  if (actions.length === 0) {
    ok('Nothing to repair');
    return 0;
  }

  info('Planned actions:');
  for (const a of actions) console.log(`  ${c.cyan('•')} ${a}`);
  console.log('');

  if (!ctx.yes) {
    const ok2 = await confirm('Proceed?', false);
    if (!ok2) {
      warn('Aborted');
      return 1;
    }
  }

  for (const a of actions) {
    const sp = new Spinner(a);
    sp.start();
    try {
      if (a.startsWith('apply binary patch')) {
        const r = applyPatch();
        if (!r.ok) {
          sp.fail(r.message);
          return 2;
        }
        sp.succeed(r.message);
      } else if (a.startsWith('free port 50999')) {
        const r = await killAntigravityProcesses();
        sp.succeed(`Killed ${r.killed} process(es)`);
      }
    } catch (e) {
      sp.fail((e as Error).message);
      return 2;
    }
  }

  ok('Repair complete');
  return 0;
}
