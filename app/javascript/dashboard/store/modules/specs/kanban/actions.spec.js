import types from '../../kanban/mutation-types';
import { actions } from '../../kanban/actions';
import KanbanAPI from '../../../../api/kanban';

vi.mock('../../../../api/kanban', () => ({
  default: {
    getFunnelItems: vi.fn(),
    getScheduledMessages: vi.fn(),
    createScheduledMessage: vi.fn(),
    updateScheduledMessage: vi.fn(),
    deleteScheduledMessage: vi.fn(),
    createItem: vi.fn(),
    updateItem: vi.fn(),
    reorderItems: vi.fn(),
  },
}));

describe('#kanban actions', () => {
  const commit = vi.fn();
  const dispatch = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('#fetchScheduledMessagesPage', () => {
    it('requests cursor payload and commits page/meta state', async () => {
      KanbanAPI.getScheduledMessages.mockResolvedValue({
        data: {
          payload: [{ id: 1, message: 'hi', status: 'pending' }],
          meta: {
            has_more: true,
            next_cursor: 'cursor-2',
            limit: 50,
            status: 'all',
            from: '2026-01-01T00:00:00.000Z',
            to: '2026-03-01T00:00:00.000Z',
          },
        },
      });

      await actions.fetchScheduledMessagesPage(
        {
          commit,
          getters: {
            getScheduledFilters: {
              status: 'all',
              conversationId: null,
              from: '2026-01-01T00:00:00.000Z',
              to: '2026-03-01T00:00:00.000Z',
              limit: 50,
            },
          },
        },
        {
          mode: 'cursor',
          status: 'all',
          from: '2026-01-01T00:00:00.000Z',
          to: '2026-03-01T00:00:00.000Z',
          limit: 50,
          append: false,
        }
      );

      expect(KanbanAPI.getScheduledMessages).toHaveBeenCalledWith({
        mode: 'cursor',
        conversationId: null,
        status: 'all',
        from: '2026-01-01T00:00:00.000Z',
        to: '2026-03-01T00:00:00.000Z',
        limit: 50,
        cursor: null,
      });
      expect(commit).toHaveBeenCalledWith(types.SET_SCHEDULED_FILTERS, {
        status: 'all',
        conversationId: null,
        from: '2026-01-01T00:00:00.000Z',
        to: '2026-03-01T00:00:00.000Z',
        limit: 50,
      });
      expect(commit).toHaveBeenCalledWith(
        types.UPSERT_SCHEDULED_MESSAGES_PAGE,
        {
          messages: [{ id: 1, message: 'hi', status: 'pending' }],
          append: false,
        }
      );
      expect(commit).toHaveBeenCalledWith(types.SET_SCHEDULED_META, {
        hasMore: true,
        nextCursor: 'cursor-2',
        limit: 50,
        loaded: true,
        error: false,
        status: 'all',
        from: '2026-01-01T00:00:00.000Z',
        to: '2026-03-01T00:00:00.000Z',
      });
    });

    it('falls back to legacy scheduled API when kanban_ux_v2 is disabled', async () => {
      KanbanAPI.getScheduledMessages.mockResolvedValue({ data: [] });

      await actions.fetchScheduledMessagesPage(
        {
          commit,
          getters: {
            getScheduledFilters: {
              status: 'all',
              conversationId: null,
              from: null,
              to: null,
              limit: 50,
            },
          },
          rootState: {
            route: {
              params: { accountId: '1' },
            },
          },
          rootGetters: {
            'accounts/isFeatureEnabledonAccount': vi.fn(() => false),
          },
        },
        {
          mode: 'cursor',
          status: 'all',
          append: false,
        }
      );

      expect(KanbanAPI.getScheduledMessages).toHaveBeenCalledWith({
        mode: null,
        conversationId: null,
        status: 'all',
        from: expect.any(String),
        to: expect.any(String),
        limit: 50,
        cursor: null,
      });
    });
  });

  describe('#bootstrapFunnel', () => {
    it('boots first page per non-resolved stage', async () => {
      const localDispatch = vi.fn(() => Promise.resolve());
      const getters = {
        getFunnelStages: vi.fn(() => [
          { id: 10, name: 'Novo', automationType: 'open' },
          { id: 11, name: 'Em andamento', automationType: 'pending' },
          { id: 12, name: 'Resolvidos', automationType: 'resolved' },
        ]),
      };

      await actions.bootstrapFunnel(
        { commit, dispatch: localDispatch, getters },
        { funnelId: 7, excludeAutomationType: 'resolved', limit: 30 }
      );

      expect(localDispatch).toHaveBeenCalledTimes(2);
      expect(localDispatch).toHaveBeenNthCalledWith(1, 'fetchFunnelItemsPage', {
        funnelId: 7,
        stageId: 10,
        excludeAutomationType: 'resolved',
        limit: 30,
        append: false,
      });
      expect(localDispatch).toHaveBeenNthCalledWith(2, 'fetchFunnelItemsPage', {
        funnelId: 7,
        stageId: 11,
        excludeAutomationType: 'resolved',
        limit: 30,
        append: false,
      });
    });
  });

  describe('#fetchFunnelItems', () => {
    it('appends using cursor metadata when merge is true', async () => {
      await actions.fetchFunnelItems(
        {
          commit,
          dispatch,
          getters: {
            getStageMeta: vi.fn(() => ({ nextCursor: 'cursor-token' })),
          },
        },
        {
          funnelId: 9,
          stageId: 99,
          merge: true,
        }
      );

      expect(dispatch).toHaveBeenCalledWith('fetchFunnelItemsPage', {
        funnelId: 9,
        stageId: 99,
        excludeAutomationType: undefined,
        cursor: 'cursor-token',
        limit: 30,
        append: true,
      });
    });
  });

  describe('#bootstrapView', () => {
    it('skips refetch when the target view is already bootstrapped', async () => {
      const localDispatch = vi.fn();

      await actions.bootstrapView(
        {
          commit,
          dispatch: localDispatch,
          getters: {
            getViewMode: 'kanban',
            getViewBootstrap: {
              kanbanLoaded: true,
              listLoaded: false,
              calendarLoaded: false,
              listQueueStageIds: [],
            },
          },
        },
        {
          view: 'kanban',
          funnelId: 22,
          force: false,
        }
      );

      expect(localDispatch).not.toHaveBeenCalled();
    });
  });

  describe('#updateItem', () => {
    it('throws and does not commit when API returns an error', async () => {
      const apiError = new Error('unprocessable');
      KanbanAPI.updateItem.mockRejectedValue(apiError);

      await expect(
        actions.updateItem(
          { commit },
          {
            funnelId: 22,
            itemId: 2528,
            data: { funnel_stage_id: 44 },
          }
        )
      ).rejects.toThrow('unprocessable');

      expect(commit).not.toHaveBeenCalledWith(
        types.UPDATE_FUNNEL_ITEM,
        expect.anything()
      );
    });
  });

  describe('#createItem', () => {
    it('commits add mutation with API response payload', async () => {
      KanbanAPI.createItem.mockResolvedValue({
        data: {
          id: 303,
          funnel_id: 22,
          funnel_stage_id: 44,
          conversation_id: 501,
        },
      });

      await actions.createItem(
        { commit },
        {
          funnelId: 22,
          data: {
            conversation_id: 501,
            funnel_stage_id: 44,
          },
        }
      );

      expect(KanbanAPI.createItem).toHaveBeenCalledWith(22, {
        conversation_id: 501,
        funnel_stage_id: 44,
      });
      expect(commit).toHaveBeenCalledWith(types.ADD_FUNNEL_ITEM, {
        id: 303,
        funnel_id: 22,
        funnel_stage_id: 44,
        conversation_id: 501,
      });
    });
  });

  describe('#reorderItems', () => {
    const state = {
      funnelItems: {
        1: { id: 1, position: 1 },
        2: { id: 2, position: 2 },
        3: { id: 3, position: 3 },
      },
    };

    it('optimistically sets 1-based positions and persists the order', async () => {
      KanbanAPI.reorderItems.mockResolvedValue({});

      await actions.reorderItems(
        { commit, state },
        { funnelId: 7, stageId: 9, itemIds: [3, 1, 2] }
      );

      expect(commit).toHaveBeenCalledWith(types.SET_FUNNEL_ITEM_POSITIONS, {
        positions: [
          { id: 3, position: 1 },
          { id: 1, position: 2 },
          { id: 2, position: 3 },
        ],
      });
      expect(KanbanAPI.reorderItems).toHaveBeenCalledWith(7, 9, [3, 1, 2]);
    });

    it('rolls back to the previous positions when the request fails', async () => {
      KanbanAPI.reorderItems.mockRejectedValue(new Error('boom'));

      await expect(
        actions.reorderItems(
          { commit, state },
          { funnelId: 7, stageId: 9, itemIds: [3, 1, 2] }
        )
      ).rejects.toThrow('boom');

      // last commit restores the snapshot captured before the optimistic update
      expect(commit).toHaveBeenLastCalledWith(types.SET_FUNNEL_ITEM_POSITIONS, {
        positions: [
          { id: 3, position: 3 },
          { id: 1, position: 1 },
          { id: 2, position: 2 },
        ],
      });
    });

    it('is a no-op when there are no valid ids', async () => {
      await actions.reorderItems(
        { commit, state },
        { funnelId: 7, stageId: 9, itemIds: [] }
      );
      expect(KanbanAPI.reorderItems).not.toHaveBeenCalled();
      expect(commit).not.toHaveBeenCalled();
    });
  });

  // Arrastar entre etapas: a lista do draggable é one-way, então sem otimismo o
  // card volta para a coluna de origem até o PATCH responder (0,26s a 1,63s
  // medidos no staging).
  describe('#moveItemToStage', () => {
    const buildState = () => ({
      funnelItems: {
        10: { id: 10, funnelStageId: 1, position: 5 },
        20: { id: 20, funnelStageId: 2, position: 3 },
        30: { id: 30, funnelStageId: 2, position: 8 },
      },
      stageItems: { '7:1': [10], '7:2': [20, 30] },
    });

    it('moves the card right away and only then persists', async () => {
      const state = buildState();
      KanbanAPI.updateItem.mockResolvedValue({ data: { id: 10 } });

      await actions.moveItemToStage(
        { commit, state },
        { funnelId: 7, itemId: 10, stageId: 2 }
      );

      // otimista: já commitou ANTES de chamar a API
      const [type, payload] = commit.mock.calls[0];
      expect(type).toBe(types.UPDATE_FUNNEL_ITEM);
      expect(payload).toMatchObject({ id: 10, funnelStageId: 2 });

      // A regra é "vai para o TOPO", não uma conta específica: a position tem que
      // ficar abaixo de TODAS as da etapa destino (é o que põe o card em primeiro).
      // Afirmar `position: 2` travaria a aritmética da fixture, não o comportamento.
      const positionsDoDestino = state.stageItems['7:2'].map(
        id => state.funnelItems[id].position
      );
      expect(payload.position).toBeLessThan(Math.min(...positionsDoDestino));

      expect(KanbanAPI.updateItem).toHaveBeenCalledWith(7, 10, {
        funnel_stage_id: 2,
      });
      // e a resposta do servidor continua sendo a autoridade
      expect(commit).toHaveBeenLastCalledWith(types.UPDATE_FUNNEL_ITEM, {
        id: 10,
      });
    });

    it('puts the card at position 1 when the target stage is empty', async () => {
      const state = buildState();
      state.stageItems['7:9'] = [];
      KanbanAPI.updateItem.mockResolvedValue({ data: { id: 10 } });

      await actions.moveItemToStage(
        { commit, state },
        { funnelId: 7, itemId: 10, stageId: 9 }
      );

      expect(commit).toHaveBeenNthCalledWith(1, types.UPDATE_FUNNEL_ITEM, {
        id: 10,
        funnelStageId: 9,
        position: 1,
      });
    });

    it('sends the card back to the original stage when the request fails', async () => {
      const state = buildState();
      KanbanAPI.updateItem.mockRejectedValue(new Error('boom'));

      await expect(
        actions.moveItemToStage(
          { commit, state },
          { funnelId: 7, itemId: 10, stageId: 2 }
        )
      ).rejects.toThrow('boom');

      expect(commit).toHaveBeenLastCalledWith(types.UPDATE_FUNNEL_ITEM, {
        id: 10,
        funnelStageId: 1,
        position: 5,
      });
    });

    it('does nothing when the card is already in the target stage', async () => {
      const state = buildState();

      await actions.moveItemToStage(
        { commit, state },
        { funnelId: 7, itemId: 10, stageId: 1 }
      );

      expect(commit).not.toHaveBeenCalled();
      expect(KanbanAPI.updateItem).not.toHaveBeenCalled();
    });

    it('does nothing for an unknown card', async () => {
      const state = buildState();

      await actions.moveItemToStage(
        { commit, state },
        { funnelId: 7, itemId: 999, stageId: 2 }
      );

      expect(commit).not.toHaveBeenCalled();
      expect(KanbanAPI.updateItem).not.toHaveBeenCalled();
    });
  });

  describe('#fetchFunnelItemsPage', () => {
    it('prevents concurrent request duplication for the same stage', async () => {
      let resolveRequest;
      const pendingRequest = new Promise(resolve => {
        resolveRequest = resolve;
      });

      KanbanAPI.getFunnelItems.mockReturnValue(pendingRequest);

      const context = {
        commit,
        getters: {
          getStageMeta: vi.fn(() => ({ isLoading: false })),
        },
        rootState: {
          route: {
            params: { accountId: '1' },
          },
        },
        rootGetters: {
          'accounts/isFeatureEnabledonAccount': vi.fn(() => true),
        },
      };

      const firstRequest = actions.fetchFunnelItemsPage(context, {
        funnelId: 5,
        stageId: 20,
      });
      const secondRequest = actions.fetchFunnelItemsPage(context, {
        funnelId: 5,
        stageId: 20,
      });

      expect(KanbanAPI.getFunnelItems).toHaveBeenCalledTimes(1);

      resolveRequest({
        data: {
          payload: [{ id: 1, funnel_stage_id: 20, funnel_id: 5 }],
          meta: {
            has_more: false,
            next_cursor: null,
            limit: 30,
          },
        },
      });

      const [firstResponse, secondResponse] = await Promise.all([
        firstRequest,
        secondRequest,
      ]);
      expect(firstResponse).toEqual(secondResponse);
    });
  });

  describe('#loadMoreScheduledMessages', () => {
    it('requests next cursor page using stored filters', async () => {
      const localDispatch = vi.fn();
      await actions.loadMoreScheduledMessages(
        {
          dispatch: localDispatch,
          getters: {
            getScheduledMeta: {
              hasMore: true,
              nextCursor: 'next-cursor',
              limit: 50,
            },
            getScheduledFilters: {
              status: 'all',
              conversationId: 99,
              from: '2026-01-01T00:00:00.000Z',
              to: '2026-03-01T00:00:00.000Z',
              limit: 50,
            },
          },
        },
        {}
      );

      expect(localDispatch).toHaveBeenCalledWith('fetchScheduledMessagesPage', {
        status: 'all',
        conversationId: 99,
        from: '2026-01-01T00:00:00.000Z',
        to: '2026-03-01T00:00:00.000Z',
        limit: 50,
        cursor: 'next-cursor',
        append: true,
      });
    });
  });

  describe('#updateScheduledMessage', () => {
    it('commits update loading states and mutation', async () => {
      KanbanAPI.updateScheduledMessage.mockResolvedValue({
        data: { id: 3, message: 'updated' },
      });

      await actions.updateScheduledMessage(
        { commit },
        { messageId: 3, data: { message: 'updated' } }
      );

      expect(KanbanAPI.updateScheduledMessage).toHaveBeenCalledWith(3, {
        message: 'updated',
      });
      expect(commit.mock.calls).toEqual([
        [types.SET_KANBAN_UI_FLAG, { isUpdating: true }],
        [types.UPDATE_SCHEDULED_MESSAGE, { id: 3, message: 'updated' }],
        [types.SET_KANBAN_UI_FLAG, { isUpdating: false }],
      ]);
    });
  });

  // ── Tempo real do board (task/kanban-tempo-real.md) ──────────────────
  describe('#applyRemoteMove', () => {
    const rootGetters = { getCurrentUserID: 7 };
    const remotePayload = (overrides = {}) => ({
      id: 10,
      funnel_id: 1,
      funnel_stage_id: 22,
      conversation_id: 500,
      moved_at: '2026-08-03T12:00:00.000Z',
      position: 0.5,
      is_task: false,
      account_id: 1,
      performer: { id: 9, name: 'Colega' },
      conversation: { id: 500, status: 'open', contact: { id: 3, name: 'Zé' } },
      ...overrides,
    });

    it('insere o card que o receptor nunca carregou', () => {
      const state = { activeFunnelId: 1, funnelItems: {} };

      actions.applyRemoteMove({ state, commit, rootGetters }, remotePayload());

      expect(commit).toHaveBeenCalledTimes(1);
      const [mutation, payload] = commit.mock.calls[0];
      expect(mutation).toBe(types.ADD_FUNNEL_ITEM);
      expect(payload.id).toBe(10);
      expect(payload.funnel_stage_id).toBe(22);
      // metadado de transporte não entra no store
      expect(payload.performer).toBeUndefined();
      expect(payload.account_id).toBeUndefined();
    });

    it('ignora payload magro demais para desenhar (VM ainda não deployada)', () => {
      const state = { activeFunnelId: 1, funnelItems: {} };

      actions.applyRemoteMove(
        { state, commit, rootGetters },
        remotePayload({ conversation: undefined, title: undefined })
      );

      expect(commit).not.toHaveBeenCalled();
    });

    it('reloca o card que já temos preservando o que o broadcast não traz', () => {
      const state = {
        activeFunnelId: 1,
        funnelItems: {
          10: {
            id: 10,
            funnelId: 1,
            funnelStageId: 21,
            movedAt: '2026-08-03T11:00:00.000Z',
            conversation: { id: 500, lastMessage: { content: 'oi' } },
          },
        },
      };

      actions.applyRemoteMove({ state, commit, rootGetters }, remotePayload());

      const [mutation, payload] = commit.mock.calls[0];
      expect(mutation).toBe(types.UPDATE_FUNNEL_ITEM);
      expect(payload.funnelStageId).toBe(22);
      expect(payload.position).toBe(0.5);
      expect(payload.conversation.lastMessage).toEqual({ content: 'oi' });
    });

    it('não reage a outro funil', () => {
      const state = { activeFunnelId: 2, funnelItems: {} };
      actions.applyRemoteMove({ state, commit, rootGetters }, remotePayload());
      expect(commit).not.toHaveBeenCalled();
    });

    it('ignora o eco da própria ação', () => {
      const state = { activeFunnelId: 1, funnelItems: {} };
      actions.applyRemoteMove(
        { state, commit, rootGetters },
        remotePayload({ performer: { id: 7 } })
      );
      expect(commit).not.toHaveBeenCalled();
    });

    it('é idempotente: mover para a etapa em que o card já está não commita', () => {
      const state = {
        activeFunnelId: 1,
        funnelItems: { 10: { id: 10, funnelId: 1, funnelStageId: 22 } },
      };
      actions.applyRemoteMove({ state, commit, rootGetters }, remotePayload());
      expect(commit).not.toHaveBeenCalled();
    });

    it('descarta move mais antigo que o estado local (last-write-wins)', () => {
      const state = {
        activeFunnelId: 1,
        funnelItems: {
          10: {
            id: 10,
            funnelId: 1,
            funnelStageId: 21,
            movedAt: '2026-08-03T13:00:00.000Z',
          },
        },
      };
      actions.applyRemoteMove({ state, commit, rootGetters }, remotePayload());
      expect(commit).not.toHaveBeenCalled();
    });

    it('nunca lança para fora do websocket', () => {
      expect(() =>
        actions.applyRemoteMove(
          { state: null, commit, rootGetters },
          remotePayload()
        )
      ).not.toThrow();
    });
  });
});
