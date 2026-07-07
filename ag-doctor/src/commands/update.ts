/**
 * `ag-doctor update` — pull latest, rebuild, redeploy.
 * This is a thin wrapper that runs the parent repo's deploy script.
 */
import path from 'path';
import { spawnInherit } from '../core/process';
import type { CommandContext } from '../types';
import { info, error } from '../cli/output';

export async function runUpdate(ctx: CommandContext): Promise<number> {
  const parent = path.resolve(__dirname, '..', '..', '..');
  info(`Running deploy from ${parent}...`);
  const platform = process.platform;
  try {
    let code = 0;
    if (platform === 'win32') {
      code = await spawnInherit('powershell', ['-ExecutionPolicy', 'Bypass', '-File', path.join(parent, 'deploy.ps1')]);
    } else if (platform === 'darwin') {
      code = await spawnInherit('bash', [path.join(parent, 'deploy.sh')]);
    } else {
      code = await spawnInherit('bash', [path.join(parent, 'deploy_linux.sh')]);
    }
    return code === 0 ? 0 : 2;
  } catch (e) {
    error(`Update failed: ${(e as Error).message}`);
    return 2;
  }
}
