import types from '../../kanban/mutation-types';
import { mutations } from '../../kanban/mutations';

describe('#kanban mutations', () => {
  describe('#SET_SCHEDULED_MESSAGES', () => {
    it('replaces scheduled messages state and removes stale items', () => {
      const state = {
        scheduledMessages: {
          1: { id: 1, message: 'stale' },
        },
        scheduledById: {
          1: { id: 1, message: 'stale' },
        },
        scheduledTimeline: [1],
      };

      mutations[types.SET_SCHEDULED_MESSAGES](state, [
        {
          id: 2,
          message: 'fresh',
          conversation_id: 42,
        },
      ]);

      expect(Object.keys(state.scheduledMessages)).toEqual(['2']);
      expect(state.scheduledMessages[2]).toMatchObject({
        id: 2,
        message: 'fresh',
        conversationId: 42,
      });
      expect(state.scheduledById[2]).toMatchObject({
        id: 2,
        message: 'fresh',
      });
      expect(state.scheduledTimeline).toEqual([2]);
    });
  });

  describe('#UPSERT_SCHEDULED_MESSAGES_PAGE', () => {
    it('appends page preserving unique ids and descending time order', () => {
      const state = {
        scheduledMessages: {},
        scheduledById: {},
        scheduledTimeline: [],
      };

      mutations[types.UPSERT_SCHEDULED_MESSAGES_PAGE](state, {
        append: false,
        messages: [
          { id: 1, scheduled_at: '2026-02-01T10:00:00.000Z' },
          { id: 2, scheduled_at: '2026-02-02T10:00:00.000Z' },
        ],
      });

      mutations[types.UPSERT_SCHEDULED_MESSAGES_PAGE](state, {
        append: true,
        messages: [
          { id: 3, scheduled_at: '2026-02-03T10:00:00.000Z' },
          { id: 2, scheduled_at: '2026-02-02T10:00:00.000Z' },
        ],
      });

      expect(state.scheduledTimeline).toEqual([3, 2, 1]);
      expect(Object.keys(state.scheduledById)).toEqual(['1', '2', '3']);
    });
  });

  describe('#UPSERT_STAGE_ITEMS', () => {
    it('deduplicates by phone at ingestion and keeps the most recent item', () => {
      const state = {
        funnels: {},
        funnelStages: {},
        funnelItems: {},
        stageItems: {},
        stageMeta: {},
        stageDedupeIndex: {},
        scheduledMessages: {},
        activeFunnelId: null,
        viewMode: 'kanban',
        wahaInboxes: [],
        uiFlags: {},
      };

      mutations[types.UPSERT_STAGE_ITEMS](state, {
        funnelId: 1,
        stageId: 10,
        append: false,
        items: [
          {
            id: 100,
            funnel_id: 1,
            funnel_stage_id: 10,
            conversation_id: 501,
            created_at: '2026-01-01T10:00:00.000Z',
            conversation: {
              id: 501,
              last_activity_at: '2026-01-01T10:00:00.000Z',
              contact: { phone_number: '+55 11 99888-0000' },
            },
          },
          {
            id: 101,
            funnel_id: 1,
            funnel_stage_id: 10,
            conversation_id: 502,
            created_at: '2026-01-01T10:05:00.000Z',
            conversation: {
              id: 502,
              last_activity_at: '2026-01-01T10:05:00.000Z',
              contact: { phone_number: '5511998880000' },
            },
          },
        ],
      });

      expect(state.stageItems['1:10']).toEqual([101]);
      expect(state.funnelItems[101]).toBeTruthy();
      expect(state.funnelItems[100]).toBeUndefined();
    });
  });

  describe('#UPDATE_FUNNEL_ITEM', () => {
    it('moves item locally between stages without requiring a full refetch', () => {
      const state = {
        funnels: {},
        funnelStages: {},
        funnelItems: {
          200: {
            id: 200,
            funnelId: 1,
            funnelStageId: 10,
            conversation: {
              id: 900,
              lastActivityAt: '2026-01-01T10:00:00.000Z',
            },
          },
        },
        stageItems: {
          '1:10': [200],
        },
        stageMeta: {},
        stageDedupeIndex: {
          '1:10': {
            'conversation:900': 200,
          },
        },
        scheduledMessages: {},
        activeFunnelId: null,
        viewMode: 'kanban',
        wahaInboxes: [],
        uiFlags: {},
      };

      mutations[types.UPDATE_FUNNEL_ITEM](state, {
        id: 200,
        funnel_id: 1,
        funnel_stage_id: 11,
        conversation_id: 900,
        conversation: {
          id: 900,
          last_activity_at: '2026-01-01T10:10:00.000Z',
        },
      });

      expect(state.stageItems['1:10']).toEqual([]);
      expect(state.stageItems['1:11']).toEqual([200]);
      expect(state.funnelItems[200].funnelStageId).toBe(11);
    });
  });
});
