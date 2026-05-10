import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
  useDismissedSuggestions,
  DISMISSED_SUGGESTIONS_KEYS,
} from '../useDismissedSuggestions';

const KEY = DISMISSED_SUGGESTIONS_KEYS.STORAGE_KEY;

describe('useDismissedSuggestions', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-15T10:00:00Z'));
    window.localStorage.clear();
  });

  afterEach(() => {
    vi.useRealTimers();
    window.localStorage.clear();
  });

  it('returns false by default for any conversation/suggestion combo', () => {
    const { isDismissed } = useDismissedSuggestions();
    expect(isDismissed(123, 'long_thread')).toBe(false);
    expect(isDismissed(456)).toBe(false);
  });

  it('persists a dismissal under the storage key', () => {
    const { add, isDismissed } = useDismissedSuggestions();
    add(123, 'long_thread');
    expect(isDismissed(123, 'long_thread')).toBe(true);

    const raw = JSON.parse(window.localStorage.getItem(KEY));
    expect(raw.items[123].ids).toEqual(['long_thread']);
    expect(raw.items[123].ts).toBeGreaterThan(0);
  });

  it('does not duplicate the same suggestion id for the same conversation', () => {
    const { add } = useDismissedSuggestions();
    add(123, 'long_thread');
    add(123, 'long_thread');
    add(123, 'long_thread');
    const raw = JSON.parse(window.localStorage.getItem(KEY));
    expect(raw.items[123].ids).toEqual(['long_thread']);
  });

  it('returns false after the 7-day TTL expires', () => {
    const { add, isDismissed } = useDismissedSuggestions();
    add(123, 'long_thread');
    expect(isDismissed(123, 'long_thread')).toBe(true);
    // Advance 8 days
    vi.advanceTimersByTime(8 * 24 * 60 * 60 * 1000);
    expect(isDismissed(123, 'long_thread')).toBe(false);
  });

  it('caps storage at MAX_ENTRIES via LRU by timestamp', () => {
    const { add } = useDismissedSuggestions();
    // Insert 250 entries, each in its own conversation, advancing time
    // so timestamps differ.
    for (let i = 0; i < 250; i += 1) {
      vi.advanceTimersByTime(1000);
      add(i, 'waiting');
    }
    const raw = JSON.parse(window.localStorage.getItem(KEY));
    const keys = Object.keys(raw.items);
    expect(keys.length).toBe(DISMISSED_SUGGESTIONS_KEYS.MAX_ENTRIES);
    // Oldest entries (id 0..49) should have been trimmed.
    expect(keys).not.toContain('0');
    expect(keys).toContain('249');
  });

  it('does not throw when localStorage contains corrupt data', () => {
    window.localStorage.setItem(KEY, '{not-valid-json');
    const { isDismissed, add } = useDismissedSuggestions();
    expect(isDismissed(123, 'long_thread')).toBe(false);
    expect(() => add(123, 'long_thread')).not.toThrow();
  });

  it('does not throw when localStorage.setItem rejects (quota exceeded)', () => {
    const original = window.localStorage.setItem.bind(window.localStorage);
    const setItemSpy = vi
      .spyOn(window.localStorage, 'setItem')
      .mockImplementation(() => {
        throw new Error('QuotaExceededError');
      });
    const { add } = useDismissedSuggestions();
    expect(() => add(123, 'long_thread')).not.toThrow();
    setItemSpy.mockRestore();
    // Sanity — the original implementation still works after restore
    original(KEY, '{}');
  });

  it('isolates dismissals between different conversations', () => {
    const { add, isDismissed } = useDismissedSuggestions();
    add(111, 'long_thread');
    expect(isDismissed(111, 'long_thread')).toBe(true);
    expect(isDismissed(222, 'long_thread')).toBe(false);
  });

  it('clear() removes all dismissals for a conversation', () => {
    const { add, clear, isDismissed } = useDismissedSuggestions();
    add(111, 'long_thread');
    add(111, 'waiting');
    expect(isDismissed(111, 'long_thread')).toBe(true);
    clear(111);
    expect(isDismissed(111, 'long_thread')).toBe(false);
    expect(isDismissed(111, 'waiting')).toBe(false);
  });

  it('isDismissed without a suggestionId returns true if any id is dismissed', () => {
    const { add, isDismissed } = useDismissedSuggestions();
    expect(isDismissed(111)).toBe(false);
    add(111, 'long_thread');
    expect(isDismissed(111)).toBe(true);
  });

  it('returns false for a falsy conversationId', () => {
    const { isDismissed, add } = useDismissedSuggestions();
    expect(isDismissed(null, 'long_thread')).toBe(false);
    expect(isDismissed(undefined, 'long_thread')).toBe(false);
    expect(isDismissed(0, 'long_thread')).toBe(false);
    expect(() => add(null, 'long_thread')).not.toThrow();
  });
});
