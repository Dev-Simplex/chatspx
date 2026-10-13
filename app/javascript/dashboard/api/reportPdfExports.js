/* global axios */
import ApiClient from './ApiClient';

class ReportPdfExportsAPI extends ApiClient {
  constructor() {
    super('report_pdf_exports', { accountScoped: true });
  }

  // reportType: 'nps' | ... ; filters: os mesmos da tela. Todo filtro que o controller aceita vai junto:
  // o PDF que deixava `business_hours`, `rating` e os filtros do SLA para tras saia diferente da tela.
  // `de`/`ate` são o período do Rodízio, mandados como a própria tela manda à API dela.
  create({
    reportType,
    from,
    to,
    user_ids,
    inbox_id,
    team_id,
    funnel_id,
    de,
    ate,
    status,
    business_hours,
    rating,
    assigned_agent_id,
    sla_policy_id,
    label_list,
  } = {}) {
    return axios.post(this.url, {
      report_type: reportType,
      since: from,
      until: to,
      user_ids,
      inbox_id,
      team_id,
      funnel_id,
      de,
      ate,
      status,
      business_hours,
      rating,
      assigned_agent_id,
      sla_policy_id,
      label_list,
    });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }
}

export default new ReportPdfExportsAPI();
