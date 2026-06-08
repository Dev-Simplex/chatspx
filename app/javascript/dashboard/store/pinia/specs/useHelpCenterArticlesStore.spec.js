import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useHelpCenterArticlesStore } from '../useHelpCenterArticlesStore';

describe('useHelpCenterArticlesStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "helpCenterArticles"', () => {
    const store = useHelpCenterArticlesStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('helpCenterArticles');
  });
});
