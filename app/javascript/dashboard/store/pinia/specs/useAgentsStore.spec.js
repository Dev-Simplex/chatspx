import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

vi.mock('../../../api/agents', () => ({
  default: {
    get: vi.fn(() =>
      Promise.resolve({
        data: [
          { id: 1, name: 'A', confirmed: true, availability_status: 'online' },
          {
            id: 2,
            name: 'B',
            confirmed: false,
            availability_status: 'offline',
          },
        ],
      })
    ),
  },
}));

import { useAgentsStore } from '../useAgentsStore';

describe('useAgentsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('initial state', () => {
    const store = useAgentsStore();
    expect(store.records).toEqual([]);
  });

  it('getVerifiedAgents filters confirmed', () => {
    const store = useAgentsStore();
    store.records = [
      { id: 1, confirmed: true },
      { id: 2, confirmed: false },
    ];
    expect(store.getVerifiedAgents).toHaveLength(1);
  });

  it('get() loads agents', async () => {
    const store = useAgentsStore();
    await store.get();
    expect(store.records).toHaveLength(2);
    expect(store.getAgentStatus.online).toBe(1);
  });

  it('updateSingleAgentPresence updates record', () => {
    const store = useAgentsStore();
    store.records = [{ id: 5, availability_status: 'offline' }];
    store.updateSingleAgentPresence({ id: 5, availabilityStatus: 'online' });
    expect(store.records[0].availability_status).toBe('online');
  });
});
