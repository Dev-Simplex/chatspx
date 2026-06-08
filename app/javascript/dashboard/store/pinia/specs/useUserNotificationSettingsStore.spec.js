import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock APIs pesadas para nao puxarem axios real
vi.mock('../../../api/notifications', () => ({ default: {} }));

import { useUserNotificationSettingsStore } from '../useUserNotificationSettingsStore';

describe('useUserNotificationSettingsStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('exposes a defineStore instance with id "userNotificationSettings"', () => {
    const store = useUserNotificationSettingsStore();
    expect(store).toBeDefined();
    expect(store.$id).toBe('userNotificationSettings');
  });
});
