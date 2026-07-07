/**
 * `ag-doctor models list` — list configured custom models.
 */
import type { CommandContext } from '../../types';
import { loadCustomModels, looksEncrypted } from '../../core/custom-models';
import { getCustomModelsPath } from '../../core/paths';
import { c, header, ok, info } from '../../cli/output';

function maskKey(k?: string): string {
  if (!k) return '(none)';
  if (k.length <= 8) return '***';
  return `${k.slice(0, 3)}...${k.slice(-4)}`;
}

export function runModelsList(ctx: CommandContext): number {
  if (!ctx.json) header('Custom models');
  const file = loadCustomModels();
  const encrypted = looksEncrypted();

  if (ctx.json) {
    console.log(JSON.stringify({ path: getCustomModelsPath(), encrypted, models: file.models }, null, 2));
    return 0;
  }

  info(`File: ${getCustomModelsPath()}`);
  info(`Encryption: ${encrypted ? c.green('yes') : c.yellow('no')}`);
  console.log('');

  if (file.models.length === 0) {
    info('No models configured. Run `ag-doctor models add` to create one.');
    return 0;
  }

  const rows: Array<[string, string]> = [];
  for (const m of file.models) {
    rows.push([c.bold(m.name), `${m.provider} → ${m.apiUrl}`]);
    rows.push(['', `${c.gray('external:')} ${m.externalModelName}  ${c.gray('key:')} ${maskKey(m.apiKey)}`]);
  }
  for (const [k, v] of rows) {
    console.log(`  ${k.padEnd(40)} ${v}`);
  }
  console.log('');
  ok(`${file.models.length} model(s)`);
  return 0;
}
