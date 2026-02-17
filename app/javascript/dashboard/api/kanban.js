/* global axios */
import ApiClient from './ApiClient';

class KanbanAPI extends ApiClient {
  constructor() {
    super('funnels', { accountScoped: true });
  }

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
    const normalizedIds = Array.isArray(stageIds)
      ? stageIds.map(id => Number(id)).filter(id => !Number.isNaN(id))
      : [];
    return axios.post(`${this.url}/${funnelId}/reorder_stages`, {
      stage_ids: normalizedIds,
    });
  }

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
    return axios.delete(`${this.url}/${funnelId}/funnel_stages/${stageId}`);
  }

  getFunnelItems(funnelId, stageId = null, options = {}) {
    let url = `${this.url}/${funnelId}/funnel_items`;
    const params = new URLSearchParams();
    if (stageId) {
      params.set('stage_id', stageId);
    }
    if (options.excludeAutomationType) {
      params.set('exclude_automation_type', options.excludeAutomationType);
    }
    if (options.page != null) {
      params.set('page', String(options.page));
    }
    if (options.perPage != null) {
      params.set('per_page', String(options.perPage));
    }
    const query = params.toString();
    if (query) {
      url += `?${query}`;
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
    return axios.delete(`${this.url}/${funnelId}/funnel_items/${itemId}`);
  }

  bulkMoveItems(funnelId, conversationIds, stageId) {
    return axios.post(`${this.url}/${funnelId}/funnel_items/bulk_move`, {
      conversation_ids: conversationIds,
      stage_id: stageId,
    });
  }

  getScheduledMessages(options = {}) {
    const accountId = this.accountIdFromRoute;
    const { conversationId = null, status = 'pending' } =
      typeof options === 'object' && options !== null
        ? options
        : { conversationId: options, status: 'pending' };

    const params = new URLSearchParams();
    if (conversationId) {
      params.set('conversation_id', conversationId);
    }
    if (status) {
      params.set('status', status);
    }

    const query = params.toString();
    let url = `${this.apiVersion}/accounts/${accountId}/scheduled_messages`;
    if (query) {
      url += `?${query}`;
    }
    return axios.get(url);
  }

  createScheduledMessage(data) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/scheduled_messages`;
    if (data instanceof FormData) {
      return axios.post(url, data);
    }
    return axios.post(url, data);
  }

  updateScheduledMessage(messageId, data) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/scheduled_messages/${messageId}`;
    if (data instanceof FormData) {
      return axios.patch(url, data);
    }
    return axios.patch(url, { scheduled_message: data });
  }

  deleteScheduledMessage(messageId) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/scheduled_messages/${messageId}`;
    return axios.delete(url);
  }

  getWahaInboxes() {
    return this.getInboxes();
  }

  getInboxes() {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/inboxes`;
    return axios.get(url);
  }
}

export default new KanbanAPI();
