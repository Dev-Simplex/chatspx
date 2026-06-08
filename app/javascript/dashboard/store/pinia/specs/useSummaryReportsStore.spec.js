import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useSummaryReportsStore } from '../useSummaryReportsStore';

describe('useSummaryReportsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "summaryReports"', () => {
    const store = useSummaryReportsStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('summaryReports');
  });
});
