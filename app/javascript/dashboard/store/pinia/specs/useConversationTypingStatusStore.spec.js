import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useConversationTypingStatusStore } from '../useConversationTypingStatusStore';

describe('useConversationTypingStatusStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "conversationTypingStatus"', () => {
    const store = useConversationTypingStatusStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('conversationTypingStatus');
  });
});
