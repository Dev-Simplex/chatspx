import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach } from 'vitest';
import { usePingStore } from '../usePingStore';

describe('usePingStore', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  it('returns "pong"', () => {
    const store = usePingStore();
    expect(store.pong()).toBe('pong');
  });
});
