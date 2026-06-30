import types from '../../mutation-types';
import ConversationApi from '../../../api/inbox/conversation';
import MessageApi from '../../../api/inbox/message';
import { MESSAGE_STATUS, MESSAGE_TYPE } from 'shared/constants/messages';
import { createPendingMessage } from 'dashboard/helper/commons';
import {
  buildConversationList,
  isOnMentionsView,
  isOnUnattendedView,
  isOnFoldersView,
} from './helpers/actionHelpers';
import messageReadActions from './actions/messageReadActions';
import messageTranslateActions from './actions/messageTranslateActions';
import * as Sentry from '@sentry/vue';
import {
  handleVoiceCallCreated,
  handleVoiceCallUpdated,
} from 'dashboard/helper/voice';

export const hasMessageFailedWithExternalError = pendingMessage => {
  // This helper is used to check if the message has failed with an external error.
  // We have two cases
  // 1. Messages that fail from the UI itself (due to large attachments or a failed network):
  //    In this case, the message will have a status of failed but no external error. So we need to create that message again
  // 2. Messages sent from Chatwoot but failed to deliver to the customer for some reason (user blocking or client system down):
  //    In this case, the message will have a status of failed and an external error. So we need to retry that message
  const { content_attributes: contentAttributes, status } = pendingMessage;
  const externalError = contentAttributes?.external_error ?? '';
  return status === MESSAGE_STATUS.FAILED && externalError !== '';
};

// Tracks reconnect-driven resend attempts per optimistic message (keyed by
// echo_id) so a persistently-unsendable message gives up after a few tries
// instead of re-POSTing on every reconnect.
const reconcileAttempts = new Map();
const MAX_RECONCILE_RETRIES = 3;

// A still-optimistic message keeps id === echo_id; the server swaps id for a
// numeric one the moment it reconciles. So this equality is the reliable
// "never confirmed by the server" signal.
const isUnreconciledOptimistic = message =>
  !!message.echo_id && String(message.id) === String(message.echo_id);

// An optimistic attachment message whose DirectUpload is still in flight: the
// real POST hasn't happened yet, so a reconnect must NOT resend it (no blob) nor
// mark it failed — leave it until the upload finishes (or fails on its own).
const isUploadingOptimistic = message =>
  Array.isArray(message.attachments) &&
  message.attachments.some(a => a.upload_status === 'uploading');

// Find an optimistic (still id===echo_id) message by its echo_id in a chat.
const findOptimisticByEchoId = (chat, echoId) =>
  chat?.messages?.find(
    m => isUnreconciledOptimistic(m) && m.echo_id === echoId
  );

