/**
 * Lightweight structured logger facade (Sprint 1, TODO-009).
 *
 * Goals:
 *  - Provide a single, mockable entry point for `console.log/warn/error` style
 *    output across the codebase.
 *  - Allow scoping (e.g. [Proxy], [IPC], [Translator]) so logs are easy to
 *    filter in the terminal / `electron-log` aggregator.
 *  - Stay zero-dep: just wraps `console.*` with a tagged prefix and JSON
 *    payload for structured logs.
 *  - Be safe to call from anywhere (main, preload-shim, proxy).
 */

/** Severity levels supported by the logger. */
export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

/** A simple structured logger. */
export interface Logger {
  debug: (...args: unknown[]) => void;
  info: (...args: unknown[]) => void;
  warn: (...args: unknown[]) => void;
  error: (...args: unknown[]) => void;
  child: (subScope: string) => Logger;
}

const LEVEL_PREFIX: Record<LogLevel, string> = {
  debug: 'DEBUG',
  info: 'INFO',
  warn: 'WARN',
  error: 'ERROR',
};

function ts(): string {
  return new Date().toISOString();
}

function emit(level: LogLevel, scope: string, args: unknown[]): void {
  const prefix = `[${scope}]`;
  const head = `${ts()} ${LEVEL_PREFIX[level]} ${prefix}`;
  const fn =
    level === 'error'
      ? console.error
      : level === 'warn'
        ? console.warn
        : level === 'info'
          ? console.info
          : console.debug;
  if (args.length === 1 && args[0] && typeof args[0] === 'object') {
    fn(head, args[0]);
  } else {
    fn(head, ...args);
  }
}

/**
 * Create a logger with the given scope, e.g. `createLogger('Proxy')`.
 *
 * Use `.child('Translator')` to compose nested scopes, e.g.
 * `createLogger('Proxy').child('OpenAI')` will tag with `[Proxy.OpenAI]`.
 *
 * @example
 * const log = createLogger('Proxy');
 * log.info('Listening on', 443);
 * log.child('OpenAI').warn('translate mismatch', { model: 'gpt-4o' });
 */
export function createLogger(scope: string): Logger {
  return makeLogger(scope);
}

function makeLogger(scope: string): Logger {
  return {
    debug: (...args) => emit('debug', scope, args),
    info: (...args) => emit('info', scope, args),
    warn: (...args) => emit('warn', scope, args),
    error: (...args) => emit('error', scope, args),
    child: (subScope) => makeLogger(`${scope}.${subScope}`),
  };
}

/**
 * Default scope-less logger — useful at the top of small helpers.
 */
export const logger: Logger = createLogger('App');
