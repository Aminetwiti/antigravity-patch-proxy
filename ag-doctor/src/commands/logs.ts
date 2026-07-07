/**
 * `ag-doctor logs [-f] [-n N]` — show language_server logs.
 */
import fs from 'fs';
import readline from 'readline';
import type { CommandContext } from '../types';
import { getLsLogPath } from '../core/paths';
import { error, info } from '../cli/output';

export async function runLogs(ctx: CommandContext, opts: { follow?: boolean; lines?: number }): Promise<number> {
  const path = getLsLogPath();
  if (!fs.existsSync(path)) {
    error(`Log file not found: ${path}`);
    return 1;
  }
  info(`Log: ${path}`);
  const lines = opts.lines ?? 50;

  if (!opts.follow) {
    const content = fs.readFileSync(path, 'utf-8');
    const tail = content.split(/\r?\n/).slice(-lines).join('\n');
    console.log(tail);
    return 0;
  }

  // Follow mode
  let pos = fs.statSync(path).size;
  console.log(`--- following ${path} (Ctrl+C to stop) ---`);
  const tick = setInterval(() => {
    fs.stat(path, (err, st) => {
      if (err) return;
      if (st.size > pos) {
        const stream = fs.createReadStream(path, { start: pos, end: st.size });
        stream.on('data', (chunk) => process.stdout.write(chunk));
        pos = st.size;
      }
    });
  }, 500);
  await new Promise<void>((resolve) => {
    process.on('SIGINT', () => {
      clearInterval(tick);
      resolve();
    });
  });
  return 0;
}
