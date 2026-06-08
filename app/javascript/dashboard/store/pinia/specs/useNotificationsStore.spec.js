import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useNotificationsStore } from '../useNotificationsStore';

describe('useNotificationsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "notifications"', () => {
    const store = useNotificationsStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('notifications');
  });
});
