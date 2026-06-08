import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useCustomRoleStore } from '../useCustomRoleStore';

describe('useCustomRoleStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "customRole"', () => {
    const store = useCustomRoleStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('customRole');
  });
});
