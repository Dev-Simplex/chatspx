import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

vi.mock('../../../api/labels', () => ({
  default: {
    get: vi.fn(() =>
      Promise.resolve({
        data: {
          payload: [
            { id: 1, title: 'b' },
            { id: 2, title: 'a' },
          ],
        },
      })
    ),
    validateCacheKey: vi.fn(),
    refetchAndCommit: vi.fn(),
  },
}));

vi.mock('../../../helper/AnalyticsHelper', () => ({
  default: { track: vi.fn() },
}));

import { useLabelsStore } from '../useLabelsStore';

describe('useLabelsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('initial state', () => {
    const store = useLabelsStore();
    expect(store.records).toEqual([]);
    expect(store.uiFlags.isFetching).toBe(false);
  });

  it('getLabelsOnSidebar filters and sorts', () => {
    const store = useLabelsStore();
    store.records = [
      { id: 1, title: 'beta', show_on_sidebar: true },
      { id: 2, title: 'alpha', show_on_sidebar: true },
      { id: 3, title: 'gamma', show_on_sidebar: false },
    ];
    const result = store.getLabelsOnSidebar;
    expect(result).toHaveLength(2);
    expect(result[0].title).toBe('alpha');
  });

  it('get() fetches and sorts records', async () => {
    const store = useLabelsStore();
    await store.get();
    expect(store.records[0].title).toBe('a');
    expect(store.uiFlags.isFetching).toBe(false);
  });
});
