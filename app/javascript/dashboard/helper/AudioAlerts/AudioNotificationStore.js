import {
  ROLES,
  CONVERSATION_PERMISSIONS,
} from 'dashboard/constants/permissions';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper';
import wootConstants from 'dashboard/constants/globals';

class AudioNotificationStore {
  constructor(store) {
    this.store = store;
  }

  hasUnreadConversation = () => {
    const currentUserId = this.store.getters.getCurrentUser?.id;
    const allConversations =
      this.store.state.conversations?.allConversations || [];

    return allConversations.some(conv => {
      const isAssignedToMe = conv.meta?.assignee?.id === currentUserId;
      const isOpen = conv.status === 'open';
      return isAssignedToMe && isOpen && conv.unread_count > 0;
    });
  };

  isMessageFromPendingConversation = (message = {}) => {
    const { conversation_id: conversationId } = message || {};
    if (!conversationId) return false;

    const activeConversation =
      this.store.getters.getConversationById(conversationId);
    return activeConversation?.status === wootConstants.STATUS_TYPE.PENDING;
  };

  isMessageFromCurrentConversation = message => {
    return this.store.getters.getSelectedChat?.id === message.conversation_id;
  };

  hasConversationPermission = user => {
    const currentAccountId = this.store.getters.getCurrentAccountId;
    // Get the user permissions for the current account
    const userPermissions = getUserPermissions(user, currentAccountId);
    // Check if the user has the required permissions
    const hasRequiredPermission = [...ROLES, ...CONVERSATION_PERMISSIONS].some(
      permission => userPermissions.includes(permission)
    );
    return hasRequiredPermission;
  };
}

export default AudioNotificationStore;
