import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useIntegrationsStore } from '../useIntegrationsStore';

describe('useIntegrationsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "integrations"', () => {
    const store = useIntegrationsStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('integrations');
  });
});
