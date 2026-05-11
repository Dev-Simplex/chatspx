import { defineComponent, h, nextTick } from 'vue';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import { useAIOnboarding } from '../useAIOnboarding';

const STORAGE_KEY = 'chatspx_ai_onboarded';

const mountWithComposable = () => {
  let exposed;
  const Wrapper = defineComponent({
    setup() {
      exposed = useAIOnboarding();
      return () => h('div');
    },
  });
  const wrapper = mount(Wrapper);
  return { wrapper, api: exposed };
};

describe('useAIOnboarding', () => {
  beforeEach(() => {
    window.localStorage.clear();
    vi.restoreAllMocks();
  });

  it('starts as not-onboarded when no flag is stored', () => {
    const { api } = mountWithComposable();
    expect(api.isOnboarded.value).toBe(false);
    expect(api.shouldShowOnboarding.value).toBe(true);
  });

  it('treats stored "true" or "auto" as onboarded', () => {
    window.localStorage.setItem(STORAGE_KEY, 'true');
    const { api } = mountWithComposable();
    expect(api.isOnboarded.value).toBe(true);
    expect(api.shouldShowOnboarding.value).toBe(false);

    window.localStorage.setItem(STORAGE_KEY, 'auto');
    const { api: api2 } = mountWithComposable();
    expect(api2.isOnboarded.value).toBe(true);
    expect(api2.shouldShowOnboarding.value).toBe(false);
  });

  it('falls back to not-onboarded when localStorage throws (corrupt/quota)', () => {
    const proto = Object.getPrototypeOf(window.localStorage);
    const spy = vi.spyOn(proto, 'getItem').mockImplementation(() => {
      throw new Error('SecurityError');
    });

    const { api } = mountWithComposable();
    expect(api.isOnboarded.value).toBe(false);
    expect(api.shouldShowOnboarding.value).toBe(true);
    spy.mockRestore();
  });

  it('does not throw when setItem hits quota during markOnboarded', () => {
    const proto = Object.getPrototypeOf(window.localStorage);
    const spy = vi.spyOn(proto, 'setItem').mockImplementation(() => {
      throw new Error('QuotaExceeded');
    });

    const { api } = mountWithComposable();
    expect(() => api.markOnboarded('confirm')).not.toThrow();
    // Still flips local reactive state even if persistence failed
    expect(api.isOnboarded.value).toBe(true);
    expect(api.shouldShowOnboarding.value).toBe(false);
    spy.mockRestore();
  });

  it('persists "auto" when method is auto and "true" otherwise', () => {
    const { api } = mountWithComposable();
    api.markOnboarded('auto');
    expect(window.localStorage.getItem(STORAGE_KEY)).toBe('auto');

    api.reset();
    expect(window.localStorage.getItem(STORAGE_KEY)).toBe(null);

    api.markOnboarded('confirm');
    expect(window.localStorage.getItem(STORAGE_KEY)).toBe('true');
  });

  it('reset() clears localStorage and reopens onboarding', () => {
    window.localStorage.setItem(STORAGE_KEY, 'true');
    const { api } = mountWithComposable();
    expect(api.shouldShowOnboarding.value).toBe(false);

    api.reset();
    expect(api.isOnboarded.value).toBe(false);
    expect(api.shouldShowOnboarding.value).toBe(true);
    expect(window.localStorage.getItem(STORAGE_KEY)).toBe(null);
  });

  it('multi-tab sync: storage event flips reactive state', async () => {
    const { api } = mountWithComposable();
    expect(api.shouldShowOnboarding.value).toBe(true);

    // Simulate another tab writing the flag
    window.localStorage.setItem(STORAGE_KEY, 'true');
    window.dispatchEvent(
      new StorageEvent('storage', {
        key: STORAGE_KEY,
        newValue: 'true',
      })
    );

    await nextTick();
    expect(api.isOnboarded.value).toBe(true);
    expect(api.shouldShowOnboarding.value).toBe(false);
  });

  it('multi-tab sync: ignores unrelated storage keys', async () => {
    const { api } = mountWithComposable();
    window.dispatchEvent(
      new StorageEvent('storage', {
        key: 'unrelated_key',
        newValue: 'true',
      })
    );
    await nextTick();
    expect(api.isOnboarded.value).toBe(false);
  });
});
