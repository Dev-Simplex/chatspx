import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useReportsStore } from '../useReportsStore';

describe('useReportsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "reports"', () => {
    const store = useReportsStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('reports');
  });
});
