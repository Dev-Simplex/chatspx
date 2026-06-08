import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

vi.mock('../../../api/account', () => ({
  default: {
    get: vi.fn(() => Promise.resolve({ data: { id: 1, name: 'Acc' } })),
  },
}));

vi.mock('../../../api/enterprise/account', () => ({
  default: {},
}));

vi.mock('../../utils/api', () => ({
  throwErrorMessage: vi.fn(),
}));

vi.mock(
  'dashboard/components/widgets/conversation/advancedFilterItems/languages',
  () => ({
    getLanguageDirection: vi.fn(() => false),
  })
);

import { useAccountsStore } from '../useAccountsStore';

describe('useAccountsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('initial state', () => {
    const store = useAccountsStore();
    expect(store.records).toEqual([]);
    expect(store.uiFlags.isFetching).toBe(false);
  });

  it('getAccount returns by id', () => {
    const store = useAccountsStore();
    store.records = [{ id: 1, name: 'A' }];
    expect(store.getAccount(1).name).toBe('A');
    expect(store.getAccount(999)).toEqual({});
  });

  it('get() upserts account', async () => {
    const store = useAccountsStore();
    await store.get();
    expect(store.records[0].id).toBe(1);
  });

  it('isFeatureEnabledonAccount returns flag', () => {
    const store = useAccountsStore();
    store.records = [{ id: 1, features: { kanban: true } }];
    expect(store.isFeatureEnabledonAccount(1, 'kanban')).toBe(true);
    expect(store.isFeatureEnabledonAccount(1, 'missing')).toBe(false);
  });
});
