import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useHelpCenterPortalsStore } from '../useHelpCenterPortalsStore';

describe('useHelpCenterPortalsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "helpCenterPortals"', () => {
    const store = useHelpCenterPortalsStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('helpCenterPortals');
  });
});
