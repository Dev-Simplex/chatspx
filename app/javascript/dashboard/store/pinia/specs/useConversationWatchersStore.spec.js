import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useConversationWatchersStore } from '../useConversationWatchersStore';

describe('useConversationWatchersStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "conversationWatchers"', () => {
    const store = useConversationWatchersStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('conversationWatchers');
  });
});
