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
      // P2-08: filtros server-side.
      labelIds = null,
      assigneeId = null,
      inboxId = null,
      status = null,
      query: textQuery = null,
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
    if (Array.isArray(labelIds) && labelIds.length) {
      params.set('label_ids', labelIds.join(','));
    }
    if (assigneeId != null) {
      params.set('assignee_id', String(assigneeId));
    }
    if (inboxId != null) {
      params.set('inbox_id', String(inboxId));
    }
    if (status && status !== 'all') {
      params.set('status', status);
    }
    if (textQuery && String(textQuery).trim().length) {
      params.set('query', String(textQuery).trim());
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

  bulkMoveItems(funnelId, conversationIds, stageId, itemIds = []) {
    return axios.post(`${this.url}/${funnelId}/funnel_items/bulk_move`, {
      conversation_ids: conversationIds,
      item_ids: itemIds,
      stage_id: stageId,
    });
  }

  // P2-07: bulk delete por item_ids.
  bulkDeleteItems(funnelId, itemIds) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/kanbans/${funnelId}/kanban_items/bulk_delete`;
    return axios.post(url, { item_ids: itemIds });
  }

  // P2-05: métricas do board (cache 60s no backend).
  getMetrics(funnelId) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/kanbans/${funnelId}/metrics`;
    return axios.get(url);
  }

  // P2-04: views salvas (filtros + sort + settings) por usuário.
  getSavedViews(funnelId) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/kanbans/${funnelId}/kanban_views`;
    return axios.get(url);
  }

  createSavedView(funnelId, data) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/kanbans/${funnelId}/kanban_views`;
    return axios.post(url, { kanban_view: data });
  }

  updateSavedView(funnelId, viewId, data) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/kanbans/${funnelId}/kanban_views/${viewId}`;
    return axios.patch(url, { kanban_view: data });
  }

  deleteSavedView(funnelId, viewId) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/kanbans/${funnelId}/kanban_views/${viewId}`;
    return axios.delete(url);
  }

  // P2-01: templates pré-prontos pt-BR.
  getTemplates() {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/kanban_templates`;
    return axios.get(url);
  }

  applyTemplate(templateId, options = {}) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/kanban_templates/${templateId}/apply`;
    return axios.post(url, options);
  }

  // P2-06: won/lost
  markItemWon(funnelId, itemId, data) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/kanbans/${funnelId}/kanban_items/${itemId}/mark_won`;
    return axios.post(url, data);
  }

  markItemLost(funnelId, itemId, data) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/kanbans/${funnelId}/kanban_items/${itemId}/mark_lost`;
    return axios.post(url, data);
  }

  // P3-01: envia mensagem rápida do card.
  quickReply(funnelId, itemId, { content, isPrivate = false } = {}) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/kanbans/${funnelId}/kanban_items/${itemId}/quick_reply`;
    return axios.post(url, { content, private: isPrivate });
  }

  // P3-02: aceita / rejeita sugestão Captain AI Triage.
  acceptSuggestion(funnelId, itemId) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/kanbans/${funnelId}/kanban_items/${itemId}/accept_suggestion`;
    return axios.post(url, {});
  }

  rejectSuggestion(funnelId, itemId) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/kanbans/${funnelId}/kanban_items/${itemId}/reject_suggestion`;
    return axios.post(url, {});
  }

  // P3-03: envia o template configurado da stage destino.
  sendTemplate(funnelId, itemId, { templateId, variables = {} } = {}) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/kanbans/${funnelId}/kanban_items/${itemId}/send_template`;
    return axios.post(url, { template_id: templateId, variables });
  }

  // P3-05: automations.
  listAutomations(funnelId) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/kanbans/${funnelId}/kanban_automations`;
    return axios.get(url);
  }

  createAutomation(funnelId, data) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/kanbans/${funnelId}/kanban_automations`;
    return axios.post(url, { kanban_automation: data });
  }

  updateAutomation(funnelId, automationId, data) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/kanbans/${funnelId}/kanban_automations/${automationId}`;
    return axios.patch(url, { kanban_automation: data });
  }

  deleteAutomation(funnelId, automationId) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/kanbans/${funnelId}/kanban_automations/${automationId}`;
    return axios.delete(url);
  }

  getAutomationRecipes(funnelId) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/kanbans/${funnelId}/kanban_automations/recipes`;
    return axios.get(url);
  }

  sendSummaryNow(funnelId) {
    const accountId = this.accountIdFromRoute;
    const url = `${this.apiVersion}/accounts/${accountId}/kanbans/${funnelId}/kanban_automations/send_summary_now`;
    return axios.post(url, {});
  }

  // P1-05: cria item a partir de uma query livre (nome/telefone).
  quickCreateItem(funnelId, stageId, contactQuery) {
    return axios.post(`${this.url}/${funnelId}/funnel_items/quick_create`, {
      funnel_stage_id: stageId,
      kanban_stage_id: stageId,
      contact_query: contactQuery,
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
