import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

vi.mock('../../../api/macros', () => ({
  default: {
    get: vi.fn(() =>
      Promise.resolve({ data: { payload: [{ id: 1, name: 'm' }] } })
    ),
  },
}));

import { useMacrosStore } from '../useMacrosStore';

describe('useMacrosStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('initial state', () => {
    const store = useMacrosStore();
    expect(store.records).toEqual([]);
    expect(store.uiFlags.isFetching).toBe(false);
  });

  it('getMacro returns by id', () => {
    const store = useMacrosStore();
    store.records = [{ id: 7, name: 'foo' }];
    expect(store.getMacro(7).name).toBe('foo');
  });

  it('get() populates records', async () => {
    const store = useMacrosStore();
    await store.get();
    expect(store.records).toEqual([{ id: 1, name: 'm' }]);
  });
});
