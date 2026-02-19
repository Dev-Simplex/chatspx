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
    return axios.patch(`${this.url}/${funnelId}/funnel_stages/${stageId}`, {
      funnel_stage: data,
    });
  }

  deleteStage(funnelId, stageId) {
    return axios.delete(`${this.url}/${funnelId}/funnel_stages/${stageId}`);
  }

  getFunnelItems(funnelId, options = {}) {
    let url = `${this.url}/${funnelId}/funnel_items`;
    const params = new URLSearchParams();
    const {
      stageId = null,
      excludeAutomationType = null,
      mode = null,
      limit = null,
      cursor = null,
      page = null,
      perPage = null,
    } = options;

    if (stageId != null) {
      params.set('stage_id', String(stageId));
    }
    if (excludeAutomationType) {
      params.set('exclude_automation_type', excludeAutomationType);
    }
    if (mode) {
      params.set('mode', mode);
    }
    if (limit != null) {
      params.set('limit', String(limit));
    }
    if (cursor) {
      params.set('cursor', cursor);
    }
    if (page != null) {
      params.set('page', String(page));
    }
    if (perPage != null) {
      params.set('per_page', String(perPage));
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
    return axios.patch(`${this.url}/${funnelId}/funnel_items/${itemId}`, {
      funnel_item: data,
    });
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
    const {
      conversationId = null,
      status = 'all',
      mode = null,
      from = null,
      to = null,
      limit = null,
      cursor = null,
    } = typeof options === 'object' && options !== null
      ? options
      : { conversationId: options, status: 'all' };

    const params = new URLSearchParams();
    if (conversationId) {
      params.set('conversation_id', String(conversationId));
    }
    if (status) {
      params.set('status', status);
    }
    if (mode) {
      params.set('mode', mode);
    }
    if (from) {
      params.set('from', from);
    }
    if (to) {
      params.set('to', to);
    }
    if (limit != null) {
      params.set('limit', String(limit));
    }
    if (cursor) {
      params.set('cursor', cursor);
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
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/scheduled_messages/inboxes`;
    return axios.get(url);
  }

  getInboxes() {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/inboxes`;
    return axios.get(url);
  }
}

export default new KanbanAPI();
