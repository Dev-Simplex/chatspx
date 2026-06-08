import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useTeamMembersStore } from '../useTeamMembersStore';

describe('useTeamMembersStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "teamMembers"', () => {
    const store = useTeamMembersStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('teamMembers');
  });
});
