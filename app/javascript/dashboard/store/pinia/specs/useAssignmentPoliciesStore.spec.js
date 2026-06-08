import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useAssignmentPoliciesStore } from '../useAssignmentPoliciesStore';

describe('useAssignmentPoliciesStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "assignmentPolicies"', () => {
    const store = useAssignmentPoliciesStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('assignmentPolicies');
  });
});
