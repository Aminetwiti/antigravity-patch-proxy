/** Mock for electron-log */
const log = {
  info: (..._args: unknown[]) => {},
  warn: (..._args: unknown[]) => {},
  error: (..._args: unknown[]) => {},
  debug: (..._args: unknown[]) => {},
  verbose: (..._args: unknown[]) => {},
};

export default log;
export const info = log.info;
export const warn = log.warn;
export const error = log.error;
export const debug = log.debug;
