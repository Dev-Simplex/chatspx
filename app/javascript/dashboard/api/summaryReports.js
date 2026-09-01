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
