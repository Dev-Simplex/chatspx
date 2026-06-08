import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useDashboardAppsStore } from '../useDashboardAppsStore';

describe('useDashboardAppsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "dashboardApps"', () => {
    const store = useDashboardAppsStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('dashboardApps');
  });
});
