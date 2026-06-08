import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useAgentBotsStore } from '../useAgentBotsStore';

describe('useAgentBotsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "agentBots"', () => {
    const store = useAgentBotsStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('agentBots');
  });
});
