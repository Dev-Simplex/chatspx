import types from '../../mutation-types';
import getters, { getSelectedChatConversation } from './getters';
import actions from './actions';
import { findPendingMessageIndex, insertSortedByCreatedAt } from './helpers';
import { MESSAGE_STATUS } from 'shared/constants/messages';
import wootConstants from 'dashboard/constants/globals';
import { BUS_EVENTS } from '../../../../shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import { CONTENT_TYPES } from 'dashboard/components-next/message/constants.js';

export const MESSAGE_WINDOW_SIZE = 500;

const state = {
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
};

// Helper to rebuild the conversationMap from the allConversations array
const rebuildConversationMap = _state => {
  const map = {};
  _state.allConversations.forEach(c => {
    map[c.id] = c;
  });
  _state.conversationMap = map;
};

// O(1) lookup with fallback for when conversationMap is not initialized
const findConversation = (_state, id) => {
  const numId = Number(id);
  if (_state.conversationMap) {
    return _state.conversationMap[numId];
  }
  return _state.allConversations.find(c => c.id === numId);
};

// Trim oldest messages (keep newest) — used when new messages arrive
const trimOldest = chat => {
  if (chat.messages && chat.messages.length > MESSAGE_WINDOW_SIZE) {
    chat.messages = chat.messages.slice(
      chat.messages.length - MESSAGE_WINDOW_SIZE
    );
  }
};

// Trim newest messages (keep oldest) — used when loading older messages
const trimNewest = chat => {
  if (chat.messages && chat.messages.length > MESSAGE_WINDOW_SIZE) {
    chat.messages = chat.messages.slice(0, MESSAGE_WINDOW_SIZE);
    chat.hasNewerMessages = true;
  }
};

