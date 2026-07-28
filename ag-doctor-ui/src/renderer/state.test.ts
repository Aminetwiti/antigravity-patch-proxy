import { describe, expect, it } from 'vitest';

/**
 * Mirror of state.ts primitives for DOM-free Vitest verification.
 */
interface FetchState {
  isFetching: boolean;
  lastFetchTime: number;
  lastAttemptTime: number;
  lastError?: string;
  lastErrorTime?: number;
  consecutiveErrorFetches: number;
}

function createFetchState(): FetchState {
  return {
    isFetching: false,
    lastFetchTime: 0,
    lastAttemptTime: 0,
    lastError: undefined,
    lastErrorTime: undefined,
    consecutiveErrorFetches: 0,
  };
}

function recordFetchSuccess(state: FetchState, now: number = Date.now()): void {
  state.lastFetchTime = now;
  state.lastAttemptTime = now;
  state.lastError = undefined;
  state.lastErrorTime = undefined;
  state.consecutiveErrorFetches = 0;
  state.isFetching = false;
}

function recordFetchFailure(
  state: FetchState,
  errorMessage: string,
  now: number = Date.now(),
): void {
  state.lastAttemptTime = now;
  state.lastError = errorMessage;
  state.lastErrorTime = now;
  state.consecutiveErrorFetches = (state.consecutiveErrorFetches ?? 0) + 1;
  state.isFetching = false;
}

function shouldRefetch(
  state: FetchState,
  intervalMs: number,
  now: number = Date.now(),
): boolean {
  const last = state.lastAttemptTime || state.lastFetchTime;
  if (!last) return true;
  return now - last >= intervalMs;
}

interface Emitter<T> {
  fire(value: T): void;
  event(handler: (value: T) => void): () => void;
}

function createEmitter<T>(): Emitter<T> {
  const handlers = new Set<(value: T) => void>();
  return {
    fire(value: T): void {
      for (const h of Array.from(handlers)) {
        try {
          h(value);
        } catch {
          /* ignore listener errors */
        }
      }
    },
    event(handler: (value: T) => void): () => void {
      handlers.add(handler);
      return () => handlers.delete(handler);
    },
  };
}

describe('state.ts FetchState primitives', () => {
  it('creates zero-valued initial FetchState', () => {
    const s = createFetchState();
    expect(s.isFetching).toBe(false);
    expect(s.lastFetchTime).toBe(0);
    expect(s.lastAttemptTime).toBe(0);
    expect(s.lastError).toBeUndefined();
    expect(s.consecutiveErrorFetches).toBe(0);
  });

  it('records fetch success cleanly and clears prior errors', () => {
    const s = createFetchState();
    s.isFetching = true;
    s.consecutiveErrorFetches = 3;
    s.lastError = 'Connection refused';

    const now = 1700000000000;
    recordFetchSuccess(s, now);

    expect(s.isFetching).toBe(false);
    expect(s.lastFetchTime).toBe(now);
    expect(s.lastAttemptTime).toBe(now);
    expect(s.lastError).toBeUndefined();
    expect(s.lastErrorTime).toBeUndefined();
    expect(s.consecutiveErrorFetches).toBe(0);
  });

  it('records fetch failure and increments consecutiveErrorFetches counter', () => {
    const s = createFetchState();
    s.isFetching = true;

    const now1 = 1700000000000;
    recordFetchFailure(s, 'Timeout', now1);

    expect(s.isFetching).toBe(false);
    expect(s.lastError).toBe('Timeout');
    expect(s.lastErrorTime).toBe(now1);
    expect(s.lastAttemptTime).toBe(now1);
    expect(s.consecutiveErrorFetches).toBe(1);

    const now2 = 1700000005000;
    recordFetchFailure(s, '500 Server Error', now2);

    expect(s.lastError).toBe('500 Server Error');
    expect(s.consecutiveErrorFetches).toBe(2);
  });

  it('evaluates shouldRefetch correctly based on attempt interval', () => {
    const s = createFetchState();
    const interval = 5000;

    // Initial state: should always refetch
    expect(shouldRefetch(s, interval, 10000)).toBe(true);

    const now = 10000;
    recordFetchSuccess(s, now);

    // 2s elapsed: should not refetch yet
    expect(shouldRefetch(s, interval, now + 2000)).toBe(false);
    // 5s elapsed: threshold met, should refetch
    expect(shouldRefetch(s, interval, now + 5000)).toBe(true);
    // 10s elapsed: should refetch
    expect(shouldRefetch(s, interval, now + 10000)).toBe(true);
  });
});

describe('state.ts Emitter primitives', () => {
  it('subscribes and receives fired events', () => {
    const emitter = createEmitter<string>();
    const received: string[] = [];

    const dispose = emitter.event((val) => received.push(val));
    emitter.fire('event1');
    emitter.fire('event2');

    expect(received).toEqual(['event1', 'event2']);

    dispose();
    emitter.fire('event3');
    expect(received).toEqual(['event1', 'event2']);
  });

  it('isolates listener errors so one listener exception does not break others', () => {
    const emitter = createEmitter<number>();
    const received: number[] = [];

    emitter.event(() => {
      throw new Error('Boom');
    });
    emitter.event((val) => received.push(val));

    expect(() => emitter.fire(42)).not.toThrow();
    expect(received).toEqual([42]);
  });
});
