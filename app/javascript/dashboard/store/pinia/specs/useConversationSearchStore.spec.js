import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useConversationSearchStore } from '../useConversationSearchStore';

describe('useConversationSearchStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "conversationSearch"', () => {
    const store = useConversationSearchStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('conversationSearch');
  });
});
