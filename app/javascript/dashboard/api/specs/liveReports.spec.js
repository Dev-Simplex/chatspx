import liveReportsAPI from '../liveReports';
import ApiClient from '../ApiClient';

describe('#LiveReports API', () => {
  it('creates correct instance', () => {
    expect(liveReportsAPI).toBeInstanceOf(ApiClient);
    expect(liveReportsAPI.apiVersion).toBe('/api/v2');
    expect(liveReportsAPI).toHaveProperty('getConversationMetric');
    expect(liveReportsAPI).toHaveProperty('getGroupedConversations');
    expect(liveReportsAPI).toHaveProperty('getInServiceOverview');
    expect(liveReportsAPI).toHaveProperty('getInServiceConversations');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      get: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('#getInServiceOverview', () => {
      liveReportsAPI.getInServiceOverview({ team_id: 12 });
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v2/live_reports/in_service_overview',
        {
          params: { team_id: 12 },
        }
      );
    });

    it('#getInServiceConversations', () => {
      liveReportsAPI.getInServiceConversations({
        scope: 'agent',
        assignee_id: 34,
        limit: 5,
        cursor: 'cursor-value',
      });

      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v2/live_reports/in_service_conversations',
        {
          params: {
            scope: 'agent',
            assignee_id: 34,
            limit: 5,
            cursor: 'cursor-value',
          },
        }
      );
    });
  });
});
