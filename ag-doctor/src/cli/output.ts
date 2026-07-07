/**
 * Colored terminal output. Zero dependencies — uses ANSI escape codes
 * with TTY auto-detection.
 */

const isTTY = Boolean(process.stdout.isTTY);

function wrap(open: string, close: string) {
  return (s: string | number) => (isTTY ? `${open}${s}${close}` : String(s));
}

export const c = {
  reset: wrap('\x1b[0m', '\x1b[0m'),
  bold: wrap('\x1b[1m', '\x1b[22m'),
  dim: wrap('\x1b[2m', '\x1b[22m'),
  red: wrap('\x1b[31m', '\x1b[39m'),
  green: wrap('\x1b[32m', '\x1b[39m'),
  yellow: wrap('\x1b[33m', '\x1b[39m'),
  blue: wrap('\x1b[34m', '\x1b[39m'),
  magenta: wrap('\x1b[35m', '\x1b[39m'),
  cyan: wrap('\x1b[36m', '\x1b[39m'),
  white: wrap('\x1b[37m', '\x1b[39m'),
  gray: wrap('\x1b[90m', '\x1b[39m'),
  bgRed: wrap('\x1b[41m', '\x1b[49m'),
  bgGreen: wrap('\x1b[42m', '\x1b[49m'),
  bgYellow: wrap('\x1b[43m', '\x1b[49m'),
};

export const ICONS = {
  ok: isTTY ? '✔' : '[OK]',
  warn: isTTY ? '⚠' : '[!]',
  err: isTTY ? '✖' : '[X]',
  info: isTTY ? 'ℹ' : '[i]',
  arrow: isTTY ? '➜' : '->',
  bullet: isTTY ? '•' : '*',
};

export function header(title: string): void {
  const bar = '═'.repeat(Math.max(40, title.length + 4));
  console.log('\n' + c.cyan(bar));
  console.log(c.bold(c.cyan(`  ${title}`)));
  console.log(c.cyan(bar) + '\n');
}

export function subheader(title: string): void {
  console.log('\n' + c.bold(c.white(title)));
  console.log(c.gray('─'.repeat(title.length)));
}

export function ok(msg: string): void {
  console.log(`${c.green(ICONS.ok)} ${msg}`);
}

export function warn(msg: string): void {
  console.log(`${c.yellow(ICONS.warn)} ${msg}`);
}

export function error(msg: string): void {
  console.log(`${c.red(ICONS.err)} ${msg}`);
}

export function info(msg: string): void {
  console.log(`${c.blue(ICONS.info)} ${msg}`);
}

export function dim(msg: string): void {
  console.log(c.gray(msg));
}

export function table(rows: Array<[string, string]>): void {
  const w1 = Math.max(...rows.map((r) => r[0].length));
  for (const [k, v] of rows) {
    console.log(`  ${c.bold(k.padEnd(w1))}  ${v}`);
  }
}

export function json(data: unknown): void {
  console.log(JSON.stringify(data, null, 2));
}
