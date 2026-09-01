/* global axios */
import ApiClient from './ApiClient';

const getTimeOffset = () => -new Date().getTimezoneOffset() / 60;

class ReportsAPI extends ApiClient {
  constructor() {
    super('reports', { accountScoped: true, apiVersion: 'v2' });
  }

  getReports({
    metric,
    from,
    to,
    type = 'account',
    id,
    groupBy,
    businessHours,
    inboxId,
  }) {
    return axios.get(`${this.url}`, {
      params: {
        metric,
        since: from,
        until: to,
        type,
        id,
        group_by: groupBy,
        business_hours: businessHours,
        inbox_id: inboxId || undefined,
        timezone_offset: getTimeOffset(),
      },
    });
  }

  getSummary(
    since,
    until,
    // eslint-disable-next-line default-param-last
    type = 'account',
    id,
    groupBy,
    businessHours,
    inboxId
  ) {
    return axios.get(`${this.url}/summary`, {
      params: {
        since,
        until,
        type,
        id,
        group_by: groupBy,
        business_hours: businessHours,
        inbox_id: inboxId || undefined,
        timezone_offset: getTimeOffset(),
      },
    });
  }

  getConversationMetric(type = 'account', page = 1) {
    return axios.get(`${this.url}/conversations`, {
      params: {
        type,
        page,
      },
    });
  }

  getAgentReports({ from: since, to: until, businessHours, inboxId }) {
    return axios.get(`${this.url}/agents`, {
      params: {
        since,
        until,
        business_hours: businessHours,
        inbox_id: inboxId || undefined,
      },
    });
  }

  getConversationsSummaryReports({
    from: since,
    to: until,
    businessHours,
    inboxId,
  }) {
    return axios.get(`${this.url}/conversations_summary`, {
      params: {
        since,
        until,
        business_hours: businessHours,
        inbox_id: inboxId || undefined,
      },
    });
  }

  getConversationTrafficCSV({ daysBefore = 6 } = {}) {
    return axios.get(`${this.url}/conversation_traffic`, {
      params: { timezone_offset: getTimeOffset(), days_before: daysBefore },
    });
  }

  getLabelReports({ from: since, to: until, businessHours, inboxId }) {
    return axios.get(`${this.url}/labels`, {
      params: {
        since,
        until,
        business_hours: businessHours,
        inbox_id: inboxId || undefined,
      },
    });
  }

  getInboxReports({ from: since, to: until, businessHours, inboxId }) {
    return axios.get(`${this.url}/inboxes`, {
      params: {
        since,
        until,
        business_hours: businessHours,
        inbox_id: inboxId || undefined,
      },
    });
  }

  getTeamReports({ from: since, to: until, businessHours, inboxId }) {
    return axios.get(`${this.url}/teams`, {
      params: {
        since,
        until,
        business_hours: businessHours,
        inbox_id: inboxId || undefined,
      },
    });
  }

  getBotMetrics({ from, to } = {}) {
    return axios.get(`${this.url}/bot_metrics`, {
      params: { since: from, until: to },
    });
  }

  getBotSummary({ from, to, groupBy, businessHours } = {}) {
    return axios.get(`${this.url}/bot_summary`, {
      params: {
        since: from,
        until: to,
        type: 'account',
        group_by: groupBy,
        business_hours: businessHours,
      },
    });
  }

  getDrilldown({
    metric,
    bucketTimestamp,
    from,
    to,
    type = 'account',
    id,
    groupBy,
    businessHours,
    page,
    perPage,
    signal,
  }) {
    const requestConfig = {
      params: {
        metric,
        bucket_timestamp: bucketTimestamp,
        since: from,
        until: to,
        type,
        id,
        group_by: groupBy,
        business_hours: businessHours,
        timezone_offset: getTimeOffset(),
        page,
        per_page: perPage,
      },
    };

    if (signal) {
      requestConfig.signal = signal;
    }

    return axios.get(`${this.url}/drilldown`, requestConfig);
  }

  // Bloco 1.22 — de onde vieram os atendimentos no periodo.
  getConversationOrigin({ from, to } = {}) {
    return axios.get(`${this.baseUrl()}/origin_report`, {
      params: { since: from, until: to, timezone_offset: getTimeOffset() },
    });
  }

  // Bloco 4.18 — quantos leads perdemos e onde. So contagens: as respostas do visitante que
  // nao concluiu nunca saem da base por aqui.
  getPartialLeads({ from, to } = {}) {
    return axios.get(`${this.baseUrl()}/partial_lead_report`, {
      params: { since: from, until: to },
    });
  }
}

export default new ReportsAPI();
