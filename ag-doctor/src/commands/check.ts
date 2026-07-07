/**
 * `ag-doctor check` — fast health check (subset of doctor, exit-code only).
 */
import type { CommandContext } from '../types';
import { checkEnvironment } from '../checks/environment';
import { checkInstallation } from '../checks/installation';
import { checkPatch } from '../checks/patch';
import { checkProxy } from '../checks/proxy';
import { checkModels } from '../checks/models';

export async function runCheck(ctx: CommandContext): Promise<number> {
  const results = await Promise.all([
    Promise.resolve(checkEnvironment()),
    Promise.resolve(checkInstallation()),
    Promise.resolve(checkPatch()),
    checkProxy(),
    Promise.resolve(checkModels()),
  ]);

  if (ctx.json) {
    console.log(JSON.stringify(results, null, 2));
  } else {
    for (const r of results) {
      const tag = r.status.toUpperCase().padEnd(5);
      console.log(`[${tag}] ${r.title}: ${r.message}`);
    }
  }

  const errors = results.filter((r) => r.status === 'error').length;
  const warns = results.filter((r) => r.status === 'warn').length;
  return errors > 0 ? 2 : warns > 0 ? 1 : 0;
}
