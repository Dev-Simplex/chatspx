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
  getSelectedChatAttachmentsMeta: ({ selectedChatId, attachmentsMeta }) => {
    return (
      attachmentsMeta[selectedChatId] || {
        currentPage: 1,
        totalPages: 1,
        totalCount: 0,
      }
    );
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
        // `assignee.type !== 'agent_bot'` fixes the User×AgentBot id collision
        // (a captain mirror bot sharing the user's id is NOT "mine")
        const isAssignedToMe =
          assignee &&
          assignee.type !== 'agent_bot' &&
          assignee.id === currentUserID;
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
  getUnAssignedChats: (_state, _getters, _rootState, rootGetters) => {
    const filters = _state.conversationFilters;
    const accountId = rootGetters.getCurrentAccountId;
    const gateEnabled = Boolean(
      rootGetters['accounts/getAccount'](accountId)?.settings
        ?.reply_assignment_gate
    );

    return _state.allConversations
      .filter(conversation => {
        const { assignee } = conversation.meta;
        // Critério exato do backend (conversation_finder unassigned_count):
        // `assignee_id IS NULL [AND ab.id IS NULL]` onde `ab` é restrito a
        // bot_type captain. Em termos do front: qualquer bot (captain OU webhook)
        // tem assignee_id null, logo NÃO é atendente humano. Um bot WEBHOOK
        // atribuído por coluna conta como não atribuído mesmo com a flag ON
        // (o LEFT JOIN só casa captain). Só o espelho captain sai da lista com
        // a flag ligada. Filtrar por `type === 'agent_bot'` cru faria count
        // (REST) e lista (websocket) divergirem nas abas IA e Não Atribuídas.
        const isBotAssignee = assignee?.type === 'agent_bot';
        const isCaptainMirror = isBotAssignee && Boolean(assignee.is_captain);
        const hasNoHumanAssignee = !assignee || isBotAssignee;
        // Gate ON: o espelho captain deixa de contar como não atribuído.
        const isUnAssigned =
          hasNoHumanAssignee && !(isCaptainMirror && gateEnabled);
        const shouldFilter = applyPageFilters(conversation, filters);
        return isUnAssigned && shouldFilter;
      })
      .sort((a, b) => sortComparator(a, b, _state.chatSortFilter));
  },
  getAIChats: _state => {
    const filters = _state.conversationFilters;

    return _state.allConversations
      .filter(conversation => {
        const { assignee } = conversation.meta;
        // Casa com o backend (bot_type captain): apenas espelhos captain contam
        // como IA. Bots webhook emitem type 'agent_bot' mas não são atendentes IA.
        const isAIAssigned =
          assignee?.type === 'agent_bot' && Boolean(assignee.is_captain);
        const shouldFilter = applyPageFilters(conversation, filters);
        return isAIAssigned && shouldFilter;
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
  getHasNewerMessages(_state) {
    const [chat] = getSelectedChatConversation(_state);
    return chat ? !!chat.hasNewerMessages : false;
  },
  getPendingNewMessageCount(_state) {
    const [chat] = getSelectedChatConversation(_state);
    return chat ? chat.pendingNewMessageCount || 0 : 0;
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