// mutations
export const mutations = {
  [types.SET_ALL_CONVERSATION](_state, conversationList) {
    const existingMap = new Map(_state.allConversations.map(c => [c.id, c]));
    conversationList.forEach(conversation => {
      const existing = existingMap.get(conversation.id);
      if (!existing) {
        existingMap.set(conversation.id, conversation);
      } else if (conversation.id !== _state.selectedChatId) {
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
    _state.allConversations = Array.from(existingMap.values());
    rebuildConversationMap(_state);
  },
  [types.EMPTY_ALL_CONVERSATION](_state) {
    _state.allConversations = [];
    _state.conversationMap = {};
    _state.selectedChatId = null;
    _state.attachments = {};
    _state.attachmentsMeta = {};
    _state.syncConversationsMessages = {};
  },
  [types.SET_ALL_MESSAGES_LOADED](_state, conversationId) {
    const chat = findConversation(_state, conversationId);
    if (!chat) return;
    chat.allMessagesLoaded = true;
  },

  [types.CLEAR_ALL_MESSAGES_LOADED](_state, conversationId) {
    const chat = findConversation(_state, conversationId);
    if (!chat) return;
    chat.allMessagesLoaded = false;
  },
  [types.CLEAR_CURRENT_CHAT_WINDOW](_state) {
    _state.selectedChatId = null;
  },

  [types.SET_PREVIOUS_CONVERSATIONS](_state, { id, data }) {
    if (data.length) {
      const chat = findConversation(_state, id);
      if (!chat) return;
      const existingIds = new Set(chat.messages.map(m => m.id));
      const incoming = data.filter(m => !existingIds.has(m.id));
      if (!incoming.length) return;
      chat.messages.unshift(...incoming);
      trimNewest(chat);
    }
  },
  [types.SET_NEXT_CONVERSATIONS](_state, { id, data }) {
    if (data.length) {
      const chat = findConversation(_state, id);
      if (!chat) return;
      const existingIds = new Set(chat.messages.map(m => m.id));
      const incoming = data.filter(m => !existingIds.has(m.id));
      if (!incoming.length) return;
      chat.messages.push(...incoming);
      trimOldest(chat);
    }
  },
  [types.SET_ALL_NEWER_MESSAGES_LOADED](_state, conversationId) {
    const chat = findConversation(_state, conversationId);
    if (!chat) return;
    chat.hasNewerMessages = false;
  },
  [types.CLEAR_NEWER_MESSAGES_FLAG](_state, conversationId) {
    const chat = findConversation(_state, conversationId);
    if (!chat) return;
    chat.hasNewerMessages = false;
  },
  [types.SET_ALL_ATTACHMENTS](_state, { id, data, meta }) {
    _state.attachments[id] = [...data];
    if (meta) {
      _state.attachmentsMeta[id] = {
        currentPage: meta.current_page || 1,
        totalPages: meta.total_pages || 1,
        totalCount: meta.total_count || data.length,
      };
    }
  },
  [types.APPEND_ATTACHMENTS](_state, { id, data, meta }) {
    const existing = _state.attachments[id] || [];
    const existingIds = new Set(existing.map(a => a.id));
    const newAttachments = data.filter(a => !existingIds.has(a.id));
    _state.attachments[id] = [...existing, ...newAttachments];
    if (meta) {
      _state.attachmentsMeta[id] = {
        currentPage: meta.current_page || 1,
        totalPages: meta.total_pages || 1,
        totalCount: meta.total_count || _state.attachments[id].length,
      };
    }
  },
  [types.SET_MISSING_MESSAGES](_state, { id, data }) {
    const chat = findConversation(_state, id);
    if (!chat) return;
    chat.messages = data;
  },

  [types.SET_CHAT_DATA_FETCHED](_state, conversationId) {
    const chat = findConversation(_state, conversationId);
    if (chat) {
      chat.dataFetched = true;
    }
  },

  [types.SET_CURRENT_CHAT_WINDOW](_state, activeChat) {
    if (activeChat) {
      _state.selectedChatId = activeChat.id;
    }
  },

  [types.ASSIGN_AGENT](_state, { conversationId, assignee }) {
    const chat = findConversation(_state, conversationId);
    if (!chat) return;
    chat.meta.assignee = assignee;
  },

  [types.ASSIGN_TEAM](_state, { team, conversationId }) {
    const chat = findConversation(_state, conversationId);
    if (!chat) return;
    const updated = { ...chat, meta: { ...chat.meta, team } };
    const index = _state.allConversations.indexOf(chat);
    if (index !== -1) _state.allConversations.splice(index, 1, updated);
    if (_state.conversationMap) _state.conversationMap[updated.id] = updated;
  },

  [types.UPDATE_CONVERSATION_LAST_ACTIVITY](
    _state,
    { lastActivityAt, conversationId }
  ) {
    const chat = findConversation(_state, conversationId);
    if (!chat) return;
    chat.last_activity_at = lastActivityAt;
  },
  [types.ASSIGN_PRIORITY](_state, { priority, conversationId }) {
    const chat = findConversation(_state, conversationId);
    if (!chat) return;
    const updated = { ...chat, priority };
    const index = _state.allConversations.indexOf(chat);
    if (index !== -1) _state.allConversations.splice(index, 1, updated);
    if (_state.conversationMap) _state.conversationMap[updated.id] = updated;
  },

  [types.UPDATE_CONVERSATION_CUSTOM_ATTRIBUTES](
    _state,
    { conversationId, customAttributes }
  ) {
    const conversation = findConversation(_state, conversationId);
    if (!conversation) return;
    conversation.custom_attributes = {
      ...conversation.custom_attributes,
      ...customAttributes,
    };
  },

  [types.CHANGE_CONVERSATION_STATUS](
    _state,
    { conversationId, status, snoozedUntil }
  ) {
    const conversation = findConversation(_state, conversationId);
    if (!conversation) return;
    const updated = { ...conversation, status, snoozed_until: snoozedUntil };
    const index = _state.allConversations.indexOf(conversation);
    if (index !== -1) _state.allConversations.splice(index, 1, updated);
    if (_state.conversationMap) _state.conversationMap[updated.id] = updated;
  },

  [types.MUTE_CONVERSATION](_state) {
    const [chat] = getSelectedChatConversation(_state);
    if (!chat) return;
    chat.muted = true;
  },

  [types.UNMUTE_CONVERSATION](_state) {
    const [chat] = getSelectedChatConversation(_state);
    if (!chat) return;
    chat.muted = false;
  },

  [types.ADD_CONVERSATION_ATTACHMENTS](_state, message) {
    // early return if the message has not been sent, or has no attachments
    if (
      message.status !== MESSAGE_STATUS.SENT ||
      !message.attachments?.length
    ) {
      return;
    }

    const id = message.conversation_id;
    const existingAttachments = _state.attachments[id] || [];

    const attachmentsToAdd = message.attachments.filter(attachment => {
      // if the attachment is not already in the store, add it
      // this is to prevent duplicates
      return !existingAttachments.some(
        existingAttachment => existingAttachment.id === attachment.id
      );
    });

    // replace the attachments in the store
    _state.attachments[id] = [...existingAttachments, ...attachmentsToAdd];
  },

  [types.DELETE_CONVERSATION_ATTACHMENTS](_state, message) {
    if (message.status !== MESSAGE_STATUS.SENT) return;

    const { conversation_id: id } = message;
    const existingAttachments = _state.attachments[id] || [];
    if (!existingAttachments.length) return;

    _state.attachments[id] = existingAttachments.filter(attachment => {
      return attachment.message_id !== message.id;
    });
  },

  [types.ADD_MESSAGE](_state, message) {
    const { conversation_id: conversationId } = message;
    const chat = findConversation(_state, conversationId);
    if (!chat) return;

    const pendingMessageIndex = findPendingMessageIndex(chat, message);
    if (pendingMessageIndex !== -1) {
      chat.messages[pendingMessageIndex] = message;
    } else if (chat.hasNewerMessages) {
      // User is browsing old history — don't inject new messages into the window.
      // Just update metadata so the UI can show a "new messages" indicator.
      chat.pendingNewMessageCount = (chat.pendingNewMessageCount || 0) + 1;
      chat.timestamp = message.created_at;
      const { conversation: { unread_count: unreadCount = 0 } = {} } = message;
      chat.unread_count = unreadCount;
    } else {
      // Defensive: preserve ascending chronological order even if a caller emits an
      // out-of-order message (e.g. WAHA status sync re-emitting old messages over WS).
      // Invariant documented in docs/adr/0002-chat-messages-invariants.md.
      insertSortedByCreatedAt(chat.messages, message);
      trimOldest(chat);
      chat.timestamp = message.created_at;
      const { conversation: { unread_count: unreadCount = 0 } = {} } = message;
      chat.unread_count = unreadCount;
      if (_state.selectedChatId === conversationId) {
        emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE);
      }
    }
  },

  // D6 — remove a bolha PROGRESS de uma mensagem pendente que falhou com o
  // gate `assignment_required`, sem deixar bolha FAILED no thread. NÃO é um
  // delete persistido (DELETE_MESSAGE fica reservado para isso): só limpa o
  // pendente local antes do dialog de assunção reabrir.
  [types.REMOVE_PENDING_MESSAGE](_state, message) {
    const chat = findConversation(_state, message.conversation_id);
    if (!chat) return;
    chat.messages = chat.messages.filter(m => m.id !== message.id);
  },

  [types.ADD_CONVERSATION](_state, conversation) {
    const exists = findConversation(_state, conversation.id);
    if (!exists) {
      _state.allConversations.push(conversation);
      if (_state.conversationMap) {
        _state.conversationMap[conversation.id] = conversation;
      }
    }
  },

  [types.DELETE_CONVERSATION](_state, conversationId) {
    _state.allConversations = _state.allConversations.filter(
      c => c.id !== conversationId
    );
    if (_state.conversationMap) {
      delete _state.conversationMap[conversationId];
    }
    if (_state.attachments) delete _state.attachments[conversationId];
    if (_state.syncConversationsMessages) {
      delete _state.syncConversationsMessages[conversationId];
    }
  },

  [types.UPDATE_CONVERSATION](_state, conversation) {
    const { allConversations } = _state;
    const existingChat = findConversation(_state, conversation.id);

    if (existingChat) {
      // ignore out of order events
      if (conversation.updated_at < existingChat.updated_at) {
        return;
      }

      const index = allConversations.indexOf(existingChat);
      const { messages, ...updates } = conversation;
      const updated = { ...existingChat, ...updates };
      allConversations[index] = updated;
      if (_state.conversationMap) {
        _state.conversationMap[conversation.id] = updated;
      }
      if (_state.selectedChatId === conversation.id) {
        emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE);
      }
    } else {
      _state.allConversations.push(conversation);
      if (_state.conversationMap) {
        _state.conversationMap[conversation.id] = conversation;
      }
    }
  },

  [types.SET_LIST_LOADING_STATUS](_state) {
    _state.listLoadingStatus = true;
  },

  [types.CLEAR_LIST_LOADING_STATUS](_state) {
    _state.listLoadingStatus = false;
  },

  [types.UPDATE_MESSAGE_UNREAD_COUNT](
    _state,
    { id, lastSeen, unreadCount = 0 }
  ) {
    const chat = findConversation(_state, id);
    if (!chat) return;
    chat.agent_last_seen_at = lastSeen;
    chat.unread_count = unreadCount;
  },
  [types.CHANGE_CHAT_STATUS_FILTER](_state, data) {
    _state.chatStatusFilter = data;
  },

  [types.CHANGE_CHAT_SORT_FILTER](_state, data) {
    _state.chatSortFilter = data;
  },

  // Update assignee on action cable message
  [types.UPDATE_ASSIGNEE](_state, payload) {
    const chat = findConversation(_state, payload.id);
    if (!chat) return;
    chat.meta.assignee = payload.assignee;
  },

  [types.UPDATE_CONVERSATION_CONTACT](_state, { conversationId, ...payload }) {
    const chat = findConversation(_state, conversationId);
    if (!chat) return;
    chat.meta.sender = payload;
  },

  [types.UPDATE_CONVERSATION_CALL_STATUS](
    _state,
    { conversationId, callStatus }
  ) {
    const chat = findConversation(_state, conversationId);
    if (!chat) return;

    chat.additional_attributes = {
      ...chat.additional_attributes,
      call_status: callStatus,
    };
  },

  [types.UPDATE_MESSAGE_CALL_STATUS](_state, { conversationId, callStatus }) {
    const chat = findConversation(_state, conversationId);
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

  [types.SET_ACTIVE_INBOX](_state, inboxId) {
    _state.currentInbox = inboxId ? parseInt(inboxId, 10) : null;
  },

  [types.SET_CONVERSATION_CAN_REPLY](_state, { conversationId, canReply }) {
    const chat = findConversation(_state, conversationId);
    if (!chat) return;
    chat.can_reply = canReply;
  },

  [types.CLEAR_CONTACT_CONVERSATIONS](_state, contactId) {
    const chats = _state.allConversations.filter(
      c => c.meta.sender.id !== contactId
    );
    _state.allConversations = chats;
    if (_state.conversationMap) {
      rebuildConversationMap(_state);
    }
  },

  [types.SET_CONVERSATION_FILTERS](_state, data) {
    _state.appliedFilters = data;
  },

  [types.CLEAR_CONVERSATION_FILTERS](_state) {
    _state.appliedFilters = [];
  },

  [types.SET_LAST_MESSAGE_ID_IN_SYNC_CONVERSATION](
    _state,
    { conversationId, messageId }
  ) {
    _state.syncConversationsMessages[conversationId] = messageId;
  },

  [types.SET_CONTEXT_MENU_CHAT_ID](_state, chatId) {
    _state.contextMenuChatId = chatId;
  },

  [types.SET_CHAT_LIST_FILTERS](_state, data) {
    _state.conversationFilters = data;
  },
  [types.UPDATE_CHAT_LIST_FILTERS](_state, data) {
    _state.conversationFilters = { ..._state.conversationFilters, ...data };
  },
  [types.SET_INBOX_CAPTAIN_ASSISTANT](_state, data) {
    _state.copilotAssistant = data.assistant;
  },
};

export default {
  state,
  getters,
  actions,
  mutations,
};
