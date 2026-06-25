/* global axios */
import ApiClient from './ApiClient';

class KanbanAPI extends ApiClient {
  constructor() {
    super('funnels', { accountScoped: true });
  }

  getFunnels() {
    return axios.get(this.url);
  }

  // Funnel placements (funnel + stage) of a single conversation, for the
  // conversation sidebar. Lives under /conversations, not /funnels.
  getConversationFunnelItems(conversationId) {
    return axios.get(
      `${this.baseUrl()}/conversations/${conversationId}/funnel_items`
    );
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

  // ── Custom field DEFINITIONS (Kanban v2 / Fase 2) ──────────────────
  getCustomFields(funnelId) {
    return axios.get(`${this.url}/${funnelId}/custom_fields`);
  }

  createCustomField(funnelId, data) {
    return axios.post(`${this.url}/${funnelId}/custom_fields`, {
      custom_field: data,
    });
  }

  updateCustomField(funnelId, fieldId, data) {
    return axios.patch(`${this.url}/${funnelId}/custom_fields/${fieldId}`, {
      custom_field: data,
    });
  }

  deleteCustomField(funnelId, fieldId) {
    return axios.delete(`${this.url}/${funnelId}/custom_fields/${fieldId}`);
  }

  // Custom field VALUES live in conversations.custom_attributes (namespaced
  // funnel_<id>_<key>). The backend merges only this funnel's keys, so other
  // attributes are never clobbered. `itemId` is the funnel_item id.
  updateItemCustomAttributes(funnelId, itemId, customAttributes) {
    return axios.patch(
      `${this.url}/${funnelId}/funnel_items/${itemId}/custom_attributes`,
      { custom_attributes: customAttributes }
    );
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

  // ── Saved views (Fase 3) — account-scoped, filtered by funnel ───────
  getFunnelViews(funnelId) {
    const url = `${this.baseUrl()}/funnel_views`;
    return axios.get(funnelId ? `${url}?funnel_id=${funnelId}` : url);
  }

  createFunnelView(data) {
    return axios.post(`${this.baseUrl()}/funnel_views`, { funnel_view: data });
  }

  updateFunnelView(viewId, data) {
    return axios.patch(`${this.baseUrl()}/funnel_views/${viewId}`, {
      funnel_view: data,
    });
  }

  deleteFunnelView(viewId) {
    return axios.delete(`${this.baseUrl()}/funnel_views/${viewId}`);
  }

  // ── Dashboard stats (Fase 6) ───────────────────────────────────────
  getFunnelStats(funnelId) {
    return axios.get(`${this.url}/${funnelId}/stats`);
  }

  // ── AI availability (Fase 7) — gates the card's AI actions ──────────
  getAiStatus() {
    return axios.get(`${this.baseUrl()}/kanban_ai/status`);
  }

  // ── Automations (Fase 5) ───────────────────────────────────────────
  getAutomations(funnelId) {
    return axios.get(`${this.url}/${funnelId}/automations`);
  }

  createAutomation(funnelId, data) {
    return axios.post(`${this.url}/${funnelId}/automations`, {
      funnel_automation: data,
    });
  }

  updateAutomation(funnelId, automationId, data) {
    return axios.patch(`${this.url}/${funnelId}/automations/${automationId}`, {
      funnel_automation: data,
    });
  }

  deleteAutomation(funnelId, automationId) {
    return axios.delete(`${this.url}/${funnelId}/automations/${automationId}`);
  }

  // ── Internal card notes (Fase 4) ───────────────────────────────────
  getItemNotes(funnelId, itemId) {
    return axios.get(`${this.url}/${funnelId}/funnel_items/${itemId}/notes`);
  }

  createItemNote(funnelId, itemId, content) {
    return axios.post(`${this.url}/${funnelId}/funnel_items/${itemId}/notes`, {
      content,
    });
  }

  deleteItemNote(funnelId, itemId, noteId) {
    return axios.delete(
      `${this.url}/${funnelId}/funnel_items/${itemId}/notes/${noteId}`
    );
  }

  // ── Bulk actions (Fase 3): reassign / tag / archive selected cards ──
  bulkUpdateItems(funnelId, payload) {
    return axios.post(
      `${this.url}/${funnelId}/funnel_items/bulk_update`,
      payload
    );
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
