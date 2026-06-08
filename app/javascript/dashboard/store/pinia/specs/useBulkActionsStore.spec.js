import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useBulkActionsStore } from '../useBulkActionsStore';

describe('useBulkActionsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "bulkActions"', () => {
    const store = useBulkActionsStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('bulkActions');
  });
});
