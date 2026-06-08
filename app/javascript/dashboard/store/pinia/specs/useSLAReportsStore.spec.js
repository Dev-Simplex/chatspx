import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useSLAReportsStore } from '../useSLAReportsStore';

describe('useSLAReportsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "SLAReports"', () => {
    const store = useSLAReportsStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('SLAReports');
  });
});
