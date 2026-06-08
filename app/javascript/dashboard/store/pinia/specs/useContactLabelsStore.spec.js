import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useContactLabelsStore } from '../useContactLabelsStore';

describe('useContactLabelsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "contactLabels"', () => {
    const store = useContactLabelsStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('contactLabels');
  });
});
