import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useAttributesStore } from '../useAttributesStore';

describe('useAttributesStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "attributes"', () => {
    const store = useAttributesStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('attributes');
  });
});
