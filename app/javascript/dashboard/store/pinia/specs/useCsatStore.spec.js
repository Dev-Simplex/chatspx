import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useCsatStore } from '../useCsatStore';

describe('useCsatStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "csat"', () => {
    const store = useCsatStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('csat');
  });
});
