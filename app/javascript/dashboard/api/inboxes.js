/* global axios */
import CacheEnabledApiClient from './CacheEnabledApiClient';

class Inboxes extends CacheEnabledApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  // eslint-disable-next-line class-methods-use-this
  get cacheModelName() {
    return 'inbox';
  }

  getCampaigns(inboxId) {
    return axios.get(`${this.url}/${inboxId}/campaigns`);
  }

  deleteInboxAvatar(inboxId) {
    return axios.delete(`${this.url}/${inboxId}/avatar`);
  }

  /**
   * Bloco 3.19 — o BYTE do ícone do lançador.
   *
   * Vai por `multipart` no mesmo `PATCH` da inbox, e não por endpoint próprio:
   * assim herda as validações do modelo (teto de 20 KB e tipo) e a resposta já
   * é a inbox inteira, com `launcher_icon_url` preenchido.
   */
  uploadLauncherIcon(inboxId, file) {
    const formData = new FormData();
    formData.append('launcher_icon_image', file, file.name);
    return axios.patch(`${this.url}/${inboxId}`, formData);
  }

  deleteLauncherIcon(inboxId) {
    return axios.delete(`${this.url}/${inboxId}/launcher_icon`);
  }

  getAgentBot(inboxId) {
    return axios.get(`${this.url}/${inboxId}/agent_bot`);
  }

  setAgentBot(inboxId, botId) {
    return axios.post(`${this.url}/${inboxId}/set_agent_bot`, {
      agent_bot: botId,
    });
  }

  syncTemplates(inboxId) {
    return axios.post(`${this.url}/${inboxId}/sync_templates`);
  }

  /**
   * Bloco 4.13 — rotação do segredo com que o webhook da inbox de API é assinado.
   * A rota existia e a tela já chamava `inboxes/resetSecret`; não havia nem esta
   * chamada nem a action no store, então o botão de reset só produzia
   * `[vuex] unknown action type` no console.
   */
  resetSecret(inboxId) {
    return axios.post(`${this.url}/${inboxId}/reset_secret`);
  }

  createCSATTemplate(inboxId, template) {
    return axios.post(`${this.url}/${inboxId}/csat_template`, {
      template,
    });
  }

  getCSATTemplateStatus(inboxId) {
    return axios.get(`${this.url}/${inboxId}/csat_template`);
  }

  analyzeCSATTemplateUtility(inboxId, template) {
    return axios.post(`${this.url}/${inboxId}/csat_template/analyze`, {
      template,
    });
  }

  getMessageTemplates(inboxId) {
    return axios.get(`${this.url}/${inboxId}/message_templates`);
  }

  createMessageTemplate(inboxId, template) {
    return axios.post(`${this.url}/${inboxId}/message_templates`, {
      template,
    });
  }

  deleteMessageTemplate(inboxId, templateName) {
    return axios.delete(
      `${this.url}/${inboxId}/message_templates/${encodeURIComponent(
        templateName
      )}`
    );
  }
}

export default new Inboxes();
