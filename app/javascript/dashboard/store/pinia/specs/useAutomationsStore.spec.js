import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useAutomationsStore } from '../useAutomationsStore';

describe('useAutomationsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "automations"', () => {
    const store = useAutomationsStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('automations');
  });
});
