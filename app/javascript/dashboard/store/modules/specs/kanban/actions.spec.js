import types from '../../kanban/mutation-types';
import { actions } from '../../kanban/actions';
import KanbanAPI from '../../../../api/kanban';

vi.mock('../../../../api/kanban', () => ({
  default: {
    getScheduledMessages: vi.fn(),
    createScheduledMessage: vi.fn(),
    updateScheduledMessage: vi.fn(),
    deleteScheduledMessage: vi.fn(),
  },
}));

describe('#kanban actions', () => {
  const commit = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('#fetchScheduledMessages', () => {
    it('requests pending messages by default and commits loading states', async () => {
      KanbanAPI.getScheduledMessages.mockResolvedValue({
        data: [{ id: 1, message: 'hi' }],
      });

      await actions.fetchScheduledMessages({ commit });

      expect(KanbanAPI.getScheduledMessages).toHaveBeenCalledWith({
        conversationId: null,
        status: 'pending',
      });
      expect(commit.mock.calls).toEqual([
        [types.SET_KANBAN_UI_FLAG, { isFetching: true }],
        [types.SET_SCHEDULED_MESSAGES, [{ id: 1, message: 'hi' }]],
        [types.SET_KANBAN_UI_FLAG, { isFetching: false }],
      ]);
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
