/**
 * `ag-doctor` / `ag-doctor doctor` — full diagnostic.
 */
import type { CommandContext } from '../types';
import { checkEnvironment } from '../checks/environment';
import { checkInstallation } from '../checks/installation';
import { checkPatch } from '../checks/patch';
import { checkProxy } from '../checks/proxy';
import { checkModels } from '../checks/models';
import { checkEncryption } from '../checks/encryption';
import { checkConnectivity } from '../checks/connectivity';
import { c, header, ICONS, ok, warn, error, info } from '../cli/output';

export async function runDoctor(ctx: CommandContext): Promise<number> {
  if (!ctx.json) header('ag-doctor — Antigravity diagnostic');

  const results = await Promise.all([
    Promise.resolve(checkEnvironment()),
    Promise.resolve(checkInstallation()),
    Promise.resolve(checkPatch()),
    checkProxy(),
    Promise.resolve(checkModels()),
    Promise.resolve(checkEncryption()),
    checkConnectivity(),
  ]);

  if (ctx.json) {
    console.log(JSON.stringify(results, null, 2));
  } else {
    for (const r of results) {
      const icon =
        r.status === 'ok'
          ? c.green(ICONS.ok)
          : r.status === 'warn'
            ? c.yellow(ICONS.warn)
            : r.status === 'error'
              ? c.red(ICONS.err)
              : c.blue(ICONS.info);
      console.log(`${icon} ${c.bold(r.title)}`);
      console.log(`    ${r.message}`);
      if (r.details && (ctx.verbose || r.status !== 'ok')) {
        console.log(c.gray(r.details.split('\n').join('\n    ')));
      }
      if (r.fixable) {
        console.log(`    ${c.cyan('→ fixable:')} run \`ag-doctor repair\``);
      }
    }
  }

  const errors = results.filter((r) => r.status === 'error').length;
  const warns = results.filter((r) => r.status === 'warn').length;
  const okCount = results.filter((r) => r.status === 'ok').length;

  if (!ctx.json) {
    console.log('');
    console.log(
      `  ${c.green(`${okCount} ok`)} · ${c.yellow(`${warns} warnings`)} · ${c.red(`${errors} errors`)}`,
    );
    console.log('');
    if (errors > 0) error(`${errors} check(s) failed`);
    else if (warns > 0) warn(`${warns} warning(s)`);
    else ok('All checks passed');
  }

  return errors > 0 ? 2 : warns > 0 ? 1 : 0;
}
