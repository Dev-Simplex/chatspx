/* global axios */
import ApiClient from './ApiClient';

class KanbanAPI extends ApiClient {
  constructor() {
    super('funnels', { accountScoped: true });
  }

  // Funnels
  getFunnels() {
    return axios.get(this.url);
  }

  getFunnel(funnelId) {
    return axios.get(`${this.url}/${funnelId}`);
  }

  createFunnel(data) {
    return axios.post(this.url, { funnel: data });
  }

  updateFunnel(funnelId, data) {
    return axios.patch(`${this.url}/${funnelId}`, { funnel: data });
  }

  deleteFunnel(funnelId) {
    return axios.delete(`${this.url}/${funnelId}`);
  }

  reorderStages(funnelId, stageIds) {
    return axios.post(`${this.url}/${funnelId}/reorder_stages`, {
      stage_ids: stageIds,
    });
  }

  // Funnel Stages
  getFunnelStages(funnelId) {
    return axios.get(`${this.url}/${funnelId}/funnel_stages`);
  }

  getFunnelStage(funnelId, stageId) {
    return axios.get(`${this.url}/${funnelId}/funnel_stages/${stageId}`);
  }

  createStage(funnelId, data) {
    return axios.post(`${this.url}/${funnelId}/funnel_stages`, {
      funnel_stage: data,
    });
  }

  updateStage(funnelId, stageId, data) {
    return axios.patch(
      `${this.url}/${funnelId}/funnel_stages/${stageId}`,
      { funnel_stage: data }
    );
  }

  deleteStage(funnelId, stageId) {
    return axios.delete(
      `${this.url}/${funnelId}/funnel_stages/${stageId}`
    );
  }

  // Funnel Items
  getFunnelItems(funnelId, stageId = null) {
    let url = `${this.url}/${funnelId}/funnel_items`;
    if (stageId) {
      url += `?stage_id=${stageId}`;
    }
    return axios.get(url);
  }

  createItem(funnelId, data) {
    return axios.post(`${this.url}/${funnelId}/funnel_items`, {
      funnel_item: data,
    });
  }

  updateItem(funnelId, itemId, data) {
    return axios.patch(
      `${this.url}/${funnelId}/funnel_items/${itemId}`,
      { funnel_item: data }
    );
  }

  deleteItem(funnelId, itemId) {
    return axios.delete(
      `${this.url}/${funnelId}/funnel_items/${itemId}`
    );
  }

  bulkMoveItems(funnelId, conversationIds, stageId) {
    return axios.post(`${this.url}/${funnelId}/funnel_items/bulk_move`, {
      conversation_ids: conversationIds,
      stage_id: stageId,
    });
  }

  // Scheduled Messages
  getScheduledMessages(conversationId = null) {
    const accountId = this.accountIdFromRoute;
    let url = `${this.apiVersion}/accounts/${accountId}/scheduled_messages`;
    if (conversationId) {
      url += `?conversation_id=${conversationId}`;
    }
    return axios.get(url);
  }

  createScheduledMessage(data) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/scheduled_messages`;
    // Se os dados já estão no formato correto (com scheduled_message), usar diretamente
    // Caso contrário, garantir que está no formato esperado
    const payload = data.scheduled_message ? data : { scheduled_message: data };
    return axios.post(url, payload);
  }

  updateScheduledMessage(messageId, data) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/scheduled_messages/${messageId}`;
    return axios.patch(url, { scheduled_message: data });
  }

  deleteScheduledMessage(messageId) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/scheduled_messages/${messageId}`;
    return axios.delete(url);
  }

  getWahaInboxes() {
    // Mantido para compatibilidade, mas agora retorna todos os inboxes
    return this.getScheduledMessageInboxes();
  }

  getScheduledMessageInboxes() {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/scheduled_messages/inboxes`;
    return axios.get(url);
  }
}

export default new KanbanAPI();

