import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useDraftMessagesStore } from '../useDraftMessagesStore';

describe('useDraftMessagesStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "draftMessages"', () => {
    const store = useDraftMessagesStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('draftMessages');
  });
});
