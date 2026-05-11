import { describe, it, expect, beforeEach, vi } from 'vitest';

// Build a mutable mock for the store getters that each test can rewire.
let mockServerEnabled = true;

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key => ({
    get value() {
      if (key === 'accounts/isFeatureEnabledonAccount') {
        // Mirror the real getter shape: takes (accountId, featureName) → bool
        return () => mockServerEnabled;
      }
      if (key === 'getCurrentAccountId') return 1;
      return null;
    },
  }),
}));

import {
  useAIAssistantFlag,
  applyAIAssistantQueryOverride,
  AI_ASSISTANT_FLAG_KEYS,
} from '../useAIAssistantFlag';

describe('useAIAssistantFlag', () => {
  beforeEach(() => {
    mockServerEnabled = true;
    sessionStorage.clear();
    localStorage.clear();
  });

  it('returns false when server flag is disabled (kill-switch)', () => {
    mockServerEnabled = false;
    sessionStorage.setItem(AI_ASSISTANT_FLAG_KEYS.SESSION_KEY, 'on');
    localStorage.setItem(AI_ASSISTANT_FLAG_KEYS.LOCAL_KEY, 'on');
    expect(useAIAssistantFlag().value).toBe(false);
  });

  it('returns true by default when server flag is enabled', () => {
    expect(useAIAssistantFlag().value).toBe(true);
  });

  it('session override "on" wins over local "off"', () => {
    sessionStorage.setItem(AI_ASSISTANT_FLAG_KEYS.SESSION_KEY, 'on');
    localStorage.setItem(AI_ASSISTANT_FLAG_KEYS.LOCAL_KEY, 'off');
    expect(useAIAssistantFlag().value).toBe(true);
  });

  it('session override "off" wins over local "on"', () => {
    sessionStorage.setItem(AI_ASSISTANT_FLAG_KEYS.SESSION_KEY, 'off');
    localStorage.setItem(AI_ASSISTANT_FLAG_KEYS.LOCAL_KEY, 'on');
    expect(useAIAssistantFlag().value).toBe(false);
  });

  it('local override "off" turns it off when no session override', () => {
    localStorage.setItem(AI_ASSISTANT_FLAG_KEYS.LOCAL_KEY, 'off');
    expect(useAIAssistantFlag().value).toBe(false);
  });

  it('local override "on" stays true (matches default)', () => {
    localStorage.setItem(AI_ASSISTANT_FLAG_KEYS.LOCAL_KEY, 'on');
    expect(useAIAssistantFlag().value).toBe(true);
  });

  it('ignores unknown override values', () => {
    sessionStorage.setItem(AI_ASSISTANT_FLAG_KEYS.SESSION_KEY, 'maybe');
    localStorage.setItem(AI_ASSISTANT_FLAG_KEYS.LOCAL_KEY, 'maybe');
    expect(useAIAssistantFlag().value).toBe(true);
  });
});

describe('applyAIAssistantQueryOverride', () => {
  beforeEach(() => {
    sessionStorage.clear();
  });

  it('returns null and is a no-op when ?aiv2 is absent', () => {
    const url = new URL('https://example.com/dashboard');
    Object.defineProperty(window, 'location', {
      value: url,
      writable: true,
      configurable: true,
    });
    expect(applyAIAssistantQueryOverride()).toBe(null);
    expect(sessionStorage.getItem(AI_ASSISTANT_FLAG_KEYS.SESSION_KEY)).toBe(
      null
    );
  });

  it('writes "on" when ?aiv2=1', () => {
    Object.defineProperty(window, 'location', {
      value: new URL('https://example.com/dashboard?aiv2=1'),
      writable: true,
      configurable: true,
    });
    expect(applyAIAssistantQueryOverride()).toBe('on');
    expect(sessionStorage.getItem(AI_ASSISTANT_FLAG_KEYS.SESSION_KEY)).toBe(
      'on'
    );
  });

  it('writes "off" when ?aiv2=0', () => {
    Object.defineProperty(window, 'location', {
      value: new URL('https://example.com/dashboard?aiv2=0'),
      writable: true,
      configurable: true,
    });
    expect(applyAIAssistantQueryOverride()).toBe('off');
    expect(sessionStorage.getItem(AI_ASSISTANT_FLAG_KEYS.SESSION_KEY)).toBe(
      'off'
    );
  });

  it('ignores ?aiv2=garbage', () => {
    Object.defineProperty(window, 'location', {
      value: new URL('https://example.com/dashboard?aiv2=foo'),
      writable: true,
      configurable: true,
    });
    expect(applyAIAssistantQueryOverride()).toBe(null);
  });
});
