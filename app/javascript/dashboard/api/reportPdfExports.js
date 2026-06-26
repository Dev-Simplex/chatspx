/* global axios */
import ApiClient from './ApiClient';

class ReportPdfExportsAPI extends ApiClient {
  constructor() {
    super('report_pdf_exports', { accountScoped: true });
  }

  // reportType: 'nps' | ... ; filters: { from, to, user_ids, inbox_id, team_id, funnel_id }
  create({
    reportType,
    from,
    to,
    user_ids,
    inbox_id,
    team_id,
    funnel_id,
  } = {}) {
    return axios.post(this.url, {
      report_type: reportType,
      since: from,
      until: to,
      user_ids,
      inbox_id,
      team_id,
      funnel_id,
    });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }
}

export default new ReportPdfExportsAPI();
