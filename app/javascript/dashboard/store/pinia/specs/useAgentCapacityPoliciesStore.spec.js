import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useAgentCapacityPoliciesStore } from '../useAgentCapacityPoliciesStore';

describe('useAgentCapacityPoliciesStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "agentCapacityPolicies"', () => {
    const store = useAgentCapacityPoliciesStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('agentCapacityPolicies');
  });
});
