/* global axios */
import ApiClient from './ApiClient';

class ReportPdfExportsAPI extends ApiClient {
  constructor() {
    super('report_pdf_exports', { accountScoped: true });
  }

  // reportType: 'nps' | ... ; filters: { from, to, ...recorte da tela }
  //
  // Só `from`/`to` são traduzidos (a API fala `since`/`until`); o resto do recorte segue adiante
  // como veio. A lista fixa que existia aqui descartava em silêncio todo filtro que a tela
  // ganhasse depois — foi o que aconteceu com o rodízio: filtrar por agente na tela e baixar o
  // PDF devolvia a conta inteira, sem erro nenhum. Quem decide o que vale é o `filter_params` do
  // controller, que ignora chave fora do whitelist.
  create({ reportType, from, to, ...recorte } = {}) {
    return axios.post(this.url, {
      report_type: reportType,
      since: from,
      until: to,
      ...recorte,
    });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }
}

export default new ReportPdfExportsAPI();
