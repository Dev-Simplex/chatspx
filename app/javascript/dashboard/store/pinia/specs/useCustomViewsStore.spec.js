import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

vi.mock('../../../api/customViews', () => ({
  default: {
    getCustomViewsByFilterType: vi.fn(() =>
      Promise.resolve({ data: [{ id: 1, name: 'view' }] })
    ),
  },
}));

import { useCustomViewsStore } from '../useCustomViewsStore';

describe('useCustomViewsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('initial state', () => {
    const store = useCustomViewsStore();
    expect(store.getConversationCustomViews).toEqual([]);
    expect(store.getContactCustomViews).toEqual([]);
  });

  it('getCustomViewsByFilterType resolves alias keys', () => {
    const store = useCustomViewsStore();
    store.conversation.records = [{ id: 1 }];
    expect(store.getCustomViewsByFilterType(0)).toHaveLength(1);
    expect(store.getCustomViewsByFilterType('conversation')).toHaveLength(1);
  });

  it('get() populates the correct bucket', async () => {
    const store = useCustomViewsStore();
    await store.get('conversation');
    expect(store.getConversationCustomViews).toHaveLength(1);
  });

  it('setActiveConversationFolder stores folder', () => {
    const store = useCustomViewsStore();
    store.setActiveConversationFolder({ id: 9 });
    expect(store.getActiveConversationFolder.id).toBe(9);
  });
});
