import { describe, it, expect, vi } from 'vitest';
import ConversationAction from '../ConversationAction.vue';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
  useTrack: vi.fn(),
}));

const { computed, methods, mounted } = ConversationAction;

const assistants = [
  {
    id: 10,
    name: 'Vendedora IA',
    avatar_url: 'https://example.com/ia.png',
    agent_bot_id: 7,
    inbox_ids: [1, 2],
  },
  {
    // sem espelho (sync falhou) — nunca entra no dropdown
    id: 11,
    name: 'Sem Espelho',
    avatar_url: null,
    agent_bot_id: null,
    inbox_ids: [1],
  },
  {
    // não elegível à inbox da conversa
    id: 12,
    name: 'Outra Inbox',
    avatar_url: null,
    agent_bot_id: 9,
    inbox_ids: [3],
  },
];

describe('ConversationAction computed', () => {
  describe('aiAgentsList', () => {
    it('keeps only assistants with a mirror bot eligible for the conversation inbox', () => {
      const list = computed.aiAgentsList.call({
        currentChat: { inbox_id: 1 },
        captainAssistants: assistants,
      });

      expect(list).toEqual([
        {
          id: 7,
          name: 'Vendedora IA',
          thumbnail: 'https://example.com/ia.png',
          assistantId: 10,
        },
      ]);
    });

    it('returns an empty list when there are no assistants', () => {
      const list = computed.aiAgentsList.call({
        currentChat: { inbox_id: 1 },
        captainAssistants: undefined,
      });

      expect(list).toEqual([]);
    });
  });

  describe('assignedAgent', () => {
    it('ignores an AI (agent_bot) assignee', () => {
      const result = computed.assignedAgent.call({
        currentChat: {
          meta: {
            assignee: { id: 7, name: 'Vendedora IA', type: 'agent_bot' },
          },
        },
      });

      expect(result).toBeNull();
    });

    it('returns a human assignee', () => {
      const human = { id: 3, name: 'Paulo' };
      const result = computed.assignedAgent.call({
        currentChat: { meta: { assignee: human } },
      });

      expect(result).toEqual(human);
    });

    it('returns null without an assignee', () => {
      const result = computed.assignedAgent.call({ currentChat: { meta: {} } });

      expect(result).toBeNull();
    });
  });

  describe('assignedAIAgent', () => {
    it('returns the assignee only when it is an agent_bot', () => {
      const bot = { id: 7, name: 'Vendedora IA', type: 'agent_bot' };
      expect(
        computed.assignedAIAgent.call({
          currentChat: { meta: { assignee: bot } },
        })
      ).toEqual(bot);
      expect(
        computed.assignedAIAgent.call({
          currentChat: { meta: { assignee: { id: 3, name: 'Paulo' } } },
        })
      ).toBeNull();
    });
  });

  describe('isAdminUser', () => {
    it('is true only for administrators', () => {
      expect(computed.isAdminUser.call({ currentRole: 'administrator' })).toBe(
        true
      );
      expect(computed.isAdminUser.call({ currentRole: 'agent' })).toBe(false);
    });
  });
});

describe('ConversationAction methods', () => {
  describe('onClickAssignAIAgent', () => {
    const buildVm = (overrides = {}) => ({
      currentChat: { id: 99 },
      assignedAIAgent: null,
      $store: { dispatch: vi.fn().mockResolvedValue() },
      $t: key => key,
      ...overrides,
    });

    it('dispatches assignAIAgent with the mirror bot id', async () => {
      const vm = buildVm();
      await methods.onClickAssignAIAgent.call(vm, { id: 7 });

      expect(vm.$store.dispatch).toHaveBeenCalledWith('assignAIAgent', {
        conversationId: 99,
        agentBotId: 7,
        rethrow: true,
      });
    });

    it('is a no-op without an id (no None option — D-11)', async () => {
      const vm = buildVm();
      await methods.onClickAssignAIAgent.call(vm, { id: null });

      expect(vm.$store.dispatch).not.toHaveBeenCalled();
    });

    it('is a no-op when the same AI agent is already assigned', async () => {
      const vm = buildVm({ assignedAIAgent: { id: 7, type: 'agent_bot' } });
      await methods.onClickAssignAIAgent.call(vm, { id: 7 });

      expect(vm.$store.dispatch).not.toHaveBeenCalled();
    });

    it('does not bubble the error when the dispatch fails', async () => {
      const vm = buildVm({
        $store: { dispatch: vi.fn().mockRejectedValue(new Error('422')) },
      });

      await expect(
        methods.onClickAssignAIAgent.call(vm, { id: 7 })
      ).resolves.toBeUndefined();
    });
  });
});

describe('ConversationAction mounted', () => {
  it('fetches captain assistants for admins only', () => {
    const dispatch = vi.fn();
    mounted.call({ isAdminUser: true, $store: { dispatch } });
    expect(dispatch).toHaveBeenCalledWith('captainAssistants/get');

    dispatch.mockClear();
    mounted.call({ isAdminUser: false, $store: { dispatch } });
    expect(dispatch).not.toHaveBeenCalled();
  });
});
