import AudioNotificationStore from '../AudioNotificationStore';
import {
  ROLES,
  CONVERSATION_PERMISSIONS,
} from 'dashboard/constants/permissions';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper';
import wootConstants from 'dashboard/constants/globals';

vi.mock('dashboard/helper/permissionsHelper', () => ({
  getUserPermissions: vi.fn(),
}));

describe('AudioNotificationStore', () => {
  let store;
  let audioNotificationStore;

  beforeEach(() => {
    store = {
      getters: {
        getCurrentUser: { id: 1 },
        getSelectedChat: null,
        getCurrentAccountId: 1,
        getConversationById: vi.fn(),
      },
      state: {
        conversations: {
          allConversations: [],
        },
      },
    };
    audioNotificationStore = new AudioNotificationStore(store);
  });

  describe('hasUnreadConversation', () => {
    it('should return true when there are unread conversations', () => {
      store.state.conversations.allConversations = [
        {
          id: 1,
          status: 'open',
          unread_count: 2,
          meta: { assignee: { id: 1 } },
        },
        {
          id: 2,
          status: 'open',
          unread_count: 0,
          meta: { assignee: { id: 1 } },
        },
      ];

      expect(audioNotificationStore.hasUnreadConversation()).toBe(true);
    });

    it('should return false when there are no unread conversations', () => {
      store.state.conversations.allConversations = [
        {
          id: 1,
          status: 'open',
          unread_count: 0,
          meta: { assignee: { id: 1 } },
        },
        {
          id: 2,
          status: 'open',
          unread_count: 0,
          meta: { assignee: { id: 1 } },
        },
      ];

      expect(audioNotificationStore.hasUnreadConversation()).toBe(false);
    });

    it('should return false when there are no conversations', () => {
      store.state.conversations.allConversations = [];

      expect(audioNotificationStore.hasUnreadConversation()).toBe(false);
    });

    it('should only match open conversations assigned to current user', () => {
      store.state.conversations.allConversations = [
        {
          id: 1,
          status: 'resolved',
          unread_count: 5,
          meta: { assignee: { id: 1 } },
        },
        {
          id: 2,
          status: 'open',
          unread_count: 3,
          meta: { assignee: { id: 2 } },
        },
      ];

      expect(audioNotificationStore.hasUnreadConversation()).toBe(false);
    });
  });

  describe('isMessageFromPendingConversation', () => {
    it('should return true when conversation status is pending', () => {
      store.getters.getConversationById.mockReturnValue({
        id: 123,
        status: wootConstants.STATUS_TYPE.PENDING,
      });
      const message = { conversation_id: 123 };

      expect(
        audioNotificationStore.isMessageFromPendingConversation(message)
      ).toBe(true);
      expect(store.getters.getConversationById).toHaveBeenCalledWith(123);
    });

    it('should return false when conversation status is not pending', () => {
      store.getters.getConversationById.mockReturnValue({
        id: 123,
        status: wootConstants.STATUS_TYPE.OPEN,
      });
      const message = { conversation_id: 123 };

      expect(
        audioNotificationStore.isMessageFromPendingConversation(message)
      ).toBe(false);
      expect(store.getters.getConversationById).toHaveBeenCalledWith(123);
    });

    it('should return false when conversation is not found', () => {
      store.getters.getConversationById.mockReturnValue(null);
      const message = { conversation_id: 123 };

      expect(
        audioNotificationStore.isMessageFromPendingConversation(message)
      ).toBe(false);
      expect(store.getters.getConversationById).toHaveBeenCalledWith(123);
    });

    it('should return false when message has no conversation_id', () => {
      const message = {};

      expect(
        audioNotificationStore.isMessageFromPendingConversation(message)
      ).toBe(false);
      expect(store.getters.getConversationById).not.toHaveBeenCalled();
    });

    it('should return false when message is null or undefined', () => {
      expect(
        audioNotificationStore.isMessageFromPendingConversation(null)
      ).toBe(false);
      expect(
        audioNotificationStore.isMessageFromPendingConversation(undefined)
      ).toBe(false);
      expect(store.getters.getConversationById).not.toHaveBeenCalled();
    });
  });

  describe('isMessageFromCurrentConversation', () => {
    it('should return true when message is from selected chat', () => {
      store.getters.getSelectedChat = { id: 6179 };
      const message = { conversation_id: 6179 };

      expect(
        audioNotificationStore.isMessageFromCurrentConversation(message)
      ).toBe(true);
    });

    it('should return false when message is from different chat', () => {
      store.getters.getSelectedChat = { id: 6179 };
      const message = { conversation_id: 1337 };

      expect(
        audioNotificationStore.isMessageFromCurrentConversation(message)
      ).toBe(false);
    });

    it('should return false when no chat is selected', () => {
      store.getters.getSelectedChat = null;
      const message = { conversation_id: 6179 };

      expect(
        audioNotificationStore.isMessageFromCurrentConversation(message)
      ).toBe(false);
    });
  });

  describe('hasConversationPermission', () => {
    const mockUser = { id: 'user123' };

    beforeEach(() => {
      getUserPermissions.mockReset();
    });

    it('should return true when user has a required role', () => {
      getUserPermissions.mockReturnValue([ROLES[0]]);

      expect(audioNotificationStore.hasConversationPermission(mockUser)).toBe(
        true
      );
      expect(getUserPermissions).toHaveBeenCalledWith(mockUser, 1);
    });

    it('should return true when user has a conversation permission', () => {
      getUserPermissions.mockReturnValue([CONVERSATION_PERMISSIONS[0]]);

      expect(audioNotificationStore.hasConversationPermission(mockUser)).toBe(
        true
      );
    });

    it('should return false when user has no required permissions', () => {
      getUserPermissions.mockReturnValue(['some-other-permission']);

      expect(audioNotificationStore.hasConversationPermission(mockUser)).toBe(
        false
      );
    });

    it('should return false when user has no permissions', () => {
      getUserPermissions.mockReturnValue([]);

      expect(audioNotificationStore.hasConversationPermission(mockUser)).toBe(
        false
      );
    });
  });
});
