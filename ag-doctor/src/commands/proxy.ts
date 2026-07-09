/**
 * `ag-doctor proxy` — manage the standalone local proxy.
 *
 * Subcommands:
 *   status      Show proxy status
 *   start       Start the proxy in standalone mode
 *   stop        Stop the standalone proxy
 *   stub        Start the proxy stub
 */
import fs from 'fs';
import path from 'path';
import { spawn } from 'child_process';
import type { CommandContext } from '../types';
import { c, header, ok, warn, error, info } from '../cli/output';
import { loadConfig } from '../core/config';
import { isPortInUse, killAntigravityProcesses } from '../core/process';

const USAGE = `ag-doctor proxy — manage the standalone local proxy

Usage:
  ag-doctor proxy status          Show standalone proxy status
  ag-doctor proxy start           Start the real proxy in standalone mode
  ag-doctor proxy stub            Start the proxy stub (emergency fallback)
  ag-doctor proxy stop            Stop the standalone proxy
  ag-doctor proxy --help          Show this help
`;

export async function runProxy(ctx: CommandContext, sub: string | undefined): Promise<number> {
  if (!sub || sub === 'help' || sub === '--help' || sub === '-h') {
    console.log(USAGE);
    return 0;
  }

  switch (sub) {
    case 'status':
      return await runStatus(ctx);
    case 'start':
      return await runStart(ctx, 'standalone-proxy-runner.js');
    case 'stub':
      return await runStart(ctx, 'proxy-stub.js');
    case 'stop':
      return await runStop(ctx);
    default:
      error(`Unknown proxy subcommand: ${sub}`);
      console.log(USAGE);
      return 2;
  }
}

async function runStatus(ctx: CommandContext): Promise<number> {
  if (!ctx.json) header('Proxy status');
  const port = loadConfig().mitmPort;
  const inUse = await isPortInUse(port);
  
  if (ctx.json) {
    console.log(JSON.stringify({ port, running: inUse }));
  } else {
    if (inUse) {
      ok(`Proxy is running (port ${port} is bound)`);
    } else {
      warn(`Proxy is NOT running (port ${port} is free)`);
    }
  }
  return 0;
}

async function runStart(ctx: CommandContext, scriptName: string): Promise<number> {
  if (!ctx.json) header(`Proxy — start (${scriptName})`);
  const port = loadConfig().mitmPort;
  const inUse = await isPortInUse(port);
  
  if (inUse) {
    warn(`Port ${port} is already in use. You might need to run \`ag-doctor proxy stop\` first.`);
    return 1;
  }

  const scriptPath = path.join(__dirname, '..', '..', 'scripts', 'proxy', scriptName);
  if (!fs.existsSync(scriptPath)) {
    error(`Script not found: ${scriptPath}`);
    return 2;
  }

  info(`Spawning detached proxy process...`);
  
  // Detached spawn
  const proc = spawn(process.execPath, [scriptPath], {
    detached: true,
    stdio: 'ignore',
    windowsHide: true
  });
  
  proc.unref();

  ok(`Proxy started (PID ${proc.pid})`);
  return 0;
}

async function runStop(ctx: CommandContext): Promise<number> {
  if (!ctx.json) header('Proxy — stop');
  const port = loadConfig().mitmPort;
  const inUse = await isPortInUse(port);
  
  if (!inUse) {
    info(`Port ${port} is already free.`);
    return 0;
  }

  info(`Port ${port} is in use. Killing Antigravity and proxy processes...`);
  const r = await killAntigravityProcesses();
  if (r.killed > 0) {
    ok(`Killed ${r.killed} process(es). Proxy should be stopped.`);
  } else {
    warn('Could not cleanly kill processes holding the port. You may need to kill node.exe manually.');
  }

  return 0;
}
