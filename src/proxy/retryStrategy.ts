/**
 * Retry strategies for upstream API requests.
 * Pure functions — no I/O, no side effects, fully testable.
 */

import {
  STREAM_RETRY_BASE_DELAY_MS,
  NON_STREAM_RETRY_BASE_DELAY_MS,
  RATE_LIMIT_RETRY_BASE_DELAY_MS,
  SERVER_ERROR_RETRY_BASE_DELAY_MS,
} from '../constants';

/**
 * Types of retry scenarios.
 */
export type RetryStrategy = 'stream-error' | 'server-error' | 'rate-limit';

/**
 * Result of computing a retry delay.
 */
export interface RetryDecision {
  /** Whether a retry should be attempted. */
  shouldRetry: boolean;
  /** Delay in milliseconds before the next attempt. */
  delayMs: number;
  /** The new retry count after this attempt. */
  nextRetryCount: number;
}

/**
 * Computes the retry delay for a given strategy.
 *
 * @param strategy Type of retry scenario
 * @param retryCount Current retry count (0-indexed)
 * @param retryAfterMs Delay from Retry-After header (0 if not present)
 * @returns Delay in milliseconds
 */
export function computeRetryDelay(
  strategy: RetryStrategy,
  retryCount: number,
  retryAfterMs: number,
): number {
  // Respect Retry-After header if present
  if (retryAfterMs > 0) return retryAfterMs;

  switch (strategy) {
    case 'stream-error':
      // Linear backoff: base * (retryCount + 1)
      return STREAM_RETRY_BASE_DELAY_MS * (retryCount + 1);

    case 'server-error':
      // Exponential backoff: base * 2^retryCount
      return SERVER_ERROR_RETRY_BASE_DELAY_MS * Math.pow(2, retryCount);

    case 'rate-limit':
      // Exponential backoff with 2x base: 2 * base * 2^retryCount
      return RATE_LIMIT_RETRY_BASE_DELAY_MS * Math.pow(2, retryCount);

    default:
      return NON_STREAM_RETRY_BASE_DELAY_MS;
  }
}

/**
 * Determines whether a retry should be attempted for a given status code.
 *
 * @param statusCode HTTP status code from upstream
 * @param retryCount Current retry count
 * @param maxRetries Maximum allowed retries
 * @returns True if retry should be attempted
 */
export function shouldRetryStatus(
  statusCode: number,
  retryCount: number,
  maxRetries: number,
): boolean {
  if (retryCount >= maxRetries) return false;
  // 5xx server errors
  if (statusCode >= 500 && statusCode < 600) return true;
  // 429 rate limit
  if (statusCode === 429) return true;
  return false;
}

/**
 * Builds a complete retry decision for a given scenario.
 */
export function buildRetryDecision(
  strategy: RetryStrategy,
  retryCount: number,
  maxRetries: number,
  retryAfterMs: number,
): RetryDecision {
  if (retryCount >= maxRetries) {
    return { shouldRetry: false, delayMs: 0, nextRetryCount: retryCount };
  }
  const delayMs = computeRetryDelay(strategy, retryCount, retryAfterMs);
  return {
    shouldRetry: true,
    delayMs,
    nextRetryCount: retryCount + 1,
  };
}
