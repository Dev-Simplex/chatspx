import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

vi.mock('../../../api/cannedResponse', () => ({
  default: {
    get: vi.fn(() =>
      Promise.resolve({
        data: [
          { id: 1, short_code: 'a' },
          { id: 2, short_code: 'b' },
        ],
      })
    ),
  },
}));

import { useCannedResponseStore } from '../useCannedResponseStore';

describe('useCannedResponseStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('initial state', () => {
    const store = useCannedResponseStore();
    expect(store.records).toEqual([]);
    expect(store.uiFlags.fetchingList).toBe(false);
  });

  it('getSortedCannedResponses sorts asc', () => {
    const store = useCannedResponseStore();
    store.records = [
      { id: 1, short_code: 'beta' },
      { id: 2, short_code: 'alpha' },
    ];
    expect(store.getSortedCannedResponses('asc')[0].short_code).toBe('alpha');
  });

  it('getCannedResponse() fetches', async () => {
    const store = useCannedResponseStore();
    await store.getCannedResponse({ searchKey: '' });
    expect(store.records).toHaveLength(2);
  });
});
