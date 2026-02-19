import kanbanAPI from '../kanban';
import ApiClient from '../ApiClient';

describe('#KanbanApi', () => {
  it('creates correct instance', () => {
    expect(kanbanAPI).toBeInstanceOf(ApiClient);
    expect(kanbanAPI).toHaveProperty('getScheduledMessages');
    expect(kanbanAPI).toHaveProperty('createScheduledMessage');
    expect(kanbanAPI).toHaveProperty('updateScheduledMessage');
    expect(kanbanAPI).toHaveProperty('deleteScheduledMessage');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const originalPathname = window.location.pathname;
    const axiosMock = {
      post: vi.fn(() => Promise.resolve()),
      get: vi.fn(() => Promise.resolve()),
      patch: vi.fn(() => Promise.resolve()),
      delete: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
      window.history.pushState({}, '', '/app/accounts/3/kanban/22');
    });

    afterEach(() => {
      window.axios = originalAxios;
      window.history.pushState({}, '', originalPathname || '/');
      vi.clearAllMocks();
    });

    it('#getScheduledMessages uses all as default status', () => {
      kanbanAPI.getScheduledMessages();
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/3/scheduled_messages?status=all'
      );
    });

    it('#getScheduledMessages sends full cursor filters', () => {
      kanbanAPI.getScheduledMessages({
        conversationId: 99,
        status: 'failed',
        mode: 'cursor',
        from: '2026-01-01T00:00:00.000Z',
        to: '2026-03-01T00:00:00.000Z',
        limit: 30,
        cursor: 'abc123',
      });
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/3/scheduled_messages?conversation_id=99&status=failed&mode=cursor&from=2026-01-01T00%3A00%3A00.000Z&to=2026-03-01T00%3A00%3A00.000Z&limit=30&cursor=abc123'
      );
    });

    it('#getFunnelItems serializes cursor params', () => {
      kanbanAPI.getFunnelItems(22, {
        stageId: 7,
        excludeAutomationType: 'resolved',
        mode: 'cursor',
        limit: 30,
        cursor: 'abc123',
      });

      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/3/funnels/22/funnel_items?stage_id=7&exclude_automation_type=resolved&mode=cursor&limit=30&cursor=abc123'
      );
    });

    it('#getFunnelItems keeps legacy pagination params when provided', () => {
      kanbanAPI.getFunnelItems(22, {
        stageId: 7,
        page: 2,
        perPage: 50,
      });

      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/3/funnels/22/funnel_items?stage_id=7&page=2&per_page=50'
      );
    });

    it('#updateScheduledMessage sends JSON payload wrapped in scheduled_message', () => {
      kanbanAPI.updateScheduledMessage(123, { message: 'Updated' });
      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/3/scheduled_messages/123',
        {
          scheduled_message: { message: 'Updated' },
        }
      );
    });

    it('#updateScheduledMessage sends FormData without JSON wrapping', () => {
      const payload = new FormData();
      payload.append('scheduled_message[message]', 'Updated');

      kanbanAPI.updateScheduledMessage(321, payload);
      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/3/scheduled_messages/321',
        payload
      );
    });
  });
});
