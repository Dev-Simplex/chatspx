import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useContactConversationsStore } from '../useContactConversationsStore';

describe('useContactConversationsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "contactConversations"', () => {
    const store = useContactConversationsStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('contactConversations');
  });
});
