import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useConversationPageStore } from '../useConversationPageStore';

describe('useConversationPageStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "conversationPage"', () => {
    const store = useConversationPageStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('conversationPage');
  });
});
