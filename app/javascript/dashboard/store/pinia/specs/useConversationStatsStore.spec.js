import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useConversationStatsStore } from '../useConversationStatsStore';

describe('useConversationStatsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "conversationStats"', () => {
    const store = useConversationStatsStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('conversationStats');
  });
});