// actions
const actions = {
  getConversation: async ({ commit }, conversationId) => {
    const response = await ConversationApi.show(conversationId);
    commit(types.UPDATE_CONVERSATION, response.data);
    commit(`contacts/${types.SET_CONTACT_ITEM}`, response.data.meta.sender);
  },

  fetchAllConversations: async ({ commit, state, dispatch }) => {
    commit(types.SET_LIST_LOADING_STATUS);
    const params = state.conversationFilters;
    try {
      const {
        data: { data },
      } = await ConversationApi.get(params);
      buildConversationList(
        { commit, dispatch },
        params,
        data,
        params.assigneeType
      );
    } catch (error) {
      // Aborted/canceled = a newer fetch replaced this one — ignore silently
      const isAbort =
        error?.name === 'AbortError' || error?.code === 'ERR_CANCELED';
      if (isAbort) return;
      commit(types.CLEAR_LIST_LOADING_STATUS);
    }
  },

  fetchFilteredConversations: async ({ commit, dispatch }, params) => {
    commit(types.SET_LIST_LOADING_STATUS);
    try {
      const { data } = await ConversationApi.filter(params);
      buildConversationList(
        { commit, dispatch },
        params,
        data,
        'appliedFilters'
      );
    } catch (error) {
      const isAbort =
        error?.name === 'AbortError' || error?.code === 'ERR_CANCELED';
      if (isAbort) return;
      commit(types.CLEAR_LIST_LOADING_STATUS);
    }
  },

  emptyAllConversations({ commit }) {
    commit(types.EMPTY_ALL_CONVERSATION);
  },

  clearSelectedState({ commit }) {
    commit(types.CLEAR_CURRENT_CHAT_WINDOW);
  },

  fetchPreviousMessages: async ({ commit }, data) => {
    const shouldIncludeMeta = data?.includeMeta ?? true;

    try {
      const {
        data: { meta = {}, payload = [] },
      } = await MessageApi.getPreviousMessages({
        ...data,
        includeMeta: shouldIncludeMeta,
      });

      const hasMore = meta.has_more;
      const hasMoreAvailable = typeof hasMore === 'boolean';

      if (shouldIncludeMeta && Object.keys(meta).length) {
        commit(`conversationMetadata/${types.SET_CONVERSATION_METADATA}`, {
          id: data.conversationId,
          data: meta,
        });
      }

      commit(types.SET_PREVIOUS_CONVERSATIONS, {
        id: data.conversationId,
        data: payload,
      });

      if (hasMoreAvailable ? !hasMore : !payload.length) {
        commit(types.SET_ALL_MESSAGES_LOADED, data.conversationId);
      }
    } catch (error) {
      // Handle error
    }
  },

  fetchNextMessages: async ({ commit }, data) => {
    try {
      const {
        data: { meta = {}, payload = [] },
      } = await MessageApi.getPreviousMessages({
        conversationId: data.conversationId,
        after: data.after,
        includeMeta: true,
      });

      commit(types.SET_NEXT_CONVERSATIONS, {
        id: data.conversationId,
        data: payload,
      });

      const hasMore = meta.has_more;
      if (typeof hasMore === 'boolean' ? !hasMore : !payload.length) {
        commit(types.SET_ALL_NEWER_MESSAGES_LOADED, data.conversationId);
      }
    } catch (error) {
      // Handle error
    }
  },

  jumpToLatest: async ({ commit }, conversationId) => {
    commit(types.CLEAR_NEWER_MESSAGES_FLAG, conversationId);
    commit(types.CLEAR_ALL_MESSAGES_LOADED, conversationId);
    try {
      const {
        data: { meta = {}, payload = [] },
      } = await MessageApi.getPreviousMessages({
        conversationId,
        includeMeta: true,
      });

      if (Object.keys(meta).length) {
        commit(`conversationMetadata/${types.SET_CONVERSATION_METADATA}`, {
          id: conversationId,
          data: meta,
        });
      }

      commit(types.SET_MISSING_MESSAGES, {
        id: conversationId,
        data: payload,
      });

      if (!meta.has_more) {
        commit(types.SET_ALL_MESSAGES_LOADED, conversationId);
      }
    } catch (error) {
      // Handle error
    }
  },

  fetchAllAttachments: async ({ commit, state }, conversationId) => {
    if (state.attachments[conversationId] !== undefined) {
      return;
    }
    commit(types.SET_ALL_ATTACHMENTS, {
      id: conversationId,
      data: [],
      meta: null,
    });
    let attachments = [];
    let meta = {};

    try {
      const { data } = await ConversationApi.getAllAttachments(
        conversationId,
        1
      );
      attachments = data.payload;
      meta = data.meta || {};
    } catch (error) {
      Sentry.setContext('Conversation', {
        id: conversationId,
      });
      Sentry.captureException(error);
    } finally {
      commit(types.SET_ALL_ATTACHMENTS, {
        id: conversationId,
        data: attachments,
        meta,
      });
    }
  },

  fetchMoreAttachments: async ({ commit, state }, conversationId) => {
    const currentMeta = state.attachmentsMeta[conversationId];
    if (!currentMeta || currentMeta.currentPage >= currentMeta.totalPages)
      return;

    const nextPage = currentMeta.currentPage + 1;

    try {
      const { data } = await ConversationApi.getAllAttachments(
        conversationId,
        nextPage
      );
      commit(types.APPEND_ATTACHMENTS, {
        id: conversationId,
        data: data.payload,
        meta: data.meta || {},
      });
    } catch (error) {
      Sentry.setContext('Conversation', {
        id: conversationId,
      });
      Sentry.captureException(error);
    }
  },

  syncActiveConversationMessages: async (
    { commit, state, dispatch },
    { conversationId }
  ) => {
    const { allConversations, syncConversationsMessages } = state;
    const lastMessageId = syncConversationsMessages[conversationId];
    const selectedChat = allConversations.find(
      conversation => conversation.id === conversationId
    );
    if (!selectedChat) return;
    try {
      const { messages } = selectedChat;
      // Fetch all the messages after the last message id
      const {
        data: { meta, payload },
      } = await MessageApi.getPreviousMessages({
        conversationId,
        after: lastMessageId,
      });
      commit(`conversationMetadata/${types.SET_CONVERSATION_METADATA}`, {
        id: conversationId,
        data: meta,
      });
      // Find the messages that are not already present in the store
      const existingIds = new Set(messages.map(m => m.id));
      const missingMessages = payload.filter(m => !existingIds.has(m.id));
      selectedChat.messages.push(...missingMessages);
      // Sort the messages by created_at, desempatando por id (created_at vem em segundos,
      // rajadas colidem no mesmo segundo — id desempata pela ordem real de criacao)
      const sortedMessages = selectedChat.messages.sort((a, b) => {
        return new Date(a.created_at) - new Date(b.created_at) || a.id - b.id;
      });
      commit(types.SET_MISSING_MESSAGES, {
        id: conversationId,
        data: sortedMessages,
      });
      commit(types.SET_LAST_MESSAGE_ID_IN_SYNC_CONVERSATION, {
        conversationId,
        messageId: null,
      });
      dispatch('markMessagesRead', { id: conversationId }, { root: true });
    } catch (error) {
      // Handle error
    }
  },

  setConversationLastMessageId: async (
    { commit, state },
    { conversationId }
  ) => {
    const { allConversations } = state;
    const selectedChat = allConversations.find(
      conversation => conversation.id === conversationId
    );
    if (!selectedChat) return;
    const { messages } = selectedChat;
    const lastMessage = messages.last();
    if (!lastMessage) return;
    commit(types.SET_LAST_MESSAGE_ID_IN_SYNC_CONVERSATION, {
      conversationId,
      messageId: lastMessage.id,
    });
  },

  async setActiveChat({ commit, dispatch }, { data, after }) {
    commit(types.SET_CURRENT_CHAT_WINDOW, data);
    commit(types.CLEAR_ALL_MESSAGES_LOADED, data.id);
    // Reset hasNewerMessages so WS pushes resume after re-entering a long thread
    // that previously triggered the sliding-window trim. Without this, the flag
    // stays true and ADD_MESSAGE silently drops every realtime message.
    commit(types.CLEAR_NEWER_MESSAGES_FLAG, data.id);
    if (data.dataFetched === undefined) {
      try {
        await dispatch('fetchPreviousMessages', {
          after,
          before: data.messages[0].id,
          conversationId: data.id,
          includeMeta: true,
        });
        commit(types.SET_CHAT_DATA_FETCHED, data.id);
      } catch (error) {
        // Ignore error
      }
    }
  },

  assignAgent: async (
    { dispatch },
    { conversationId, agentId, rethrow = false }
  ) => {
    try {
      const response = await ConversationApi.assignAgent({
        conversationId,
        agentId,
      });
      dispatch('setCurrentChatAssignee', {
        conversationId,
        assignee: response.data,
      });
    } catch (error) {
      if (rethrow) {
        throw error;
      }
    }
  },

  assignAIAgent: async (
    { dispatch },
    { conversationId, agentBotId, rethrow = false }
  ) => {
    try {
      const response = await ConversationApi.assignAIAgent({
        conversationId,
        agentBotId,
      });
      // response.data = _agent_bot_slim (id, name, thumbnail, bot_type, type)
      // → vira meta.assignee via mutation ASSIGN_AGENT existente
      dispatch('setCurrentChatAssignee', {
        conversationId,
        assignee: response.data,
      });
    } catch (error) {
      if (rethrow) {
        throw error;
      }
    }
  },

  setCurrentChatAssignee({ commit }, { conversationId, assignee }) {
    commit(types.ASSIGN_AGENT, { conversationId, assignee });
  },

  assignTeam: async (
    { dispatch },
    { conversationId, teamId, rethrow = false }
  ) => {
    try {
      const response = await ConversationApi.assignTeam({
        conversationId,
        teamId,
      });
      dispatch('setCurrentChatTeam', { team: response.data, conversationId });
    } catch (error) {
      if (rethrow) {
        throw error;
      }
    }
  },

  setCurrentChatTeam({ commit }, { team, conversationId }) {
    commit(types.ASSIGN_TEAM, { team, conversationId });
  },

  // "Devolver para a IA": re-tria a conversa (Clara) no backend e re-busca a
  // conversa pra refletir o novo assignee (IA) + time limpo na hora.
  retriage: async ({ dispatch }, { conversationId, rethrow = false }) => {
    try {
      await ConversationApi.retriage({ conversationId });
      dispatch('getConversation', conversationId);
    } catch (error) {
      if (rethrow) {
        throw error;
      }
    }
  },

  toggleStatus: async (
    { commit },
    {
      conversationId,
      status,
      snoozedUntil = null,
      customAttributes = null,
      rethrow = false,
    }
  ) => {
    try {
      // Update custom attributes first if provided
      if (customAttributes) {
        await ConversationApi.updateCustomAttributes({
          conversationId,
          customAttributes,
        });
        commit(types.UPDATE_CONVERSATION_CUSTOM_ATTRIBUTES, {
          conversationId,
          customAttributes,
        });
      }

      const {
        data: {
          payload: {
            current_status: updatedStatus,
            snoozed_until: updatedSnoozedUntil,
          } = {},
        } = {},
      } = await ConversationApi.toggleStatus({
        conversationId,
        status,
        snoozedUntil,
      });
      commit(types.CHANGE_CONVERSATION_STATUS, {
        conversationId,
        status: updatedStatus,
        snoozedUntil: updatedSnoozedUntil,
      });
    } catch (error) {
      // Opt-in propagation so callers (e.g. the resolve assignment gate) can react
      // to a 422; default stays silent to preserve existing behaviour.
      if (rethrow) {
        throw error;
      }
    }
  },

  createPendingMessageAndSend: async ({ dispatch }, data) => {
    const pendingMessage = createPendingMessage(data);
    // D6: propagar a rejeição (era fire-and-forget → o 422 do gate nunca
    // chegava ao catch do ReplyBox e virava unhandled rejection). Com o
    // `return`, qualquer falha de envio chega ao ReplyBox e pode reabrir o
    // dialog de assunção (assignment_required).
    return dispatch('sendMessageWithData', pendingMessage);
  },

  sendMessageWithData: async ({ commit }, pendingMessage) => {
    const { conversation_id: conversationId, id } = pendingMessage;
    try {
      commit(types.ADD_MESSAGE, {
        ...pendingMessage,
        status: MESSAGE_STATUS.PROGRESS,
      });
      const response = hasMessageFailedWithExternalError(pendingMessage)
        ? await MessageApi.retry(conversationId, id)
        : await MessageApi.create(pendingMessage);
      commit(types.ADD_MESSAGE, {
        ...response.data,
        status: MESSAGE_STATUS.SENT,
      });
      commit(types.ADD_CONVERSATION_ATTACHMENTS, {
        ...response.data,
        status: MESSAGE_STATUS.SENT,
      });
    } catch (error) {
      const errorMessage = error.response
        ? error.response.data.error
        : undefined;
      // D6: gate `assignment_required` não vira bolha FAILED — remove o
      // pendente PROGRESS e deixa o ReplyBox reabrir o dialog de assunção.
      if (error.response?.data?.error_code === 'assignment_required') {
        commit(types.REMOVE_PENDING_MESSAGE, pendingMessage);
      } else {
        commit(types.ADD_MESSAGE, {
          ...pendingMessage,
          meta: {
            error: errorMessage,
          },
          status: MESSAGE_STATUS.FAILED,
        });
      }
      throw error;
    }
  },

  // ── In-conversation "uploading" bubble (WhatsApp-style) ───────────────────
  // Inject an optimistic OUTGOING message that shows its attachment WHILE the
  // DirectUpload is still in flight. No POST yet — the real send fires from
  // finalizePendingAttachmentMessage once the blob is stored, reusing the SAME
  // echo_id so the server copy reconciles onto this very bubble (no duplicate).
  // Returns the pending message so the caller can map uploadId → echo_id.
  addPendingAttachmentMessage: ({ commit }, data) => {
    const pendingMessage = createPendingMessage(data);
    commit(types.ADD_MESSAGE, {
      ...pendingMessage,
      status: MESSAGE_STATUS.PROGRESS,
    });
    return pendingMessage;
  },

  // Refresh the % on the uploading attachment bubble. Re-commits a NEW message
  // object on purpose: the message-list camelize cache is keyed by reference, so
  // mutating in place would not update the UI.
  updatePendingAttachmentProgress: (
    { commit, state },
    { conversationId, echoId, uploadId, percent }
  ) => {
    const chat = state.allConversations.find(c => c.id === conversationId);
    const message = findOptimisticByEchoId(chat, echoId);
    if (!message?.attachments?.length) return;
    const attachments = message.attachments.map(att =>
      att.upload_id === uploadId ? { ...att, upload_progress: percent } : att
    );
    commit(types.ADD_MESSAGE, { ...message, attachments });
  },

  // DirectUpload finished → fire the real POST reusing the SAME echo_id and the
  // freshly-stored blob signed id. sendMessageWithData re-commits PROGRESS then
  // swaps to the server copy (SENT) by echo_id.
  finalizePendingAttachmentMessage: (
    { dispatch },
    { pendingMessage, blobSignedId }
  ) => {
    // O blob já está armazenado: marca o anexo otimista como 'uploaded' (some o
    // anel) antes do POST. Se o POST falhar, a bolha cai no estado FAILED normal
    // (sem ficar com o anel "carregando" travado).
    const attachments = (pendingMessage.attachments || []).map(a => ({
      ...a,
      upload_status: 'uploaded',
      upload_progress: 100,
    }));
    return dispatch('sendMessageWithData', {
      ...pendingMessage,
      attachments,
      files: [blobSignedId],
    });
  },

  // DirectUpload failed before the POST → flip the bubble to FAILED so the agent
  // can retry. Também marca o anexo como 'failed' para o overlay "carregando"
  // sumir (senão a bolha mostra o anel + o erro ao mesmo tempo).
  markPendingAttachmentFailed: (
    { commit, state },
    { conversationId, echoId, error }
  ) => {
    const chat = state.allConversations.find(c => c.id === conversationId);
    const message = findOptimisticByEchoId(chat, echoId);
    if (!message) return;
    const attachments = (message.attachments || []).map(a =>
      a.upload_status === 'uploading' ? { ...a, upload_status: 'failed' } : a
    );
    commit(types.ADD_MESSAGE, {
      ...message,
      attachments,
      status: MESSAGE_STATUS.FAILED,
      meta: { ...(message.meta || {}), error },
    });
  },

  // Resolve optimistic messages stuck in 'progress'/'failed' after a dropped
  // socket — WITHOUT a page reload. Runs after the post-reconnect refetch has
  // pulled fresh server state into the window. For each stuck message:
  //   1. If the server already has it (matched by the now-persisted echo_id),
  //      drop the optimistic duplicate the refetch left behind.
  //   2. Otherwise, if it's a genuinely-unsent 'progress' message we can fully
  //      reconstruct, re-send it (backend dedupes by echo_id, so this can never
  //      double-send). Give up after MAX_RECONCILE_RETRIES → mark failed.
  // 'failed' messages with no server copy are left as-is (already visible; the
  // user retries manually). See docs + F4 spec.
  reconcilePendingMessages: async (
    { commit, state, dispatch },
    { conversationId } = {}
  ) => {
    const chat = state.allConversations.find(c => c.id === conversationId);
    if (!chat?.messages?.length) return;

    const pendings = chat.messages.filter(
      m =>
        isUnreconciledOptimistic(m) &&
        // Upload em andamento: ainda não há POST/blob — não reenviar nem falhar.
        !isUploadingOptimistic(m) &&
        (m.status === MESSAGE_STATUS.PROGRESS ||
          m.status === MESSAGE_STATUS.FAILED)
    );

    // Sequential on purpose: keeps resends ordered and avoids hammering the API.
    // eslint-disable-next-line no-restricted-syntax
    for (const pending of pendings) {
      const serverCopy = chat.messages.find(
        m =>
          m !== pending &&
          !isUnreconciledOptimistic(m) &&
          m.additional_attributes?.echo_id === pending.echo_id
      );

      if (serverCopy) {
        reconcileAttempts.delete(pending.echo_id);
        commit(types.REMOVE_OPTIMISTIC_MESSAGE, {
          conversationId,
          echoId: pending.echo_id,
        });
        // eslint-disable-next-line no-continue
        continue;
      }

      if (pending.status !== MESSAGE_STATUS.PROGRESS) {
        // Already-failed with no server copy: visible; leave for manual retry.
        // eslint-disable-next-line no-continue
        continue;
      }

      // Only resend what we can fully reconstruct. An attachment message whose
      // File objects are gone (e.g. after a reload) would otherwise be sent
      // without its media — surface it as failed instead.
      const hasPlaceholderAttachment = pending.attachments?.length > 0;
      const hasResendableFiles = pending.files?.length > 0;
      if (hasPlaceholderAttachment && !hasResendableFiles) {
        commit(types.ADD_MESSAGE, {
          ...pending,
          status: MESSAGE_STATUS.FAILED,
        });
        // eslint-disable-next-line no-continue
        continue;
      }

      const attempts = reconcileAttempts.get(pending.echo_id) || 0;
      if (attempts >= MAX_RECONCILE_RETRIES) {
        reconcileAttempts.delete(pending.echo_id);
        commit(types.ADD_MESSAGE, {
          ...pending,
          status: MESSAGE_STATUS.FAILED,
        });
        // eslint-disable-next-line no-continue
        continue;
      }

      reconcileAttempts.set(pending.echo_id, attempts + 1);
      try {
        // eslint-disable-next-line no-await-in-loop
        await dispatch('sendMessageWithData', pending);
        reconcileAttempts.delete(pending.echo_id);
      } catch (error) {
        // sendMessageWithData already flips the message to 'failed' on a hard
        // error; keep the attempt count so a later reconnect can retry up to
        // the cap.
      }
    }
  },

  addMessage({ commit, rootGetters }, message) {
    commit(types.ADD_MESSAGE, message);
    if (message.message_type === MESSAGE_TYPE.INCOMING) {
      commit(types.SET_CONVERSATION_CAN_REPLY, {
        conversationId: message.conversation_id,
        canReply: true,
      });
      commit(types.ADD_CONVERSATION_ATTACHMENTS, message);
    }
    handleVoiceCallCreated(message, rootGetters?.getCurrentUserID);
  },

  updateMessage({ commit, rootGetters, state }, message) {
    // Status updates (e.g. WAHA status sync) re-emit `message.updated` over ActionCable
    // for messages that may not be in the current window. Re-injecting them via
    // ADD_MESSAGE used to break chronological order (see Bug fix 06-mai-2026).
    // Skip when the message is not visible — the user will get fresh state on next fetch.
    const chat = state.allConversations.find(
      c => c.id === message.conversation_id
    );
    const exists = chat?.messages?.some(m => m.id === message.id);
    if (exists) {
      commit(types.ADD_MESSAGE, message);
    }
    handleVoiceCallUpdated(commit, message, rootGetters?.getCurrentUserID);
  },

  deleteMessage: async function deleteMessage(
    { commit },
    { conversationId, messageId }
  ) {
    try {
      const { data } = await MessageApi.delete(conversationId, messageId);
      commit(types.ADD_MESSAGE, data);
      commit(types.DELETE_CONVERSATION_ATTACHMENTS, data);
    } catch (error) {
      throw new Error(error);
    }
  },

  updateMessageContent: async function updateMessageContent(
    { commit },
    { conversationId, messageId, content }
  ) {
    try {
      const { data } = await MessageApi.updateContent(
        conversationId,
        messageId,
        content
      );
      commit(types.ADD_MESSAGE, data);
    } catch (error) {
      throw new Error(error);
    }
  },

  deleteConversation: async ({ commit, dispatch }, conversationId) => {
    try {
      await ConversationApi.delete(conversationId);
      commit(types.DELETE_CONVERSATION, conversationId);
      dispatch('conversationStats/get', {}, { root: true });
    } catch (error) {
      throw new Error(error);
    }
  },

  addConversation({ commit, state, dispatch, rootState }, conversation) {
    const { currentInbox, appliedFilters } = state;
    const {
      inbox_id: inboxId,
      meta: { sender },
    } = conversation;
    const hasAppliedFilters = !!appliedFilters.length;
    const isMatchingInboxFilter =
      !currentInbox || Number(currentInbox) === inboxId;
    if (
      !hasAppliedFilters &&
      !isOnFoldersView(rootState) &&
      !isOnMentionsView(rootState) &&
      !isOnUnattendedView(rootState) &&
      isMatchingInboxFilter
    ) {
      commit(types.ADD_CONVERSATION, conversation);
      dispatch('contacts/setContact', sender);
    }
  },

  addMentions({ dispatch, rootState }, conversation) {
    if (isOnMentionsView(rootState)) {
      dispatch('updateConversation', conversation);
    }
  },

  addUnattended({ dispatch, rootState }, conversation) {
    if (isOnUnattendedView(rootState)) {
      dispatch('updateConversation', conversation);
    }
  },

  updateConversation({ commit, dispatch }, conversation) {
    const {
      meta: { sender },
    } = conversation;
    commit(types.UPDATE_CONVERSATION, conversation);

    dispatch('conversationLabels/setConversationLabel', {
      id: conversation.id,
      data: conversation.labels,
    });

    dispatch('contacts/setContact', sender);
  },

  updateConversationLastActivity(
    { commit },
    { conversationId, lastActivityAt }
  ) {
    commit(types.UPDATE_CONVERSATION_LAST_ACTIVITY, {
      lastActivityAt,
      conversationId,
    });
  },

  setChatStatusFilter({ commit }, data) {
    commit(types.CHANGE_CHAT_STATUS_FILTER, data);
  },

  setChatSortFilter({ commit }, data) {
    commit(types.CHANGE_CHAT_SORT_FILTER, data);
  },

  updateAssignee({ commit }, data) {
    commit(types.UPDATE_ASSIGNEE, data);
  },

  updateConversationContact({ commit }, data) {
    if (data.id) {
      commit(`contacts/${types.SET_CONTACT_ITEM}`, data);
    }
    commit(types.UPDATE_CONVERSATION_CONTACT, data);
  },

  setActiveInbox({ commit }, inboxId) {
    commit(types.SET_ACTIVE_INBOX, inboxId);
  },

  muteConversation: async ({ commit }, conversationId) => {
    try {
      await ConversationApi.mute(conversationId);
      commit(types.MUTE_CONVERSATION);
    } catch (error) {
      //
    }
  },

  unmuteConversation: async ({ commit }, conversationId) => {
    try {
      await ConversationApi.unmute(conversationId);
      commit(types.UNMUTE_CONVERSATION);
    } catch (error) {
      //
    }
  },

  sendEmailTranscript: async (_, { conversationId, email }) => {
    await ConversationApi.sendEmailTranscript({ conversationId, email });
  },

  updateCustomAttributes: async (
    { commit },
    { conversationId, customAttributes }
  ) => {
    try {
      const response = await ConversationApi.updateCustomAttributes({
        conversationId,
        customAttributes,
      });
      const { custom_attributes } = response.data;
      commit(types.UPDATE_CONVERSATION_CUSTOM_ATTRIBUTES, {
        conversationId,
        customAttributes: custom_attributes,
      });
    } catch (error) {
      // Handle error
    }
  },

  setConversationFilters({ commit }, data) {
    commit(types.SET_CONVERSATION_FILTERS, data);
  },

  clearConversationFilters({ commit }) {
    commit(types.CLEAR_CONVERSATION_FILTERS);
  },

  setChatListFilters({ commit }, data) {
    commit(types.SET_CHAT_LIST_FILTERS, data);
  },

  updateChatListFilters({ commit }, data) {
    commit(types.UPDATE_CHAT_LIST_FILTERS, data);
  },

  assignPriority: async ({ dispatch }, { conversationId, priority }) => {
    try {
      await ConversationApi.togglePriority({
        conversationId,
        priority,
      });

      dispatch('setCurrentChatPriority', {
        priority,
        conversationId,
      });
    } catch (error) {
      // Handle error
    }
  },

  setCurrentChatPriority({ commit }, { priority, conversationId }) {
    commit(types.ASSIGN_PRIORITY, { priority, conversationId });
  },

  setContextMenuChatId({ commit }, chatId) {
    commit(types.SET_CONTEXT_MENU_CHAT_ID, chatId);
  },

  getInboxCaptainAssistantById: async ({ commit }, conversationId) => {
    try {
      const response = await ConversationApi.getInboxAssistant(conversationId);
      commit(types.SET_INBOX_CAPTAIN_ASSISTANT, response.data);
    } catch (error) {
      // Handle error
    }
  },

  ...messageReadActions,
  ...messageTranslateActions,
};

export default actions;
