import types from '../../kanban/mutation-types';
import { mutations } from '../../kanban/mutations';

describe('#kanban mutations', () => {
  describe('#SET_SCHEDULED_MESSAGES', () => {
    it('replaces scheduled messages state and removes stale items', () => {
      const state = {
        scheduledMessages: {
          1: { id: 1, message: 'stale' },
        },
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
    });
  });

  describe('#UPDATE_SCHEDULED_MESSAGE', () => {
    it('upserts the scheduled message when it does not exist yet', () => {
      const state = {
        scheduledMessages: {},
      };

      mutations[types.UPDATE_SCHEDULED_MESSAGE](state, {
        id: 15,
        message: 'updated',
      });

      expect(state.scheduledMessages[15]).toMatchObject({
        id: 15,
        message: 'updated',
      });
    });
  });
});
