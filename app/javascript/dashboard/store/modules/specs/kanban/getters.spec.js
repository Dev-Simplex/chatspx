import { getters } from '../../kanban/getters';

describe('#kanban getters', () => {
  describe('#getFunnelItems', () => {
    it('reads items by stage index without scanning global state fallback', () => {
      const state = {
        stageItems: {
          '1:10': [100],
        },
        funnelItems: {
          100: { id: 100, funnelId: 1, funnelStageId: 10 },
          101: { id: 101, funnelId: 1, funnelStageId: 10 },
        },
      };

      const items = getters.getFunnelItems(state)(1, 10);
      expect(items.map(item => item.id)).toEqual([100]);
    });

    it('returns empty list when stage index was not loaded yet', () => {
      const state = {
        stageItems: {},
        funnelItems: {
          200: { id: 200, funnelId: 1, funnelStageId: 20 },
        },
      };

      expect(getters.getFunnelItems(state)(1, 20)).toEqual([]);
    });
  });

  describe('#getStageMeta', () => {
    it('returns default stage meta for unknown stage', () => {
      const state = { stageMeta: {} };
      expect(getters.getStageMeta(state)(1, 2)).toEqual({
        hasMore: false,
        nextCursor: null,
        isLoading: false,
        loaded: false,
        error: false,
        limit: null,
      });
    });
  });

  describe('#getScheduledMessagesByConversation', () => {
    it('matches by conversation id with number and string values', () => {
      const state = {
        scheduledMessages: {
          1: { id: 1, conversationId: 10, status: 'pending' },
          2: { id: 2, conversationId: '10', status: 'pending' },
          3: { id: 3, conversationId: 11, status: 'pending' },
        },
      };

      const messages = getters.getScheduledMessagesByConversation(state)(10);
      const ids = messages.map(message => message.id);

      expect(ids).toEqual([1, 2]);
    });
  });

  describe('#getScheduledMeta', () => {
    it('returns scheduled meta defaults when timeline was not initialized', () => {
      const state = {};
      expect(getters.getScheduledMeta(state)).toEqual({
        hasMore: false,
        nextCursor: null,
        limit: 50,
        loaded: false,
        error: false,
      });
    });
  });
});
