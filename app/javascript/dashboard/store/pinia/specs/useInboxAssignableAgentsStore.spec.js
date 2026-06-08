import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useInboxAssignableAgentsStore } from '../useInboxAssignableAgentsStore';

describe('useInboxAssignableAgentsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "inboxAssignableAgents"', () => {
    const store = useInboxAssignableAgentsStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('inboxAssignableAgents');
  });
});
