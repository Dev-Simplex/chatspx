/* global axios */
import ApiClient from './ApiClient';

class SummaryReportsAPI extends ApiClient {
  constructor() {
    super('summary_reports', { accountScoped: true, apiVersion: 'v2' });
  }

  getTeamReports({ since, until, businessHours, inboxId } = {}) {
    return axios.get(`${this.url}/team`, {
      params: {
        since,
        until,
        business_hours: businessHours,
        inbox_id: inboxId || undefined,
      },
    });
  }

  getAgentReports({ since, until, businessHours, inboxId } = {}) {
    return axios.get(`${this.url}/agent`, {
      params: {
        since,
        until,
        business_hours: businessHours,
        inbox_id: inboxId || undefined,
      },
    });
  }

  getAgentAssignmentReports({
    since,
    until,
    businessHours,
    teamId,
    inboxId,
  } = {}) {
    return axios.get(`${this.url}/agent_assignment`, {
      params: {
        since,
        until,
        business_hours: businessHours,
        team_id: teamId || undefined,
        inbox_id: inboxId || undefined,
      },
    });
  }

  // As atribuicoes por tras de um numero da tabela de Atribuicoes (painel de detalhe).
  getAgentAssignmentList({
    from,
    to,
    teamId,
    inboxId,
    kind,
    userId,
    toId,
    page = 1,
  } = {}) {
    return axios.get(`${this.url}/agent_assignment_list`, {
      params: {
        since: from,
        until: to,
        team_id: teamId || undefined,
        inbox_id: inboxId || undefined,
        kind,
        user_id: userId,
        to_id: toId || undefined,
        page,
      },
    });
  }

  getAgentAssignmentListCsv({
    from,
    to,
    teamId,
    inboxId,
    kind,
    userId,
    toId,
  } = {}) {
    return axios.get(`${this.url}/agent_assignment_list.csv`, {
      params: {
        since: from,
        until: to,
        team_id: teamId || undefined,
        inbox_id: inboxId || undefined,
        kind,
        user_id: userId,
        to_id: toId || undefined,
      },
    });
  }

  getInboxReports({ since, until, businessHours, inboxId } = {}) {
    return axios.get(`${this.url}/inbox`, {
      params: {
        since,
        until,
        business_hours: businessHours,
        inbox_id: inboxId || undefined,
      },
    });
  }

  getLabelReports({ since, until, businessHours, inboxId } = {}) {
    return axios.get(`${this.url}/label`, {
      params: {
        since,
        until,
        business_hours: businessHours,
        inbox_id: inboxId || undefined,
      },
    });
  }
}

export default new SummaryReportsAPI();
