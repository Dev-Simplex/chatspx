import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

vi.mock('../../../api/teams', () => ({
  default: {
    get: vi.fn(() =>
      Promise.resolve({ data: [{ id: 1, name: 'T1', is_member: true }] })
    ),
  },
}));

import { useTeamsStore } from '../useTeamsStore';

describe('useTeamsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('initial state', () => {
    const store = useTeamsStore();
    expect(store.records).toEqual({});
    expect(store.getTeams).toEqual([]);
  });

  it('getTeams sorts by id', () => {
    const store = useTeamsStore();
    store.records = {
      2: { id: 2, name: 'B' },
      1: { id: 1, name: 'A' },
    };
    expect(store.getTeams[0].name).toBe('A');
  });

  it('get() populates records dict', async () => {
    const store = useTeamsStore();
    await store.get();
    expect(store.records[1].name).toBe('T1');
    expect(store.getMyTeams).toHaveLength(1);
  });

  it('getTeam returns by id', () => {
    const store = useTeamsStore();
    store.records = { 3: { id: 3, name: 'X' } };
    expect(store.getTeam(3).name).toBe('X');
    expect(store.getTeam(999)).toEqual({});
  });
});
