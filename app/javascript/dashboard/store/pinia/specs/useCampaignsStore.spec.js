import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useCampaignsStore } from '../useCampaignsStore';

describe('useCampaignsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "campaigns"', () => {
    const store = useCampaignsStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('campaigns');
  });
});
