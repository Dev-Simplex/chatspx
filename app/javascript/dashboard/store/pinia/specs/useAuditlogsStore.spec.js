import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useAuditlogsStore } from '../useAuditlogsStore';

describe('useAuditlogsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "auditlogs"', () => {
    const store = useAuditlogsStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('auditlogs');
  });
});
