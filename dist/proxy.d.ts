import type { CustomModel, GeminiRequestBody, GeminiCandidate, CloudCodeResponse } from './proxy/types';
export type { CustomModel, GeminiRequestBody, GeminiCandidate, CloudCodeResponse };
import { type ErrorType } from './proxy/errorClassifier';
import { generateModelPlaceholderId, toSlug } from './proxy/idGenerator';
export { generateModelPlaceholderId, toSlug };
export type ProxyErrorPayload = {
    traceId: string;
    provider: string;
    status?: number;
    errorType: ErrorType;
    rawError: string;
    title: string;
    message: string;
    suggestions: string[];
    actionUrl?: string;
};
export declare function setProxyErrorEmitter(fn: ((p: ProxyErrorPayload) => void) | null): void;
export declare function buildProxyErrorPayload(traceId: string, status: number | undefined, bodyOrErr: unknown, provider: string | undefined, fallbackMessage?: string): ProxyErrorPayload;
/**
 * Parses the Retry-After header from upstream responses (RFC 7231 §7.1.3).
 * Returns delay in milliseconds, or 0 if no valid header is present.
 */
export declare function parseRetryAfter(headers: Record<string, string | string[] | undefined>): number;
export declare function startProxy(): Promise<number>;
/**
 * Reads the persisted state file and applies it to the live singletons.
 * Called once on startup. Safe to call again — re-loads idempotently.
 */
export declare function loadPersistedState(): void;
/**
 * Persist the current in-memory retry budget + breaker state to disk.
 * Throttled by `MIN_FLUSH_INTERVAL_MS` unless `force` is set.
 */
export declare function flushPersistedState(opts?: {
    force?: boolean;
}): void;
export declare function stopProxy(): Promise<void>;
export declare function getProxyPort(): number;
//# sourceMappingURL=proxy.d.ts.map