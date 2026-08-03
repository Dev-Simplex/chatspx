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

// Espelha `may_clear_unread_marker?` do backend: numa conversa com dono humano,
// só o dono limpa o "não lida" — senão quem só passa o olho apaga o marcador de
// quem precisa responder. O backend já recusa a escrita; sem este guarda o front
// ainda zeraria o contador localmente (otimista) e mostraria como lida uma
// conversa que o servidor manteve não-lida.
//
// Sem dono — incluindo conversa em poder da IA, que não ocupa `assignee` humano
// — segue o comportamento padrão: quem abrir, leu.
// Conversa desconhecida no store não bloqueia: o backend é a autoridade.
const canClearUnreadMarker = (rootGetters, conversationId) => {
  const conversation = rootGetters?.getConversationById?.(conversationId);
  const assignee = conversation?.meta?.assignee;
  // Sem dono humano — inclusive quando quem está no controle é a IA — NINGUÉM limpa
  // o "não lida" só de abrir. O marcador é o sinal do que falta atender, e some com
  // um clique de quem passou o olho. Fica não-lida até alguém assumir (ou marcar
  // explicitamente). Espelha `may_clear_unread_marker?` do backend.
  if (!assignee?.id || assignee.type === 'agent_bot') return false;
  return Number(assignee.id) === Number(rootGetters?.getCurrentUserID);
};

export default {
  // `explicit: true` só vem do botão "marcar como lida". Abrir a conversa nunca manda.
  markMessagesRead: async ({ commit, dispatch, rootGetters }, data) => {
    const explicit = data.explicit === true;
    if (!explicit && !canClearUnreadMarker(rootGetters, data.id)) return;

    try {
      const {
        data: { id, agent_last_seen_at: lastSeen },
      } = await ConversationApi.markMessageRead({ id: data.id, explicit });
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
