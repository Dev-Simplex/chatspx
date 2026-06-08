import { defineStore, acceptHMRUpdate } from 'pinia';
import * as Sentry from '@sentry/vue';

import ConversationApi from '../../api/inbox/conversation';
import MessageApi from '../../api/inbox/message';
import NotificationsAPI from '../../api/notifications';

import { MESSAGE_STATUS, MESSAGE_TYPE } from 'shared/constants/messages';
import { createPendingMessage } from 'dashboard/helper/commons';
import { BUS_EVENTS } from '../../../shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import { CONTENT_TYPES } from 'dashboard/components-next/message/constants.js';
import wootConstants from 'dashboard/constants/globals';

import {
  findPendingMessageIndex,
  applyPageFilters,
  applyRoleFilter,
  sortComparator,
} from '../modules/conversations/helpers';
import { matchesFilters } from '../modules/conversations/helpers/filterHelpers';
import {
  buildConversationList,
  isOnMentionsView,
  isOnUnattendedView,
  isOnFoldersView,
} from '../modules/conversations/helpers/actionHelpers';
import filterQueryGenerator from 'dashboard/helper/filterQueryGenerator';
import {
  getUserPermissions,
  getUserRole,
} from '../../helper/permissionsHelper';
import camelcaseKeys from 'camelcase-keys';
import { throwErrorMessage } from 'dashboard/store/utils/api';
import {
  handleVoiceCallCreated,
  handleVoiceCallUpdated,
} from 'dashboard/helper/voice';

// Espelho Pinia de store/modules/conversations/* (Onda 3 P0-05).
// - Vuex segue intacto (consumidores Vue nao foram tocados)
// - Mutations + actions fundidas em actions Pinia (this.*)
// - Cross-store Vuex (`dispatch('xxx/...')`) sao mantidas via window.$store
//   quando precisamos invocar OUTROS modulos Vuex (auth, notifications,
//   contacts, conversationMetadata, conversationLabels, conversationPage,
//   conversationStats). Isso evita ciclos de import e duplicar logica
//   dos outros stores. O Pinia da Onda 3 e um espelho passivo; consumidores
//   nao migrados continuam batendo no Vuex original.

export const MESSAGE_WINDOW_SIZE = 500;

const rebuildConversationMap = state => {
  const map = {};
  state.allConversations.forEach(c => {
    map[c.id] = c;
  });
  state.conversationMap = map;
};

const findConversation = (state, id) => {
  const numId = Number(id);
  if (state.conversationMap) {
    return state.conversationMap[numId];
  }
  return state.allConversations.find(c => c.id === numId);
};

const trimOldest = chat => {
  if (chat.messages && chat.messages.length > MESSAGE_WINDOW_SIZE) {
    chat.messages = chat.messages.slice(
      chat.messages.length - MESSAGE_WINDOW_SIZE
    );
  }
};

const trimNewest = chat => {
  if (chat.messages && chat.messages.length > MESSAGE_WINDOW_SIZE) {
    chat.messages = chat.messages.slice(0, MESSAGE_WINDOW_SIZE);
    chat.hasNewerMessages = true;
  }
};

export const hasMessageFailedWithExternalError = pendingMessage => {
  const { content_attributes: contentAttributes, status } = pendingMessage;
  const externalError = contentAttributes?.external_error ?? '';
  return status === MESSAGE_STATUS.FAILED && externalError !== '';
};

const getSelectedChatConversation = ({
  conversationMap,
  allConversations,
  selectedChatId,
}) => {
  if (conversationMap) {
    const chat = conversationMap[selectedChatId];
    return chat ? [chat] : [];
  }
  const chat = allConversations.find(
    conversation => conversation.id === selectedChatId
  );
  return chat ? [chat] : [];
};

// Helpers para falar com Vuex sem criar ciclos de import com outras
// Pinia stores. window.$store e setado pelo bootstrap do app (main.js).
const vuexDispatch = (action, payload, options) => {
  if (typeof window === 'undefined' || !window.$store) return undefined;
  return window.$store.dispatch(action, payload, options);
};

const vuexCommit = (mutation, payload, options) => {
  if (typeof window === 'undefined' || !window.$store) return undefined;
  return window.$store.commit(mutation, payload, options);
};

const vuexRootState = () => {
  if (typeof window === 'undefined' || !window.$store) return {};
  return window.$store.state || {};
};

const vuexRootGetter = key => {
  if (typeof window === 'undefined' || !window.$store) return undefined;
  return window.$store.getters?.[key];
};

