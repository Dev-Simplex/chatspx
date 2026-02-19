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
});
