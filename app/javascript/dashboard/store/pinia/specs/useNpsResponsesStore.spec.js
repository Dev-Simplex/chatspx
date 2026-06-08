import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useNpsResponsesStore } from '../useNpsResponsesStore';

describe('useNpsResponsesStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "npsResponses"', () => {
    const store = useNpsResponsesStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('npsResponses');
  });
});