export const useConversationsStore = defineStore('conversations', {
  state: () => ({
    allConversations: [],
    conversationMap: {},
    attachments: {},
    attachmentsMeta: {},
    listLoadingStatus: true,
    chatStatusFilter: wootConstants.STATUS_TYPE.OPEN,
    chatSortFilter: wootConstants.SORT_BY_TYPE.LATEST,
    currentInbox: null,
    selectedChatId: null,
    appliedFilters: [],
    contextMenuChatId: null,
    conversationParticipants: [],
    conversationLastSeen: null,
    syncConversationsMessages: {},
    conversationFilters: {},
    copilotAssistant: {},
  }),

  getters: {
    getAllConversations: state => {
      return [...state.allConversations].sort((a, b) =>
        sortComparator(a, b, state.chatSortFilter)
      );
    },
    getFilteredConversations: state => {
      const currentUser = vuexRootGetter('getCurrentUser') || {};
      const currentUserId = currentUser.id;
      const currentAccountId = vuexRootGetter('getCurrentAccountId');

      const permissions = getUserPermissions(currentUser, currentAccountId);
      const userRole = getUserRole(currentUser, currentAccountId);

      return state.allConversations
        .filter(conversation => {
          const matchesFilterResult = matchesFilters(
            conversation,
            state.appliedFilters
          );
          const allowedForRole = applyRoleFilter(
            conversation,
            userRole,
            permissions,
            currentUserId
          );
          return matchesFilterResult && allowedForRole;
        })
        .sort((a, b) => sortComparator(a, b, state.chatSortFilter));
    },
    getSelectedChat: state => {
      if (state.conversationMap) {
        return state.conversationMap[state.selectedChatId] || {};
      }
      const selectedChat = state.allConversations.find(
        c => c.id === state.selectedChatId
      );
      return selectedChat || {};
    },
    getSelectedChatAttachments: state =>
      state.attachments[state.selectedChatId] || [],
    getSelectedChatAttachmentsMeta: state =>
      state.attachmentsMeta[state.selectedChatId] || {
        currentPage: 1,
        totalPages: 1,
        totalCount: 0,
      },
    getChatListFilters: state => state.conversationFilters,
    getLastEmailInSelectedChat() {
      const selectedChat = this.getSelectedChat;
      const { messages = [] } = selectedChat;
      const lastEmail = [...messages].reverse().find(message => {
        const { message_type: messageType } = message;
        if (message.private) return false;
        return [MESSAGE_TYPE.OUTGOING, MESSAGE_TYPE.INCOMING].includes(
          messageType
        );
      });
      return lastEmail;
    },
    getMineChats: state => {
      const currentUserID = vuexRootGetter('getCurrentUser')?.id;
      const filters = state.conversationFilters;
      return state.allConversations
        .filter(conversation => {
          const { assignee } = conversation.meta;
          const isAssignedToMe = assignee && assignee.id === currentUserID;
          const shouldFilter = applyPageFilters(conversation, filters);
          return isAssignedToMe && shouldFilter;
        })
        .sort((a, b) => sortComparator(a, b, state.chatSortFilter));
    },
    getAppliedConversationFiltersV2: state =>
      state.appliedFilters.map(camelcaseKeys),
    getAppliedConversationFilters: state => state.appliedFilters,
    getAppliedConversationFiltersQuery: state => {
      const hasAppliedFilters = state.appliedFilters.length !== 0;
      return hasAppliedFilters
        ? filterQueryGenerator(state.appliedFilters)
        : [];
    },
    getUnAssignedChats: state => {
      const filters = state.conversationFilters;
      return state.allConversations
        .filter(conversation => {
          const isUnAssigned = !conversation.meta.assignee;
          const shouldFilter = applyPageFilters(conversation, filters);
          return isUnAssigned && shouldFilter;
        })
        .sort((a, b) => sortComparator(a, b, state.chatSortFilter));
    },
    getAllStatusChats: state => {
      const currentUser = vuexRootGetter('getCurrentUser') || {};
      const currentUserId = currentUser.id;
      const currentAccountId = vuexRootGetter('getCurrentAccountId');
      const permissions = getUserPermissions(currentUser, currentAccountId);
      const userRole = getUserRole(currentUser, currentAccountId);
      const filters = state.conversationFilters;
      return state.allConversations
        .filter(conversation => {
          const shouldFilter = applyPageFilters(conversation, filters);
          const allowedForRole = applyRoleFilter(
            conversation,
            userRole,
            permissions,
            currentUserId
          );
          return shouldFilter && allowedForRole;
        })
        .sort((a, b) => sortComparator(a, b, state.chatSortFilter));
    },
    getChatListLoadingStatus: state => state.listLoadingStatus,
    getAllMessagesLoaded(state) {
      const [chat] = getSelectedChatConversation(state);
      return !chat || chat.allMessagesLoaded === undefined
        ? false
        : chat.allMessagesLoaded;
    },
    getHasNewerMessages(state) {
      const [chat] = getSelectedChatConversation(state);
      return chat ? !!chat.hasNewerMessages : false;
    },
    getPendingNewMessageCount(state) {
      const [chat] = getSelectedChatConversation(state);
      return chat ? chat.pendingNewMessageCount || 0 : 0;
    },
    getUnreadCount(state) {
      const [chat] = getSelectedChatConversation(state);
      if (!chat) return [];
      return chat.messages.filter(
        chatMessage =>
          chatMessage.created_at * 1000 > chat.agent_last_seen_at * 1000 &&
          chatMessage.message_type === 0 &&
          chatMessage.private !== true
      ).length;
    },
    getChatStatusFilter: state => state.chatStatusFilter,
    getChatSortFilter: state => state.chatSortFilter,
    getSelectedInbox: state => state.currentInbox,
    getConversationById: state => conversationId => {
      if (state.conversationMap) {
        return state.conversationMap[Number(conversationId)];
      }
      return state.allConversations.find(c => c.id === Number(conversationId));
    },
    getConversationParticipants: state => state.conversationParticipants,
    getConversationLastSeen: state => state.conversationLastSeen,
    getContextMenuChatId: state => state.contextMenuChatId,
    getCopilotAssistant: state => state.copilotAssistant,
  },

  actions: {
    // ===== mutations (state writes) =====
    setAllConversation(conversationList) {
      const existingMap = new Map(this.allConversations.map(c => [c.id, c]));
      conversationList.forEach(conversation => {
        const existing = existingMap.get(conversation.id);
        if (!existing) {
          existingMap.set(conversation.id, conversation);
        } else if (conversation.id !== this.selectedChatId) {
          existingMap.set(conversation.id, conversation);
        } else {
          existingMap.set(conversation.id, {
            ...conversation,
            allMessagesLoaded: existing.allMessagesLoaded,
            messages: existing.messages,
            dataFetched: existing.dataFetched,
          });
        }
      });
      this.allConversations = Array.from(existingMap.values());
      rebuildConversationMap(this);
    },
    emptyAllConversation() {
      this.allConversations = [];
      this.conversationMap = {};
      this.selectedChatId = null;
      this.attachments = {};
      this.attachmentsMeta = {};
      this.syncConversationsMessages = {};
    },
    setAllMessagesLoaded(conversationId) {
      const chat = findConversation(this, conversationId);
      if (!chat) return;
      chat.allMessagesLoaded = true;
    },
    clearAllMessagesLoaded(conversationId) {
      const chat = findConversation(this, conversationId);
      if (!chat) return;
      chat.allMessagesLoaded = false;
    },
    clearCurrentChatWindow() {
      this.selectedChatId = null;
    },
    setPreviousConversations({ id, data }) {
      if (data.length) {
        const chat = findConversation(this, id);
        if (!chat) return;
        chat.messages.unshift(...data);
        trimNewest(chat);
      }
    },
    setNextConversations({ id, data }) {
      if (data.length) {
        const chat = findConversation(this, id);
        if (!chat) return;
        chat.messages.push(...data);
        trimOldest(chat);
      }
    },
    setAllNewerMessagesLoaded(conversationId) {
      const chat = findConversation(this, conversationId);
      if (!chat) return;
      chat.hasNewerMessages = false;
    },
    clearNewerMessagesFlag(conversationId) {
      const chat = findConversation(this, conversationId);
      if (!chat) return;
      chat.hasNewerMessages = false;
    },
    setAllAttachments({ id, data, meta }) {
      this.attachments[id] = [...data];
      if (meta) {
        this.attachmentsMeta[id] = {
          currentPage: meta.current_page || 1,
          totalPages: meta.total_pages || 1,
          totalCount: meta.total_count || data.length,
        };
      }
    },
    appendAttachments({ id, data, meta }) {
      const existing = this.attachments[id] || [];
      const existingIds = new Set(existing.map(a => a.id));
      const newAttachments = data.filter(a => !existingIds.has(a.id));
      this.attachments[id] = [...existing, ...newAttachments];
      if (meta) {
        this.attachmentsMeta[id] = {
          currentPage: meta.current_page || 1,
          totalPages: meta.total_pages || 1,
          totalCount: meta.total_count || this.attachments[id].length,
        };
      }
    },
    setMissingMessages({ id, data }) {
      const chat = findConversation(this, id);
      if (!chat) return;
      chat.messages = data;
    },
    setChatDataFetched(conversationId) {
      const chat = findConversation(this, conversationId);
      if (chat) chat.dataFetched = true;
    },
    setCurrentChatWindow(activeChat) {
      if (activeChat) this.selectedChatId = activeChat.id;
    },
    assignAgentLocal({ conversationId, assignee }) {
      const chat = findConversation(this, conversationId);
      if (!chat) return;
      chat.meta.assignee = assignee;
    },
    assignTeamLocal({ team, conversationId }) {
      const chat = findConversation(this, conversationId);
      if (!chat) return;
      const updated = { ...chat, meta: { ...chat.meta, team } };
      const index = this.allConversations.indexOf(chat);
      if (index !== -1) this.allConversations.splice(index, 1, updated);
      if (this.conversationMap) this.conversationMap[updated.id] = updated;
    },
    updateConversationLastActivityLocal({ lastActivityAt, conversationId }) {
      const chat = findConversation(this, conversationId);
      if (!chat) return;
      chat.last_activity_at = lastActivityAt;
    },
    assignPriorityLocal({ priority, conversationId }) {
      const chat = findConversation(this, conversationId);
      if (!chat) return;
      const updated = { ...chat, priority };
      const index = this.allConversations.indexOf(chat);
      if (index !== -1) this.allConversations.splice(index, 1, updated);
      if (this.conversationMap) this.conversationMap[updated.id] = updated;
    },
    updateConversationCustomAttributesLocal({
      conversationId,
      customAttributes,
    }) {
      const conversation = findConversation(this, conversationId);
      if (!conversation) return;
      conversation.custom_attributes = {
        ...conversation.custom_attributes,
        ...customAttributes,
      };
    },
    changeConversationStatusLocal({ conversationId, status, snoozedUntil }) {
      const conversation = findConversation(this, conversationId);
      if (!conversation) return;
      const updated = { ...conversation, status, snoozed_until: snoozedUntil };
      const index = this.allConversations.indexOf(conversation);
      if (index !== -1) this.allConversations.splice(index, 1, updated);
      if (this.conversationMap) this.conversationMap[updated.id] = updated;
    },
    muteConversationLocal() {
      const [chat] = getSelectedChatConversation(this);
      if (!chat) return;
      chat.muted = true;
    },
    unmuteConversationLocal() {
      const [chat] = getSelectedChatConversation(this);
      if (!chat) return;
      chat.muted = false;
    },
    addConversationAttachments(message) {
      if (
        message.status !== MESSAGE_STATUS.SENT ||
        !message.attachments?.length
      ) {
        return;
      }
      const id = message.conversation_id;
      const existingAttachments = this.attachments[id] || [];
      const attachmentsToAdd = message.attachments.filter(attachment => {
        return !existingAttachments.some(
          existingAttachment => existingAttachment.id === attachment.id
        );
      });
      this.attachments[id] = [...existingAttachments, ...attachmentsToAdd];
    },
    deleteConversationAttachments(message) {
      if (message.status !== MESSAGE_STATUS.SENT) return;
      const { conversation_id: id } = message;
      const existingAttachments = this.attachments[id] || [];
      if (!existingAttachments.length) return;
      this.attachments[id] = existingAttachments.filter(attachment => {
        return attachment.message_id !== message.id;
      });
    },
    addMessageLocal(message) {
      const { conversation_id: conversationId } = message;
      const chat = findConversation(this, conversationId);
      if (!chat) return;

      const pendingMessageIndex = findPendingMessageIndex(chat, message);
      if (pendingMessageIndex !== -1) {
        chat.messages[pendingMessageIndex] = message;
      } else if (chat.hasNewerMessages) {
        chat.pendingNewMessageCount = (chat.pendingNewMessageCount || 0) + 1;
        chat.timestamp = message.created_at;
        const { conversation: { unread_count: unreadCount = 0 } = {} } =
          message;
        chat.unread_count = unreadCount;
      } else {
        chat.messages.push(message);
        trimOldest(chat);
        chat.timestamp = message.created_at;
        const { conversation: { unread_count: unreadCount = 0 } = {} } =
          message;
        chat.unread_count = unreadCount;
        if (this.selectedChatId === conversationId) {
          emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE);
        }
      }
    },
    addConversationLocal(conversation) {
      const exists = findConversation(this, conversation.id);
      if (!exists) {
        this.allConversations.push(conversation);
        if (this.conversationMap) {
          this.conversationMap[conversation.id] = conversation;
        }
      }
    },
    deleteConversationLocal(conversationId) {
      this.allConversations = this.allConversations.filter(
        c => c.id !== conversationId
      );
      if (this.conversationMap) delete this.conversationMap[conversationId];
      if (this.attachments) delete this.attachments[conversationId];
      if (this.syncConversationsMessages) {
        delete this.syncConversationsMessages[conversationId];
      }
    },
    updateConversationLocal(conversation) {
      const existingChat = findConversation(this, conversation.id);
      if (existingChat) {
        if (conversation.updated_at < existingChat.updated_at) return;
        const index = this.allConversations.indexOf(existingChat);
        const { messages, ...updates } = conversation;
        const updated = { ...existingChat, ...updates };
        this.allConversations[index] = updated;
        if (this.conversationMap) {
          this.conversationMap[conversation.id] = updated;
        }
        if (this.selectedChatId === conversation.id) {
          emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE);
        }
      } else {
        this.allConversations.push(conversation);
        if (this.conversationMap) {
          this.conversationMap[conversation.id] = conversation;
        }
      }
    },
    setListLoadingStatus() {
      this.listLoadingStatus = true;
    },
    clearListLoadingStatus() {
      this.listLoadingStatus = false;
    },
    updateMessageUnreadCount({ id, lastSeen, unreadCount = 0 }) {
      const chat = findConversation(this, id);
      if (!chat) return;
      chat.agent_last_seen_at = lastSeen;
      chat.unread_count = unreadCount;
    },
    changeChatStatusFilter(data) {
      this.chatStatusFilter = data;
    },
    changeChatSortFilter(data) {
      this.chatSortFilter = data;
    },
    updateAssigneeLocal(payload) {
      const chat = findConversation(this, payload.id);
      if (!chat) return;
      chat.meta.assignee = payload.assignee;
    },
    updateConversationContactLocal({ conversationId, ...payload }) {
      const chat = findConversation(this, conversationId);
      if (!chat) return;
      chat.meta.sender = payload;
    },
    updateConversationCallStatus({ conversationId, callStatus }) {
      const chat = findConversation(this, conversationId);
      if (!chat) return;
      chat.additional_attributes = {
        ...chat.additional_attributes,
        call_status: callStatus,
      };
    },
    updateMessageCallStatus({ conversationId, callStatus }) {
      const chat = findConversation(this, conversationId);
      if (!chat) return;
      const lastCall = (chat.messages || []).findLast(
        m => m.content_type === CONTENT_TYPES.VOICE_CALL
      );
      if (!lastCall) return;
      lastCall.content_attributes ??= {};
      lastCall.content_attributes.data = {
        ...lastCall.content_attributes.data,
        status: callStatus,
      };
    },
    setActiveInboxLocal(inboxId) {
      this.currentInbox = inboxId ? parseInt(inboxId, 10) : null;
    },
    setConversationCanReply({ conversationId, canReply }) {
      const chat = findConversation(this, conversationId);
      if (!chat) return;
      chat.can_reply = canReply;
    },
    clearContactConversations(contactId) {
      const chats = this.allConversations.filter(
        c => c.meta.sender.id !== contactId
      );
      this.allConversations = chats;
      if (this.conversationMap) rebuildConversationMap(this);
    },
    setConversationFiltersLocal(data) {
      this.appliedFilters = data;
    },
    clearConversationFiltersLocal() {
      this.appliedFilters = [];
    },
    setLastMessageIdInSyncConversation({ conversationId, messageId }) {
      this.syncConversationsMessages[conversationId] = messageId;
    },
    setContextMenuChatIdLocal(chatId) {
      this.contextMenuChatId = chatId;
    },
    setChatListFiltersLocal(data) {
      this.conversationFilters = data;
    },
    updateChatListFiltersLocal(data) {
      this.conversationFilters = { ...this.conversationFilters, ...data };
    },
    setInboxCaptainAssistant(data) {
      this.copilotAssistant = data.assistant;
    },

    // ===== async actions =====
    async getConversation(conversationId) {
      const response = await ConversationApi.show(conversationId);
      this.updateConversationLocal(response.data);
      vuexCommit('contacts/SET_CONTACT_ITEM', response.data.meta.sender);
    },

    async fetchAllConversations() {
      this.setListLoadingStatus();
      const params = this.conversationFilters;
      try {
        const {
          data: { data },
        } = await ConversationApi.get(params);
        // buildConversationList espera context com commit/dispatch:
        // criamos shim que reusa o Vuex root pra disparar conversationStats,
        // conversationLabels e conversationPage (modulos que ainda nao
        // estao migrados pra Pinia como consumidores ativos).
        buildConversationList(
          {
            commit: (mutation, payload) => {
              // mutations do proprio modulo conversations vao pra esta store;
              // outros modulos sao redirecionados pro Vuex.
              if (mutation === 'SET_ALL_CONVERSATION') {
                this.setAllConversation(payload);
              } else if (mutation === 'CLEAR_LIST_LOADING_STATUS') {
                this.clearListLoadingStatus();
              } else {
                vuexCommit(mutation, payload);
              }
            },
            dispatch: vuexDispatch,
          },
          params,
          data,
          params.assigneeType
        );
      } catch (error) {
        const isAbort =
          error?.name === 'AbortError' || error?.code === 'ERR_CANCELED';
        if (isAbort) return;
        this.clearListLoadingStatus();
      }
    },

    async fetchFilteredConversations(params) {
      this.setListLoadingStatus();
      try {
        const { data } = await ConversationApi.filter(params);
        buildConversationList(
          {
            commit: (mutation, payload) => {
              if (mutation === 'SET_ALL_CONVERSATION') {
                this.setAllConversation(payload);
              } else if (mutation === 'CLEAR_LIST_LOADING_STATUS') {
                this.clearListLoadingStatus();
              } else {
                vuexCommit(mutation, payload);
              }
            },
            dispatch: vuexDispatch,
          },
          params,
          data,
          'appliedFilters'
        );
      } catch (error) {
        const isAbort =
          error?.name === 'AbortError' || error?.code === 'ERR_CANCELED';
        if (isAbort) return;
        this.clearListLoadingStatus();
      }
    },

    emptyAllConversations() {
      this.emptyAllConversation();
    },

    clearSelectedState() {
      this.clearCurrentChatWindow();
    },

    async fetchPreviousMessages(data) {
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
          vuexCommit('conversationMetadata/SET_CONVERSATION_METADATA', {
            id: data.conversationId,
            data: meta,
          });
        }

        this.setPreviousConversations({
          id: data.conversationId,
          data: payload,
        });

        if (hasMoreAvailable ? !hasMore : !payload.length) {
          this.setAllMessagesLoaded(data.conversationId);
        }
      } catch (error) {
        // silent
      }
    },

    async fetchNextMessages(data) {
      try {
        const {
          data: { meta = {}, payload = [] },
        } = await MessageApi.getPreviousMessages({
          conversationId: data.conversationId,
          after: data.after,
          includeMeta: true,
        });

        this.setNextConversations({ id: data.conversationId, data: payload });

        const hasMore = meta.has_more;
        if (typeof hasMore === 'boolean' ? !hasMore : !payload.length) {
          this.setAllNewerMessagesLoaded(data.conversationId);
        }
      } catch (error) {
        // silent
      }
    },

    async jumpToLatest(conversationId) {
      this.clearNewerMessagesFlag(conversationId);
      this.clearAllMessagesLoaded(conversationId);
      try {
        const {
          data: { meta = {}, payload = [] },
        } = await MessageApi.getPreviousMessages({
          conversationId,
          includeMeta: true,
        });

        if (Object.keys(meta).length) {
          vuexCommit('conversationMetadata/SET_CONVERSATION_METADATA', {
            id: conversationId,
            data: meta,
          });
        }

        this.setMissingMessages({ id: conversationId, data: payload });

        if (!meta.has_more) {
          this.setAllMessagesLoaded(conversationId);
        }
      } catch (error) {
        // silent
      }
    },

    async fetchAllAttachments(conversationId) {
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
        Sentry.setContext('Conversation', { id: conversationId });
        Sentry.captureException(error);
      } finally {
        this.setAllAttachments({ id: conversationId, data: attachments, meta });
      }
    },

    async fetchMoreAttachments(conversationId) {
      const currentMeta = this.attachmentsMeta[conversationId];
      if (!currentMeta || currentMeta.currentPage >= currentMeta.totalPages) {
        return;
      }
      const nextPage = currentMeta.currentPage + 1;
      try {
        const { data } = await ConversationApi.getAllAttachments(
          conversationId,
          nextPage
        );
        this.appendAttachments({
          id: conversationId,
          data: data.payload,
          meta: data.meta || {},
        });
      } catch (error) {
        Sentry.setContext('Conversation', { id: conversationId });
        Sentry.captureException(error);
      }
    },

    async syncActiveConversationMessages({ conversationId }) {
      const { allConversations, syncConversationsMessages } = this;
      const lastMessageId = syncConversationsMessages[conversationId];
      const selectedChat = allConversations.find(
        conversation => conversation.id === conversationId
      );
      if (!selectedChat) return;
      try {
        const { messages } = selectedChat;
        const {
          data: { meta, payload },
        } = await MessageApi.getPreviousMessages({
          conversationId,
          after: lastMessageId,
        });
        vuexCommit('conversationMetadata/SET_CONVERSATION_METADATA', {
          id: conversationId,
          data: meta,
        });
        const existingIds = new Set(messages.map(m => m.id));
        const missingMessages = payload.filter(m => !existingIds.has(m.id));
        selectedChat.messages.push(...missingMessages);
        const sortedMessages = selectedChat.messages.sort((a, b) => {
          return new Date(a.created_at) - new Date(b.created_at);
        });
        this.setMissingMessages({ id: conversationId, data: sortedMessages });
        this.setLastMessageIdInSyncConversation({
          conversationId,
          messageId: null,
        });
        this.markMessagesRead({ id: conversationId });
      } catch (error) {
        // silent
      }
    },

    setConversationLastMessageId({ conversationId }) {
      const selectedChat = this.allConversations.find(
        conversation => conversation.id === conversationId
      );
      if (!selectedChat) return;
      const { messages } = selectedChat;
      const lastMessage = messages.last();
      if (!lastMessage) return;
      this.setLastMessageIdInSyncConversation({
        conversationId,
        messageId: lastMessage.id,
      });
    },

    async setActiveChat({ data, after }) {
      this.setCurrentChatWindow(data);
      this.clearAllMessagesLoaded(data.id);
      if (data.dataFetched === undefined) {
        try {
          await this.fetchPreviousMessages({
            after,
            before: data.messages[0].id,
            conversationId: data.id,
            includeMeta: true,
          });
          this.setChatDataFetched(data.id);
        } catch (error) {
          // ignore
        }
      }
    },

    async assignAgent({ conversationId, agentId, rethrow = false }) {
      try {
        const response = await ConversationApi.assignAgent({
          conversationId,
          agentId,
        });
        this.setCurrentChatAssignee({
          conversationId,
          assignee: response.data,
        });
      } catch (error) {
        if (rethrow) throw error;
      }
    },

    setCurrentChatAssignee({ conversationId, assignee }) {
      this.assignAgentLocal({ conversationId, assignee });
    },

    async assignTeam({ conversationId, teamId, rethrow = false }) {
      try {
        const response = await ConversationApi.assignTeam({
          conversationId,
          teamId,
        });
        this.setCurrentChatTeam({ team: response.data, conversationId });
      } catch (error) {
        if (rethrow) throw error;
      }
    },

    setCurrentChatTeam({ team, conversationId }) {
      this.assignTeamLocal({ team, conversationId });
    },

    async toggleStatus({
      conversationId,
      status,
      snoozedUntil = null,
      customAttributes = null,
    }) {
      try {
        if (customAttributes) {
          await ConversationApi.updateCustomAttributes({
            conversationId,
            customAttributes,
          });
          this.updateConversationCustomAttributesLocal({
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
        this.changeConversationStatusLocal({
          conversationId,
          status: updatedStatus,
          snoozedUntil: updatedSnoozedUntil,
        });
      } catch (error) {
        // silent
      }
    },

    createPendingMessageAndSend(data) {
      const pendingMessage = createPendingMessage(data);
      this.sendMessageWithData(pendingMessage);
    },

    async sendMessageWithData(pendingMessage) {
      const { conversation_id: conversationId, id } = pendingMessage;
      try {
        this.addMessageLocal({
          ...pendingMessage,
          status: MESSAGE_STATUS.PROGRESS,
        });
        const response = hasMessageFailedWithExternalError(pendingMessage)
          ? await MessageApi.retry(conversationId, id)
          : await MessageApi.create(pendingMessage);
        this.addMessageLocal({
          ...response.data,
          status: MESSAGE_STATUS.SENT,
        });
        this.addConversationAttachments({
          ...response.data,
          status: MESSAGE_STATUS.SENT,
        });
      } catch (error) {
        const errorMessage = error.response
          ? error.response.data.error
          : undefined;
        this.addMessageLocal({
          ...pendingMessage,
          meta: { error: errorMessage },
          status: MESSAGE_STATUS.FAILED,
        });
        throw error;
      }
    },

    addMessage(message) {
      this.addMessageLocal(message);
      if (message.message_type === MESSAGE_TYPE.INCOMING) {
        this.setConversationCanReply({
          conversationId: message.conversation_id,
          canReply: true,
        });
        this.addConversationAttachments(message);
      }
      handleVoiceCallCreated(message, vuexRootGetter('getCurrentUserID'));
    },

    updateMessage(message) {
      this.addMessageLocal(message);
      // handleVoiceCallUpdated espera (commit, message, userId).
      // Mantemos comportamento de proxy pro store Vuex.
      handleVoiceCallUpdated(
        (mutation, payload) => vuexCommit(mutation, payload),
        message,
        vuexRootGetter('getCurrentUserID')
      );
    },

    async deleteMessage({ conversationId, messageId }) {
      try {
        const { data } = await MessageApi.delete(conversationId, messageId);
        this.addMessageLocal(data);
        this.deleteConversationAttachments(data);
      } catch (error) {
        throw new Error(error);
      }
    },

    async updateMessageContent({ conversationId, messageId, content }) {
      try {
        const { data } = await MessageApi.updateContent(
          conversationId,
          messageId,
          content
        );
        this.addMessageLocal(data);
      } catch (error) {
        throw new Error(error);
      }
    },

    async deleteConversation(conversationId) {
      try {
        await ConversationApi.delete(conversationId);
        this.deleteConversationLocal(conversationId);
        vuexDispatch('conversationStats/get', {}, { root: true });
      } catch (error) {
        throw new Error(error);
      }
    },

    addConversation(conversation) {
      const { currentInbox, appliedFilters } = this;
      const {
        inbox_id: inboxId,
        meta: { sender },
      } = conversation;
      const hasAppliedFilters = !!appliedFilters.length;
      const isMatchingInboxFilter =
        !currentInbox || Number(currentInbox) === inboxId;

      const rootState = vuexRootState();
      if (
        !hasAppliedFilters &&
        !isOnFoldersView(rootState) &&
        !isOnMentionsView(rootState) &&
        !isOnUnattendedView(rootState) &&
        isMatchingInboxFilter
      ) {
        this.addConversationLocal(conversation);
        vuexDispatch('contacts/setContact', sender);
      }
    },

    addMentions(conversation) {
      if (isOnMentionsView(vuexRootState())) {
        this.updateConversation(conversation);
      }
    },

    addUnattended(conversation) {
      if (isOnUnattendedView(vuexRootState())) {
        this.updateConversation(conversation);
      }
    },

    updateConversation(conversation) {
      const {
        meta: { sender },
      } = conversation;
      this.updateConversationLocal(conversation);
      vuexDispatch('conversationLabels/setConversationLabel', {
        id: conversation.id,
        data: conversation.labels,
      });
      vuexDispatch('contacts/setContact', sender);
    },

    updateConversationLastActivity({ conversationId, lastActivityAt }) {
      this.updateConversationLastActivityLocal({
        lastActivityAt,
        conversationId,
      });
    },

    setChatStatusFilter(data) {
      this.changeChatStatusFilter(data);
    },

    setChatSortFilter(data) {
      this.changeChatSortFilter(data);
    },

    updateAssignee(data) {
      this.updateAssigneeLocal(data);
    },

    updateConversationContact(data) {
      if (data.id) {
        vuexCommit('contacts/SET_CONTACT_ITEM', data);
      }
      this.updateConversationContactLocal(data);
    },

    setActiveInbox(inboxId) {
      this.setActiveInboxLocal(inboxId);
    },

    async muteConversation(conversationId) {
      try {
        await ConversationApi.mute(conversationId);
        this.muteConversationLocal();
      } catch (error) {
        //
      }
    },

    async unmuteConversation(conversationId) {
      try {
        await ConversationApi.unmute(conversationId);
        this.unmuteConversationLocal();
      } catch (error) {
        //
      }
    },

    async sendEmailTranscript({ conversationId, email }) {
      await ConversationApi.sendEmailTranscript({ conversationId, email });
    },

    async updateCustomAttributes({ conversationId, customAttributes }) {
      try {
        const response = await ConversationApi.updateCustomAttributes({
          conversationId,
          customAttributes,
        });
        const { custom_attributes } = response.data;
        this.updateConversationCustomAttributesLocal({
          conversationId,
          customAttributes: custom_attributes,
        });
      } catch (error) {
        // silent
      }
    },

    setConversationFilters(data) {
      this.setConversationFiltersLocal(data);
    },

    clearConversationFilters() {
      this.clearConversationFiltersLocal();
    },

    setChatListFilters(data) {
      this.setChatListFiltersLocal(data);
    },

    updateChatListFilters(data) {
      this.updateChatListFiltersLocal(data);
    },

    async assignPriority({ conversationId, priority }) {
      try {
        await ConversationApi.togglePriority({ conversationId, priority });
        this.setCurrentChatPriority({ priority, conversationId });
      } catch (error) {
        // silent
      }
    },

    setCurrentChatPriority({ priority, conversationId }) {
      this.assignPriorityLocal({ priority, conversationId });
    },

    setContextMenuChatId(chatId) {
      this.setContextMenuChatIdLocal(chatId);
    },

    async getInboxCaptainAssistantById(conversationId) {
      try {
        const response =
          await ConversationApi.getInboxAssistant(conversationId);
        this.setInboxCaptainAssistant(response.data);
      } catch (error) {
        // silent
      }
    },

    // ===== messageReadActions =====
    async markMessagesRead(data) {
      try {
        const {
          data: { id, agent_last_seen_at: lastSeen },
        } = await ConversationApi.markMessageRead(data);
        setTimeout(() => this.updateMessageUnreadCount({ id, lastSeen }), 4000);
        await this.clearMatchingNotificationInternal(data.id);
      } catch (error) {
        // silent
      }
    },

    async markMessagesUnread({ id }) {
      try {
        const {
          data: { agent_last_seen_at: lastSeen, unread_count: unreadCount },
        } = await ConversationApi.markMessagesUnread({ id });
        this.updateMessageUnreadCount({ id, lastSeen, unreadCount });
      } catch (error) {
        throwErrorMessage(error);
      }
    },

    async clearMatchingNotificationInternal(conversationId) {
      const conversationIdNum = Number(conversationId);
      if (!conversationIdNum) return;

      const notifications =
        vuexRootGetter('notifications/getNotifications') || [];
      const match = notifications.find(
        n =>
          !n.read_at &&
          n.primary_actor_type === 'Conversation' &&
          Number(n.primary_actor_id) === conversationIdNum
      );

      if (match) {
        const unreadCount = vuexRootGetter('notifications/getUnreadCount') || 0;
        await vuexDispatch(
          'notifications/read',
          {
            id: match.id,
            primaryActorType: match.primary_actor_type,
            primaryActorId: match.primary_actor_id,
            unreadCount,
          },
          { root: true }
        );
        return;
      }

      try {
        await NotificationsAPI.read('Conversation', conversationIdNum);
        await vuexDispatch('notifications/unReadCount', undefined, {
          root: true,
        });
      } catch (error) {
        // silent — auto-clear is best effort
      }
    },

    // ===== messageTranslateActions =====
    async translateMessage({ conversationId, messageId, targetLanguage }) {
      try {
        await MessageApi.translateMessage(
          conversationId,
          messageId,
          targetLanguage
        );
      } catch (error) {
        // silent
      }
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useConversationsStore, import.meta.hot)
  );
}
