import { useAgentIsolation } from '../useAgentIsolation';
import { useStore } from 'dashboard/composables/store';

vi.mock('dashboard/composables/store');

const buildStore = ({
  userId = 1,
  role = 'agent',
  accountId = 100,
  supervisedTeams = [],
  conversations = {},
} = {}) => ({
  getters: {
    getCurrentUser: { id: userId, accounts: [{ id: accountId, role }] },
    getCurrentAccount: { id: accountId },
    'teams/getSupervisedTeams': supervisedTeams,
    getConversationById: id => conversations[id],
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

  // Supervisão de time (F2/F4): o backend entrega TODAS as bolhas da conversa de um
  // time supervisionado, então o front não pode mascará-las com 🔒.
  describe('supervisão de time', () => {
    const chatOfTeam7 = { id: 55, meta: { team: { id: 7 } } };
    const supervisorStore = extras =>
      buildStore({
        userId: 1,
        supervisedTeams: [{ id: 7, name: 'Suporte' }],
        conversations: { 55: chatOfTeam7 },
        ...extras,
      });

    it('supervisor vê a mensagem de outro agente (conversa passada no 3º arg)', () => {
      useStore.mockReturnValue(supervisorStore());
      const { isMessageRestricted } = useAgentIsolation();
      expect(isMessageRestricted({ agent_id: 2 }, inboxOn, chatOfTeam7)).toBe(
        false
      );
    });

    it('supervisor vê a mensagem quando a conversa vem do store pelo conversation_id', () => {
      useStore.mockReturnValue(supervisorStore());
      const { isMessageRestricted } = useAgentIsolation();
      expect(
        isMessageRestricted({ agent_id: 2, conversation_id: 55 }, inboxOn)
      ).toBe(false);
    });

    it('supervisor NÃO é isento em conversa de time que ele não supervisiona', () => {
      useStore.mockReturnValue(supervisorStore());
      const { isMessageRestricted } = useAgentIsolation();
      const otherChat = { id: 56, meta: { team: { id: 9 } } };
      expect(isMessageRestricted({ agent_id: 2 }, inboxOn, otherChat)).toBe(
        true
      );
    });

    it('supervisor NÃO é isento em conversa sem time', () => {
      useStore.mockReturnValue(supervisorStore());
      const { isMessageRestricted } = useAgentIsolation();
      expect(isMessageRestricted({ agent_id: 2 }, inboxOn, { id: 57 })).toBe(
        true
      );
    });

    it('agente comum (sem supervisão) continua vendo 🔒 na mesma conversa', () => {
      useStore.mockReturnValue(
        buildStore({ userId: 1, conversations: { 55: chatOfTeam7 } })
      );
      const { isMessageRestricted } = useAgentIsolation();
      expect(isMessageRestricted({ agent_id: 2 }, inboxOn, chatOfTeam7)).toBe(
        true
      );
    });

    it('não consulta o store quando ninguém supervisiona nada', () => {
      const store = buildStore({ userId: 1 });
      const spy = vi.fn(() => chatOfTeam7);
      store.getters.getConversationById = spy;
      useStore.mockReturnValue(store);
      const { isMessageRestricted } = useAgentIsolation();
      expect(
        isMessageRestricted({ agent_id: 2, conversation_id: 55 }, inboxOn)
      ).toBe(true);
      expect(spy).not.toHaveBeenCalled();
    });
  });
});
