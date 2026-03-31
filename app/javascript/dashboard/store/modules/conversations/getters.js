import { MESSAGE_TYPE } from 'shared/constants/messages';
import { applyPageFilters, applyRoleFilter, sortComparator } from './helpers';
import filterQueryGenerator from 'dashboard/helper/filterQueryGenerator';
import { matchesFilters } from './helpers/filterHelpers';
import {
  getUserPermissions,
  getUserRole,
} from '../../../helper/permissionsHelper';
import camelcaseKeys from 'camelcase-keys';

export const getSelectedChatConversation = ({
  conversationMap,
  allConversations,
  selectedChatId,
}) => {
  if (conversationMap) {
    const chat = conversationMap[selectedChatId];
    return chat ? [chat] : [];
  }
  // Fallback for cases where conversationMap is not available (e.g., tests)
  const chat = allConversations.find(
    conversation => conversation.id === selectedChatId
  );
  return chat ? [chat] : [];
};

const getters = {
  getAllConversations: ({ allConversations, chatSortFilter: sortKey }) => {
    return [...allConversations].sort((a, b) => sortComparator(a, b, sortKey));
  },
  getFilteredConversations: (
    { allConversations, chatSortFilter, appliedFilters },
    _,
    __,
    rootGetters
  ) => {
    const currentUser = rootGetters.getCurrentUser;
    const currentUserId = rootGetters.getCurrentUser.id;
    const currentAccountId = rootGetters.getCurrentAccountId;

    const permissions = getUserPermissions(currentUser, currentAccountId);
    const userRole = getUserRole(currentUser, currentAccountId);

    return allConversations
      .filter(conversation => {
        const matchesFilterResult = matchesFilters(
          conversation,
          appliedFilters
        );
        const allowedForRole = applyRoleFilter(
          conversation,
          userRole,
          permissions,
          currentUserId
        );

        return matchesFilterResult && allowedForRole;
      })
      .sort((a, b) => sortComparator(a, b, chatSortFilter));
  },
  getSelectedChat: ({ selectedChatId, conversationMap, allConversations }) => {
    if (conversationMap) {
      return conversationMap[selectedChatId] || {};
    }
    const selectedChat = allConversations.find(
      conversation => conversation.id === selectedChatId
    );
    return selectedChat || {};
  },
  getSelectedChatAttachments: ({ selectedChatId, attachments }) => {
    return attachments[selectedChatId] || [];
  },
  getChatListFilters: ({ conversationFilters }) => conversationFilters,
  getLastEmailInSelectedChat: (stage, _getters) => {
    const selectedChat = _getters.getSelectedChat;
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
  getMineChats: (_state, _, __, rootGetters) => {
    const currentUserID = rootGetters.getCurrentUser?.id;
    const filters = _state.conversationFilters;

    return _state.allConversations
      .filter(conversation => {
        const { assignee } = conversation.meta;
        const isAssignedToMe = assignee && assignee.id === currentUserID;
        const shouldFilter = applyPageFilters(conversation, filters);
        return isAssignedToMe && shouldFilter;
      })
      .sort((a, b) => sortComparator(a, b, _state.chatSortFilter));
  },
  getAppliedConversationFiltersV2: _state => {
    // TODO: Replace existing one with V2 after migrating the filters to use camelcase
    return _state.appliedFilters.map(camelcaseKeys);
  },
  getAppliedConversationFilters: _state => {
    return _state.appliedFilters;
  },
  getAppliedConversationFiltersQuery: _state => {
    const hasAppliedFilters = _state.appliedFilters.length !== 0;
    return hasAppliedFilters ? filterQueryGenerator(_state.appliedFilters) : [];
  },
  getUnAssignedChats: _state => {
    const filters = _state.conversationFilters;

    return _state.allConversations
      .filter(conversation => {
        const isUnAssigned = !conversation.meta.assignee;
        const shouldFilter = applyPageFilters(conversation, filters);
        return isUnAssigned && shouldFilter;
      })
      .sort((a, b) => sortComparator(a, b, _state.chatSortFilter));
  },
  getAllStatusChats: (_state, _, __, rootGetters) => {
    const currentUser = rootGetters.getCurrentUser;
    const currentUserId = rootGetters.getCurrentUser.id;
    const currentAccountId = rootGetters.getCurrentAccountId;

    const permissions = getUserPermissions(currentUser, currentAccountId);
    const userRole = getUserRole(currentUser, currentAccountId);
    const filters = _state.conversationFilters;

    return _state.allConversations
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
      .sort((a, b) => sortComparator(a, b, _state.chatSortFilter));
  },
  getChatListLoadingStatus: ({ listLoadingStatus }) => listLoadingStatus,
  getAllMessagesLoaded(_state) {
    const [chat] = getSelectedChatConversation(_state);
    return !chat || chat.allMessagesLoaded === undefined
      ? false
      : chat.allMessagesLoaded;
  },
  getUnreadCount(_state) {
    const [chat] = getSelectedChatConversation(_state);
    if (!chat) return [];
    return chat.messages.filter(
      chatMessage =>
        chatMessage.created_at * 1000 > chat.agent_last_seen_at * 1000 &&
        chatMessage.message_type === 0 &&
        chatMessage.private !== true
    ).length;
  },
  getChatStatusFilter: ({ chatStatusFilter }) => chatStatusFilter,
  getChatSortFilter: ({ chatSortFilter }) => chatSortFilter,
  getSelectedInbox: ({ currentInbox }) => currentInbox,
  getConversationById: _state => conversationId => {
    if (_state.conversationMap) {
      return _state.conversationMap[Number(conversationId)];
    }
    return _state.allConversations.find(
      value => value.id === Number(conversationId)
    );
  },
  getConversationParticipants: _state => {
    return _state.conversationParticipants;
  },
  getConversationLastSeen: _state => {
    return _state.conversationLastSeen;
  },

  getContextMenuChatId: _state => {
    return _state.contextMenuChatId;
  },

  getCopilotAssistant: _state => {
    return _state.copilotAssistant;
  },
};

export default getters;
