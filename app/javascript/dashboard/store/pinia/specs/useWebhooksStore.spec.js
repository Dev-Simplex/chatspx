import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useWebhooksStore } from '../useWebhooksStore';

describe('useWebhooksStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "webhooks"', () => {
    const store = useWebhooksStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('webhooks');
  });
});
