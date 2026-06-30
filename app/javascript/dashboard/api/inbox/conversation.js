/* global axios */
import ApiClient from '../ApiClient';

/* eslint-disable no-underscore-dangle */
class ConversationApi extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
    this._getAbortController = null;
    this._filterAbortController = null;
  }

  get({
    inboxId,
    status,
    assigneeType,
    page,
    cursor,
    labels,
    teamId,
    conversationType,
    sortBy,
    updatedWithin,
    limit,
    dateFrom,
    dateTo,
  }) {
    if (this._getAbortController) {
      this._getAbortController.abort();
    }
    this._getAbortController = new AbortController();

    const params = {
      inbox_id: inboxId,
      team_id: teamId,
      status,
      assignee_type: assigneeType,
      labels: labels || undefined,
      conversation_type: conversationType,
      sort_by: sortBy,
      updated_within: updatedWithin,
      date_from: dateFrom,
      date_to: dateTo,
    };
    if (cursor) {
      params.cursor = cursor;
    } else if (page) {
      params.page = page;
    }
    if (limit) {
      params.limit = limit;
    }
    return axios.get(this.url, {
      params,
      signal: this._getAbortController.signal,
    });
  }

  filter(payload) {
    if (this._filterAbortController) {
      this._filterAbortController.abort();
    }
    this._filterAbortController = new AbortController();

    return axios.post(`${this.url}/filter`, payload.queryData, {
      params: {
        page: payload.page,
      },
      signal: this._filterAbortController.signal,
    });
  }

  search({ q }) {
    return axios.get(`${this.url}/search`, {
      params: {
        q,
        page: 1,
      },
    });
  }

  toggleStatus({ conversationId, status, snoozedUntil = null }) {
    return axios.post(`${this.url}/${conversationId}/toggle_status`, {
      status,
      snoozed_until: snoozedUntil,
    });
  }

  togglePriority({ conversationId, priority }) {
    return axios.post(`${this.url}/${conversationId}/toggle_priority`, {
      priority,
    });
  }

  assignAgent({ conversationId, agentId }) {
    return axios.post(`${this.url}/${conversationId}/assignments`, {
      assignee_id: agentId,
    });
  }

  assignAIAgent({ conversationId, agentBotId }) {
    return axios.post(`${this.url}/${conversationId}/assignments`, {
      // id do ESPELHO (assistant.agent_bot_id) — nunca o id do assistant (DC-2)
      assignee_id: agentBotId,
      assignee_type: 'AgentBot',
    });
  }

  assignTeam({ conversationId, teamId }) {
    const params = { team_id: teamId };
    return axios.post(`${this.url}/${conversationId}/assignments`, params);
  }

  // "Devolver para a IA": re-tria a conversa (Clara, time limpo). O backend
  // resolve qual é o assistente de triagem da conta/inbox.
  retriage({ conversationId }) {
    return axios.post(`${this.url}/${conversationId}/retriage`);
  }

  markMessageRead({ id }) {
    return axios.post(`${this.url}/${id}/update_last_seen`);
  }

  markMessagesUnread({ id }) {
    return axios.post(`${this.url}/${id}/unread`);
  }

  toggleTyping({ conversationId, status, isPrivate }) {
    return axios.post(`${this.url}/${conversationId}/toggle_typing_status`, {
      typing_status: status,
      is_private: isPrivate,
    });
  }

  mute(conversationId) {
    return axios.post(`${this.url}/${conversationId}/mute`);
  }

  unmute(conversationId) {
    return axios.post(`${this.url}/${conversationId}/unmute`);
  }

  meta({ inboxId, status, assigneeType, labels, teamId, conversationType }) {
    return axios.get(`${this.url}/meta`, {
      params: {
        inbox_id: inboxId,
        status,
        assignee_type: assigneeType,
        labels,
        team_id: teamId,
        conversation_type: conversationType,
      },
    });
  }

  sendEmailTranscript({ conversationId, email }) {
    return axios.post(`${this.url}/${conversationId}/transcript`, { email });
  }

  updateCustomAttributes({ conversationId, customAttributes }) {
    return axios.post(`${this.url}/${conversationId}/custom_attributes`, {
      custom_attributes: customAttributes,
    });
  }

  fetchParticipants(conversationId) {
    return axios.get(`${this.url}/${conversationId}/participants`);
  }

  updateParticipants({ conversationId, userIds }) {
    return axios.patch(`${this.url}/${conversationId}/participants`, {
      user_ids: userIds,
    });
  }

  getAllAttachments(conversationId, page = 1) {
    return axios.get(`${this.url}/${conversationId}/attachments`, {
      params: { page },
    });
  }

  getInboxAssistant(conversationId) {
    return axios.get(`${this.url}/${conversationId}/inbox_assistant`);
  }

  delete(conversationId) {
    return axios.delete(`${this.url}/${conversationId}`);
  }

  forwardMessage({ messageId, conversationIds, contactIds }) {
    const accountUrl = this.url.replace('/conversations', '');
    return axios.post(`${accountUrl}/messages/${messageId}/forward`, {
      forward: {
        conversation_ids: conversationIds || [],
        contact_ids: contactIds || [],
      },
    });
  }

  getAllConversationsForForward({ status = 'all', page = 1, perPage = 100 }) {
    return axios.get(this.url, {
      params: {
        status,
        page,
        per_page: perPage,
        sort_by: 'last_activity_at_desc',
      },
    });
  }

  searchContactsForForward({ query }) {
    const accountId = this.url.match(/accounts\/(\d+)/)?.[1];
    return axios.get(`/api/v1/accounts/${accountId}/contacts/search`, {
      params: { q: query, page: 1, per_page: 15 },
    });
  }
}

export default new ConversationApi();
