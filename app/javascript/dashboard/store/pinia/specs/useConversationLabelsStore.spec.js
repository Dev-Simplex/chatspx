import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useConversationLabelsStore } from '../useConversationLabelsStore';

describe('useConversationLabelsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "conversationLabels"', () => {
    const store = useConversationLabelsStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('conversationLabels');
  });
});
