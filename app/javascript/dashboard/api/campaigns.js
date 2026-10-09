/* global axios */
import ApiClient from './ApiClient';

class CampaignsAPI extends ApiClient {
  constructor() {
    super('campaigns', { accountScoped: true });
  }

  // Agregado read-only do disparo ancorado nesta campanha (por campaign_id).
  // Usa o axios GLOBAL (configurado com auth), igual ao ApiClient — nao o import.
  getStats(id) {
    return axios.get(`${this.url}/${id}/stats`);
  }

  // Destinatarios que NAO receberam (falhou | bloqueado), paginado, com o motivo.
  getUndelivered(id, { type = null, page = 1 } = {}) {
    return axios.get(`${this.url}/${id}/undelivered`, {
      params: { type, page },
    });
  }

  // A mesma lista inteira em CSV (`;`, para o Excel em pt-BR).
  exportUndelivered(id, type = null) {
    return axios.get(`${this.url}/${id}/undelivered.csv`, {
      params: { type },
      responseType: 'blob',
    });
  }

  // Higiene da audiencia em DRY-RUN: devolve quem entra, quem sai e por que, sem
  // gravar destinatario nenhum. E o passo que impede montar disparo em cima de
  // lista errada — o nome do arquivo mente.
  audiencePreview(id, rows, blocklist = []) {
    return axios.post(`${this.url}/${id}/audience_preview`, {
      rows,
      blocklist,
    });
  }

  // Carrega a lista (upload) de destinatarios — rows: [{ name, phone }].
  uploadRecipients(id, rows, blocklist = []) {
    return axios.post(`${this.url}/${id}/recipients`, { rows, blocklist });
  }

  // Mesmos dois passos, com o publico vindo da BASE em vez de uma planilha. O backend
  // resolve o segmento em rows e entrega no mesmo lugar, entao a higiene e o preview sao
  // exatamente os do upload.
  segmentPreview(id, segmento) {
    return axios.post(`${this.url}/${id}/audience_preview`, { segmento });
  }

  segmentRecipients(id, segmento) {
    return axios.post(`${this.url}/${id}/recipients`, { segmento });
  }

  // Inicia/retoma o disparo (dispatch_status: running).
  startDispatch(id) {
    return axios.post(`${this.url}/${id}/start`);
  }

  // Pausa o disparo mantendo os pendentes.
  pauseDispatch(id) {
    return axios.post(`${this.url}/${id}/pause`);
  }
}

export default new CampaignsAPI();
