import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas pra nao puxarem axios real
vi.mock('../../../api/inbox/conversation', () => ({ default: {} }));
vi.mock('../../../api/inbox/message', () => ({ default: {} }));
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useConversationsStore } from '../useConversationsStore';

describe('useConversationsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "conversations"', () => {
    const store = useConversationsStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('conversations');
  });

  it('starts with empty allConversations and null selectedChatId', () => {
    const store = useConversationsStore();
    expect(store.allConversations).toEqual([]);
    expect(store.selectedChatId).toBeNull();
  });

  it('emptyAllConversation clears state', () => {
    const store = useConversationsStore();
    store.allConversations = [{ id: 1 }];
    store.selectedChatId = 1;
    store.emptyAllConversation();
    expect(store.allConversations).toEqual([]);
    expect(store.selectedChatId).toBeNull();
  });

  it('changeChatStatusFilter updates state', () => {
    const store = useConversationsStore();
    store.changeChatStatusFilter('all');
    expect(store.chatStatusFilter).toBe('all');
  });
});
