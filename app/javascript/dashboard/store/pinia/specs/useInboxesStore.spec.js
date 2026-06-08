import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

vi.mock('../../../api/inboxes', () => ({
  default: {
    get: vi.fn(() =>
      Promise.resolve({
        data: { payload: [{ id: 1, channel_type: 'Channel::Email' }] },
      })
    ),
  },
}));

vi.mock('../../../api/channel/webChannel', () => ({ default: {} }));
vi.mock('../../../api/channel/fbChannel', () => ({ default: {} }));
vi.mock('../../../api/channel/twilioChannel', () => ({ default: {} }));
vi.mock('../../../api/channel/whatsappChannel', () => ({ default: {} }));
vi.mock('../../utils/api', () => ({ throwErrorMessage: vi.fn() }));
vi.mock('../../../helper/AnalyticsHelper', () => ({
  default: { track: vi.fn() },
}));

import { useInboxesStore } from '../useInboxesStore';

describe('useInboxesStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('initial state', () => {
    const store = useInboxesStore();
    expect(store.records).toEqual([]);
    expect(store.uiFlags.isFetching).toBe(false);
  });

  it('getInbox returns record by id', () => {
    const store = useInboxesStore();
    store.records = [{ id: 5, name: 'Foo' }];
    expect(store.getInbox(5).name).toBe('Foo');
    expect(store.getInbox(999)).toEqual({});
  });

  it('get() loads records', async () => {
    const store = useInboxesStore();
    await store.get();
    expect(store.records).toHaveLength(1);
    expect(store.uiFlags.isFetching).toBe(false);
  });
});
