/* global axios */
import ApiClient from './ApiClient';

class LiveReportsAPI extends ApiClient {
  constructor() {
    super('live_reports', { accountScoped: true, apiVersion: 'v2' });
  }

  getConversationMetric(params = {}) {
    return axios.get(`${this.url}/conversation_metrics`, { params });
  }

  getGroupedConversations({ groupBy, inboxId } = { groupBy: 'assignee_id' }) {
    return axios.get(`${this.url}/grouped_conversation_metrics`, {
      params: { group_by: groupBy, inbox_id: inboxId || undefined },
    });
  }

  // As conversas por tras de um numero da Visao geral (painel de detalhe).
  getConversationList({ metric, teamId, inboxId, assigneeId, page = 1 } = {}) {
    return axios.get(`${this.url}/conversation_list`, {
      params: {
        metric,
        team_id: teamId || undefined,
        inbox_id: inboxId || undefined,
        assignee_id: assigneeId || undefined,
        page,
      },
    });
  }

  getConversationListCsv({ metric, teamId, inboxId, assigneeId } = {}) {
    return axios.get(`${this.url}/conversation_list.csv`, {
      params: {
        metric,
        team_id: teamId || undefined,
        inbox_id: inboxId || undefined,
        assignee_id: assigneeId || undefined,
      },
    });
  }

  getInServiceOverview(params = {}) {
    return axios.get(`${this.url}/in_service_overview`, { params });
  }

  getInServiceConversations(params = {}) {
    return axios.get(`${this.url}/in_service_conversations`, { params });
  }
}

export default new LiveReportsAPI();
