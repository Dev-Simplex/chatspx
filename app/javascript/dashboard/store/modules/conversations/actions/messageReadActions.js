import { throwErrorMessage } from 'dashboard/store/utils/api';
import ConversationApi from '../../../../api/inbox/conversation';
import NotificationsAPI from '../../../../api/notifications';
import mutationTypes from '../../../mutation-types';

const clearMatchingNotification = async (
  { dispatch, rootGetters },
  conversationId
) => {
  const conversationIdNum = Number(conversationId);
  if (!conversationIdNum) return;

  const notifications = rootGetters['notifications/getNotifications'] || [];
  const match = notifications.find(
    n =>
      !n.read_at &&
      n.primary_actor_type === 'Conversation' &&
      Number(n.primary_actor_id) === conversationIdNum
  );

  if (match) {
    const unreadCount = rootGetters['notifications/getUnreadCount'] || 0;
    await dispatch(
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

  // Notifications list not loaded yet — talk to API directly and refresh count
  try {
    await NotificationsAPI.read('Conversation', conversationIdNum);
    await dispatch('notifications/unReadCount', undefined, { root: true });
  } catch (error) {
    // silent — auto-clear is best effort
  }
};

export default {
  markMessagesRead: async ({ commit, dispatch, rootGetters }, data) => {
    try {
      const {
        data: { id, agent_last_seen_at: lastSeen },
      } = await ConversationApi.markMessageRead(data);
      setTimeout(
        () =>
          commit(mutationTypes.UPDATE_MESSAGE_UNREAD_COUNT, { id, lastSeen }),
        4000
      );
      clearMatchingNotification({ dispatch, rootGetters }, data.id);
    } catch (error) {
      // Handle error
    }
  },

  markMessagesUnread: async ({ commit }, { id }) => {
    try {
      const {
        data: { agent_last_seen_at: lastSeen, unread_count: unreadCount },
      } = await ConversationApi.markMessagesUnread({ id });
      commit(mutationTypes.UPDATE_MESSAGE_UNREAD_COUNT, {
        id,
        lastSeen,
        unreadCount,
      });
    } catch (error) {
      throwErrorMessage(error);
    }
  },
};
