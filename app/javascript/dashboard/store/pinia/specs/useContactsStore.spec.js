import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useContactsStore } from '../useContactsStore';

describe('useContactsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "contacts"', () => {
    const store = useContactsStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('contacts');
  });
});
