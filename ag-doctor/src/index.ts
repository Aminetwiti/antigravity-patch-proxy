#!/usr/bin/env node
/**
 * ag-doctor — entry point.
 * Routes argv to the right command module.
 */
import { parseArgs } from './cli/parser';
import type { CommandContext } from './types';
import { c } from './cli/output';

import { runDoctor } from './commands/doctor';
import { runCheck } from './commands/check';
import { runRepair } from './commands/repair';
import { runModelsList } from './commands/models/list';
import { runModelsAdd } from './commands/models/add';
import { runModelsRemove } from './commands/models/remove';
import { runModelsTest } from './commands/models/test';
import { runPatchStatus } from './commands/patch/status';
import { runPatchApply } from './commands/patch/apply';
import { runPatchRestore } from './commands/patch/restore';
import { runLogs } from './commands/logs';
import { runUpdate } from './commands/update';
import { runInfo } from './commands/info';

const USAGE = `ag-doctor — Antigravity diagnostic & management CLI

Usage:
  ag-doctor [command] [options]

Commands:
  (default)              Run full diagnostic (alias for 'doctor')
  doctor                 Full diagnostic with details
  check                  Quick health check (exit code only)
  repair [--yes]         Auto-fix detected issues
  models list            List configured custom models
  models add             Interactive model creation
  models remove <name>   Delete a model
  models test [name]     Test connectivity for one or all models
  patch status           Show binary patch state
  patch apply            Apply the binary patch (creates backup)
  patch restore          Restore language_server from backup
  logs [-f] [-n N]       Show language_server logs (tail/follow)
  update                 Re-run the parent deploy script
  info                   System & environment information
  help                   Show this help

Options:
  --json                 Machine-readable JSON output
  --verbose, -v          Verbose output
  --yes, -y              Auto-confirm prompts
  --follow, -f           Follow log output (logs command)
  --lines N, -n N        Number of lines (logs command)

Exit codes:
  0  OK
  1  Warning(s)
  2  Error(s)
`;

function buildContext(parsed: ReturnType<typeof parseArgs>): CommandContext {
  return {
    json: Boolean(parsed.options.json),
    verbose: Boolean(parsed.options.verbose || parsed.options.v),
    yes: Boolean(parsed.options.yes || parsed.options.y),
    cwd: process.cwd(),
  };
}

async function main(argv: string[]): Promise<number> {
  const parsed = parseArgs(argv);
  const ctx = buildContext(parsed);
  const [cmd, sub, ...rest] = parsed.command;

  try {
    switch (cmd) {
      case undefined:
      case 'doctor':
        return await runDoctor(ctx);
      case 'check':
        return await runCheck(ctx);
      case 'repair':
        return await runRepair(ctx);
      case 'models':
        if (sub === 'list' || sub === 'ls') return runModelsList(ctx);
        if (sub === 'add') return await runModelsAdd(ctx);
        if (sub === 'remove' || sub === 'rm') return await runModelsRemove(ctx, rest[0]);
        if (sub === 'test') return await runModelsTest(ctx, rest[0]);
        console.error(`Unknown models subcommand: ${sub}`);
        console.error(USAGE);
        return 2;
      case 'patch':
        if (sub === 'status') return runPatchStatus(ctx);
        if (sub === 'apply') return await runPatchApply(ctx);
        if (sub === 'restore') return await runPatchRestore(ctx);
        console.error(`Unknown patch subcommand: ${sub}`);
        console.error(USAGE);
        return 2;
      case 'logs':
        return await runLogs(ctx, {
          follow: Boolean(parsed.options.follow || parsed.options.f),
          lines: Number(parsed.options.lines || parsed.options.n) || 50,
        });
      case 'update':
        return await runUpdate(ctx);
      case 'info':
        return runInfo(ctx);
      case 'help':
      case '--help':
      case '-h':
        console.log(USAGE);
        return 0;
      case 'version':
      case '--version':
      case '-v':
        const pkg = require('../package.json');
        console.log(`ag-doctor v${pkg.version}`);
        return 0;
      default:
        console.error(`Unknown command: ${cmd}`);
        console.error(USAGE);
        return 2;
    }
  } catch (e) {
    console.error(c.red(`ag-doctor: ${(e as Error).message}`));
    if (ctx.verbose) console.error((e as Error).stack);
    return 2;
  }
}

main(process.argv.slice(2)).then(
  (code) => process.exit(code),
  (err) => {
    console.error(c.red('Fatal:'), err);
    process.exit(2);
  },
);
