import { setActivePinia, createPinia } from 'pinia';
import { describe, it, expect, beforeEach, vi } from 'vitest';

vi.mock('../../../api/auth', () => ({
  default: {
    hasAuthCookie: vi.fn(() => false),
    validityCheck: vi.fn(),
  },
}));

vi.mock('../../utils/api', () => ({
  setUser: vi.fn(),
  clearCookiesOnLogout: vi.fn(),
}));

vi.mock('shared/helpers/sessionStorage', () => ({
  default: { get: vi.fn(() => false), set: vi.fn(), remove: vi.fn() },
}));

vi.mock('dashboard/constants/sessionStorage', () => ({
  SESSION_STORAGE_KEYS: { IMPERSONATION_USER: 'impersonation_user' },
}));

import { useAuthStore } from '../useAuthStore';

describe('useAuthStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('initial state has no current user id', () => {
    const store = useAuthStore();
    expect(store.currentUser.id).toBeNull();
    expect(store.isLoggedIn).toBe(false);
  });

  it('isLoggedIn true after setting user', () => {
    const store = useAuthStore();
    store.currentUser = { id: 42, accounts: [], account_id: null };
    expect(store.isLoggedIn).toBe(true);
    expect(store.getCurrentUserID).toBe(42);
  });

  it('setCurrentAccountId stores account id', () => {
    const store = useAuthStore();
    store.setCurrentAccountId('7');
    expect(store.currentAccountId).toBe(7);
  });

  it('logout clears currentUser', () => {
    const store = useAuthStore();
    store.currentUser = { id: 1, accounts: [], account_id: 1 };
    store.logout();
    expect(store.currentUser.id).toBeNull();
  });
});
