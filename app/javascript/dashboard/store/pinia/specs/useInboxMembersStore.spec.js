import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useInboxMembersStore } from '../useInboxMembersStore';

describe('useInboxMembersStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "inboxMembers"', () => {
    const store = useInboxMembersStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('inboxMembers');
  });
});
