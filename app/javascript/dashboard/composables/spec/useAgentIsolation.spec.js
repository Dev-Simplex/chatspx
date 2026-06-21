import { useAgentIsolation } from '../useAgentIsolation';
import { useStore } from 'dashboard/composables/store';

vi.mock('dashboard/composables/store');

const buildStore = ({ userId = 1, role = 'agent', accountId = 100 } = {}) => ({
  getters: {
    getCurrentUser: { id: userId, accounts: [{ id: accountId, role }] },
    getCurrentAccount: { id: accountId },
  },
});

describe('useAgentIsolation', () => {
  const inboxOn = { agent_message_isolation: true };
  const inboxOff = { agent_message_isolation: false };

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('returns false when isolation is disabled on the inbox', () => {
    useStore.mockReturnValue(buildStore());
    const { isMessageRestricted } = useAgentIsolation();
    expect(isMessageRestricted({ agent_id: 2 }, inboxOff)).toBe(false);
  });

  it('returns false for the current agent own message', () => {
    useStore.mockReturnValue(buildStore({ userId: 1 }));
    const { isMessageRestricted } = useAgentIsolation();
    expect(isMessageRestricted({ agent_id: 1 }, inboxOn)).toBe(false);
  });

  it('returns true for a message owned by another agent', () => {
    useStore.mockReturnValue(buildStore({ userId: 1 }));
    const { isMessageRestricted } = useAgentIsolation();
    expect(isMessageRestricted({ agent_id: 2 }, inboxOn)).toBe(true);
  });

  it('returns false for public messages (agent_id null)', () => {
    useStore.mockReturnValue(buildStore({ userId: 1 }));
    const { isMessageRestricted } = useAgentIsolation();
    expect(isMessageRestricted({ agent_id: null }, inboxOn)).toBe(false);
  });

  it('returns false for activity messages even from another agent', () => {
    useStore.mockReturnValue(buildStore({ userId: 1 }));
    const { isMessageRestricted } = useAgentIsolation();
    expect(isMessageRestricted({ agent_id: 2, message_type: 2 }, inboxOn)).toBe(
      false
    );
  });

  it('returns false for admins (they see everything)', () => {
    useStore.mockReturnValue(buildStore({ userId: 1, role: 'administrator' }));
    const { isMessageRestricted } = useAgentIsolation();
    expect(isMessageRestricted({ agent_id: 2 }, inboxOn)).toBe(false);
  });

  it('supports camelCase fields (agentId / agentMessageIsolation)', () => {
    useStore.mockReturnValue(buildStore({ userId: 1 }));
    const { isMessageRestricted } = useAgentIsolation();
    expect(
      isMessageRestricted({ agentId: 2 }, { agentMessageIsolation: true })
    ).toBe(true);
  });
});
