import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useHelpCenterCategoriesStore } from '../useHelpCenterCategoriesStore';

describe('useHelpCenterCategoriesStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "helpCenterCategories"', () => {
    const store = useHelpCenterCategoriesStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('helpCenterCategories');
  });
});
