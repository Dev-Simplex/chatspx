import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useSlaStore } from '../useSlaStore';

describe('useSlaStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "sla"', () => {
    const store = useSlaStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('sla');
  });
});
