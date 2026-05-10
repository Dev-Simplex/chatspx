import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { useAIErrorState } from '../useAIErrorState';

vi.mock('vue', async () => {
  const actual = await vi.importActual('vue');
  return { ...actual, onBeforeUnmount: () => {} };
});

describe('useAIErrorState', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('returns null for missing error', () => {
    const { classify } = useAIErrorState();
    expect(classify(null)).toBe(null);
    expect(classify(undefined)).toBe(null);
  });

  it('classifies AbortError as aborted', () => {
    const { handle } = useAIErrorState();
    expect(handle({ name: 'AbortError' })).toBe('aborted');
  });

  it('classifies CanceledError (axios) as aborted', () => {
    const { handle } = useAIErrorState();
    expect(handle({ name: 'CanceledError' })).toBe('aborted');
  });

  it('classifies ERR_NETWORK as network', () => {
    const { handle } = useAIErrorState();
    expect(handle({ code: 'ERR_NETWORK' })).toBe('network');
  });

  it('classifies ECONNABORTED as timeout', () => {
    const { handle } = useAIErrorState();
    expect(handle({ code: 'ECONNABORTED' })).toBe('timeout');
  });

  it('classifies HTTP 429 as rate_limit and parses Retry-After', () => {
    const { handle, errorType, retryAfterSeconds } = useAIErrorState();
    handle({
      response: { status: 429, headers: { 'retry-after': '45' } },
    });
    expect(errorType.value).toBe('rate_limit');
    expect(retryAfterSeconds.value).toBe(45);
  });

  it('falls back to 60s when 429 has no Retry-After', () => {
    const { handle, retryAfterSeconds } = useAIErrorState();
    handle({ response: { status: 429, headers: {} } });
    expect(retryAfterSeconds.value).toBe(60);
  });

  it('decrements retryAfterSeconds via cooldown interval', () => {
    const { handle, retryAfterSeconds } = useAIErrorState();
    handle({ response: { status: 429, headers: { 'retry-after': '3' } } });
    expect(retryAfterSeconds.value).toBe(3);
    vi.advanceTimersByTime(1000);
    expect(retryAfterSeconds.value).toBe(2);
    vi.advanceTimersByTime(1000);
    expect(retryAfterSeconds.value).toBe(1);
    vi.advanceTimersByTime(1000);
    expect(retryAfterSeconds.value).toBe(0);
  });

  it('classifies HTTP 502 as captain_unstable', () => {
    const { handle } = useAIErrorState();
    expect(handle({ response: { status: 502 } })).toBe('captain_unstable');
  });

  it('classifies HTTP 503 as captain_unstable', () => {
    const { handle } = useAIErrorState();
    expect(handle({ response: { status: 503 } })).toBe('captain_unstable');
  });

  it('classifies HTTP 504 as timeout', () => {
    const { handle } = useAIErrorState();
    expect(handle({ response: { status: 504 } })).toBe('timeout');
  });

  it('returns null for HTTP 500 (caller decides fallback)', () => {
    const { handle } = useAIErrorState();
    expect(handle({ response: { status: 500 } })).toBe(null);
  });

  it('setEmpty marks empty_response', () => {
    const { setEmpty, errorType } = useAIErrorState();
    setEmpty();
    expect(errorType.value).toBe('empty_response');
  });

  it('clear() resets state and stops cooldown', () => {
    const { handle, clear, errorType, retryAfterSeconds } = useAIErrorState();
    handle({ response: { status: 429, headers: { 'retry-after': '10' } } });
    expect(errorType.value).toBe('rate_limit');
    clear();
    expect(errorType.value).toBe(null);
    expect(retryAfterSeconds.value).toBe(0);
    vi.advanceTimersByTime(2000);
    // After clear, the cooldown should be stopped
    expect(retryAfterSeconds.value).toBe(0);
  });

  it('handles 429 → 200 sequence correctly', () => {
    const { handle, clear, errorType } = useAIErrorState();
    handle({ response: { status: 429, headers: { 'retry-after': '5' } } });
    expect(errorType.value).toBe('rate_limit');
    clear();
    expect(errorType.value).toBe(null);
    // Next call succeeds — caller doesn't invoke handle, so state stays clear
    expect(errorType.value).toBe(null);
  });
});
