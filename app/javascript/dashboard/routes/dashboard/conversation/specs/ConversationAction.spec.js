import { describe, it, expect, vi } from 'vitest';
import { useAlert } from 'dashboard/composables';
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

describe('ConversationAction takeover path (dropdown 422)', () => {
  const build422 = (meta = {}) => ({
    response: { data: { error_code: 'takeover_request_required', meta } },
  });

  const buildVm = (overrides = {}) => {
    const vm = {
      takeoverGate: null,
      isRequestingTakeover: false,
      currentChat: { id: 99, meta: {} },
      $refs: { attendanceDialogRef: { open: vi.fn(), close: vi.fn() } },
      $store: { dispatch: vi.fn().mockResolvedValue() },
      $t: key => key,
      leaveConversationIfAccessLost: vi.fn(),
      ...overrides,
    };
    // métodos que um método chama no próprio componente precisam existir no vm
    vm.offerTakeoverRequest = methods.offerTakeoverRequest.bind(vm);
    vm.takeoverErrorMessage = methods.takeoverErrorMessage.bind(vm);
    return vm;
  };

  it('offerTakeoverRequest opens the dialog and builds the gate for a takeover 422', () => {
    const vm = buildVm();
    const result = methods.offerTakeoverRequest.call(
      vm,
      build422({
        current_assignee: { id: 5, name: 'Ana' },
        team: { id: 2, name: 'suporte' },
        existing_request: null,
      }),
      99
    );

    expect(result).toBe(true);
    expect(vm.$refs.attendanceDialogRef.open).toHaveBeenCalled();
    expect(vm.takeoverGate.attendance.id).toBe(99);
    expect(vm.takeoverGate.attendance.assignee.name).toBe('Ana');
    expect(vm.takeoverGate.attendance.canRequest).toBe(true);
    expect(vm.takeoverGate.attendance.canOpen).toBe(false);
  });

  it('offerTakeoverRequest ignores a non-takeover error', () => {
    const vm = buildVm();
    const result = methods.offerTakeoverRequest.call(
      vm,
      { response: { data: { error_code: 'something_else' } } },
      99
    );
    expect(result).toBe(false);
    expect(vm.$refs.attendanceDialogRef.open).not.toHaveBeenCalled();
  });

  it('offerTakeoverRequest marks a pending request from meta.existing_request', () => {
    const vm = buildVm();
    methods.offerTakeoverRequest.call(
      vm,
      build422({ existing_request: { id: 42 } }),
      99
    );
    expect(vm.takeoverGate.attendance.myPendingRequestId).toBe(42);
    expect(vm.takeoverGate.attendance.canRequest).toBe(false);
  });

  it('assignAgentDirect offers Solicitar on a takeover 422 instead of the generic failure', async () => {
    useAlert.mockClear();
    const vm = buildVm({
      $store: { dispatch: vi.fn().mockRejectedValue(build422()) },
    });
    await methods.assignAgentDirect.call(vm, { id: 3 });

    expect(vm.$refs.attendanceDialogRef.open).toHaveBeenCalled();
    expect(useAlert).not.toHaveBeenCalledWith(
      'CONVERSATION.CHANGE_AGENT_FAILED'
    );
  });

  it('assignAgentDirect falls back to the generic alert on a non-takeover error', async () => {
    useAlert.mockClear();
    const vm = buildVm({
      $store: {
        dispatch: vi.fn().mockRejectedValue({ response: { data: {} } }),
      },
    });
    await methods.assignAgentDirect.call(vm, { id: 3 });

    expect(vm.$refs.attendanceDialogRef.open).not.toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalledWith('CONVERSATION.CHANGE_AGENT_FAILED');
  });

  it('onTakeoverRequest dispatches create and clears the gate', async () => {
    useAlert.mockClear();
    const vm = buildVm({ takeoverGate: { attendance: { id: 99 } } });
    await methods.onTakeoverRequest.call(vm);

    expect(vm.$store.dispatch).toHaveBeenCalledWith('takeoverRequests/create', {
      conversationId: 99,
    });
    expect(useAlert).toHaveBeenCalledWith('CONVERSATION.TAKEOVER_REQUEST.SENT');
    expect(vm.takeoverGate).toBeNull();
  });

  it('takeoverErrorMessage falls back to the generic message for a missing key', () => {
    // vue-i18n devolve a própria chave quando falta
    const vm = { $t: key => key };
    const msg = methods.takeoverErrorMessage.call(vm, {
      response: { data: { error_code: 'weird_code' } },
    });
    expect(msg).toBe('CONVERSATION.REPLY_GATE_DIALOG.ERROR');
  });

  it('takeoverErrorMessage returns the mapped message for a known code', () => {
    const vm = {
      $t: key =>
        key.endsWith('TAKEOVER_REQUEST_EXISTS') ? 'Você já tem um pedido' : key,
    };
    const msg = methods.takeoverErrorMessage.call(vm, {
      response: { data: { error_code: 'takeover_request_exists' } },
    });
    expect(msg).toBe('Você já tem um pedido');
  });
});

describe('ConversationAction mounted', () => {
  it('fetches captain assistants for admins only', () => {
    // mockResolvedValue: mounted encadeia .catch() no dispatch (guarda defensiva),
    // então o mock precisa devolver uma promise.
    const dispatch = vi.fn().mockResolvedValue();
    mounted.call({ isAdminUser: true, $store: { dispatch } });
    expect(dispatch).toHaveBeenCalledWith('captainAssistants/get');

    dispatch.mockClear();
    mounted.call({ isAdminUser: false, $store: { dispatch } });
    expect(dispatch).not.toHaveBeenCalled();
  });
});
