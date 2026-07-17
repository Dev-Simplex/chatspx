import AuthAPI from '../api/auth';
import BaseActionCableConnector from '../../shared/helpers/BaseActionCableConnector';
import {
  fetchVersion,
  forceCleanReload,
  getInitialVersion,
} from '../helper/autoUpdateHelper';
import DashboardAudioNotificationHelper from './AudioAlerts/DashboardAudioNotificationHelper';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import SessionStorage from 'shared/helpers/sessionStorage';
import { SESSION_STORAGE_KEYS } from 'dashboard/constants/sessionStorage';

const isImpersonating = () =>
  !!SessionStorage.get(SESSION_STORAGE_KEYS.IMPERSONATION_USER);

class ActionCableConnector extends BaseActionCableConnector {
  constructor(app, pubsubToken) {
    const { websocketURL = '' } = window.chatwootConfig || {};
    super(app, pubsubToken, websocketURL);
    this.CancelTyping = {};
    this.events = {
      'message.created': this.onMessageCreated,
      'message.updated': this.onMessageUpdated,
      'conversation.created': this.onConversationCreated,
      'conversation.status_changed': this.onStatusChange,
      'user:logout': this.onLogout,
      'page:reload': this.onReload,
      'assignee.changed': this.onAssigneeChanged,
      'conversation.typing_on': this.onTypingOn,
      'conversation.typing_off': this.onTypingOff,
      'conversation.contact_changed': this.onConversationContactChange,
      'presence.update': this.onPresenceUpdate,
      'contact.deleted': this.onContactDelete,
      'contact.updated': this.onContactUpdate,
      'conversation.mentioned': this.onConversationMentioned,
      'notification.created': this.onNotificationCreated,
      'notification.deleted': this.onNotificationDeleted,
      'notification.updated': this.onNotificationUpdated,
      'conversation.read': this.onConversationRead,
      'conversation.updated': this.onConversationUpdated,
      'account.cache_invalidated': this.onCacheInvalidate,
      'copilot.message.created': this.onCopilotMessageCreated,
      'funnel_item.moved': this.onFunnelItemMoved,
      'takeover_request.created': this.onTakeoverRequestChanged,
      'takeover_request.updated': this.onTakeoverRequestChanged,
      'internal.message.created': this.onInternalMessageCreated,
      'internal.message.updated': this.onInternalMessageUpdated,
      'internal.mention.created': this.onInternalMentionCreated,
      'internal.typing': this.onInternalTyping,
      'internal.read': this.onInternalRead,
      'internal.channel.updated': this.onInternalChannelUpdated,
    };
  }

  // Kanban v2 (Fase 4): another user moved a card to a different stage — relocate
  // it live. Best-effort; the store action no-ops if the item isn't loaded.
  onFunnelItemMoved = data => {
    this.app.$store.dispatch('kanban/applyRemoteMove', data);
  };

  // D1 (Fase 3): pedido de atendimento criado/respondido. O payload do broadcast
  // é mínimo (dado dirigido entre 2 pessoas), então em vez de mesclar um registro
  // parcial, refazemos o fetch da lista — barato (só os MEUS pendentes) e robusto.
  onTakeoverRequestChanged = () => {
    this.app.$store.dispatch('takeoverRequests/fetchIncoming');
  };

  // Chat interno (Módulo B): a peer posted into one of my internal channels.
  onInternalMessageCreated = data => {
    this.app.$store.dispatch('internalChat/applyIncomingMessage', data);
  };

  // Chat interno (v2 Fase 2): a message was edited / deleted / reacted-to.
  onInternalMessageUpdated = data => {
    this.app.$store.dispatch('internalChat/applyUpdatedMessage', data);
  };

  // Chat interno (v2 Fase 2B): peer is typing / read up to a point.
  onInternalTyping = data => {
    this.app.$store.dispatch('internalChat/applyTyping', data);
  };

  onInternalRead = data => {
    this.app.$store.dispatch('internalChat/applyRead', data);
  };

  // Chat interno (v2 Fase 5): a channel's name/membership changed.
  onInternalChannelUpdated = () => {
    this.app.$store.dispatch('internalChat/applyChannelUpdated');
  };

  // Chat interno (B2): I was @mentioned. The toast (localized) is fired by the
  // always-mounted Sidebar watching this store state — keeps i18n out of the
  // connector and avoids touching the global notification bell.
  onInternalMentionCreated = data => {
    this.app.$store.dispatch('internalChat/applyIncomingMention', data);
  };

  // eslint-disable-next-line class-methods-use-this
  onReconnect = async () => {
    emitter.emit(BUS_EVENTS.WEBSOCKET_RECONNECT);
    const initialVersion = getInitialVersion();
    if (initialVersion) {
      const newVersion = await fetchVersion();
      if (newVersion && newVersion !== initialVersion) {
        forceCleanReload();
      }
    }
  };

  // eslint-disable-next-line class-methods-use-this
  onDisconnected = () => {
    emitter.emit(BUS_EVENTS.WEBSOCKET_DISCONNECT);
  };

  isAValidEvent = data => {
    return this.app.$store.getters.getCurrentAccountId === data.account_id;
  };

  onMessageUpdated = data => {
    this.app.$store.dispatch('updateMessage', data);
  };

  // Three separate dispatches are required here: contacts and agents live in
  // different Vuex modules and setCurrentUserAvailability updates the root state.
  // Vuex does not support batching commits across modules in a single dispatch.
  onPresenceUpdate = data => {
    if (isImpersonating()) return;
    this.app.$store.dispatch('contacts/updatePresence', data.contacts);
    this.app.$store.dispatch('agents/updatePresence', data.users);
    this.app.$store.dispatch('setCurrentUserAvailability', data.users);
  };

  onConversationContactChange = payload => {
    const { meta = {}, id: conversationId } = payload;
    const { sender } = meta || {};
    if (conversationId) {
      this.app.$store.dispatch('updateConversationContact', {
        conversationId,
        ...sender,
      });
    }
  };

  onAssigneeChanged = payload => {
    const { id } = payload;
    if (id) {
      this.app.$store.dispatch('updateConversation', payload);
    }
    this.fetchConversationStats();
    this.app.$store.dispatch('kanban/syncConversationFromRealtime', payload);
  };

  onConversationCreated = data => {
    this.app.$store.dispatch('addConversation', data);
    this.fetchConversationStats();
  };

  onConversationRead = data => {
    this.app.$store.dispatch('updateConversation', data);
  };

  // eslint-disable-next-line class-methods-use-this
  onLogout = () => AuthAPI.logout();

  onMessageCreated = data => {
    const {
      conversation: { last_activity_at: lastActivityAt },
      conversation_id: conversationId,
    } = data;
    DashboardAudioNotificationHelper.onNewMessage(data);
    this.app.$store.dispatch('addMessage', data);
    // addMessage does not update last_activity_at on the conversation object;
    // a separate dispatch is needed to keep sort order in sync.
    this.app.$store.dispatch('updateConversationLastActivity', {
      lastActivityAt,
      conversationId,
    });
    this.app.$store.dispatch('kanban/syncConversationFromRealtime', data);
  };

  // eslint-disable-next-line class-methods-use-this
  onReload = () => window.location.reload();

  onStatusChange = data => {
    this.app.$store.dispatch('updateConversation', data);
    this.fetchConversationStats();
    this.app.$store.dispatch('kanban/syncConversationFromRealtime', data);
  };

  onConversationUpdated = data => {
    this.app.$store.dispatch('updateConversation', data);
    this.fetchConversationStats();
    this.app.$store.dispatch('kanban/syncConversationFromRealtime', data);
  };

  onTypingOn = ({ conversation, user }) => {
    const conversationId = conversation.id;

    this.clearTimer(conversationId);
    this.app.$store.dispatch('conversationTypingStatus/create', {
      conversationId,
      user,
    });
    this.initTimer({ conversation, user });
  };

  onTypingOff = ({ conversation, user }) => {
    const conversationId = conversation.id;

    this.clearTimer(conversationId);
    this.app.$store.dispatch('conversationTypingStatus/destroy', {
      conversationId,
      user,
    });
  };

  onConversationMentioned = data => {
    this.app.$store.dispatch('addMentions', data);
  };

  disconnect() {
    Object.keys(this.CancelTyping).forEach(conversationId => {
      clearTimeout(this.CancelTyping[conversationId]);
    });
    this.CancelTyping = {};
    super.disconnect();
  }

  clearTimer = conversationId => {
    const timerEvent = this.CancelTyping[conversationId];

    if (timerEvent) {
      clearTimeout(timerEvent);
      this.CancelTyping[conversationId] = null;
    }
  };

  initTimer = ({ conversation, user }) => {
    const conversationId = conversation.id;
    // Turn off typing automatically after 30 seconds
    this.CancelTyping[conversationId] = setTimeout(() => {
      this.onTypingOff({ conversation, user });
    }, 30000);
  };

  // The conversationStats store already has adaptive debouncing (500ms-10s)
  // and a META_FRESH_THRESHOLD_MS guard, so no extra debounce is needed here.
  // eslint-disable-next-line class-methods-use-this
  fetchConversationStats = () => {
    emitter.emit('fetch_conversation_stats');
  };

  onContactDelete = data => {
    this.app.$store.dispatch(
      'contacts/deleteContactThroughConversations',
      data.id
    );
    this.fetchConversationStats();
  };

  onContactUpdate = data => {
    this.app.$store.dispatch('contacts/updateContact', data);
  };

  onNotificationCreated = data => {
    this.app.$store.dispatch('notifications/addNotification', data);
  };

  onNotificationDeleted = data => {
    this.app.$store.dispatch('notifications/deleteNotification', data);
  };

  onNotificationUpdated = data => {
    this.app.$store.dispatch('notifications/updateNotification', data);
  };

  onCopilotMessageCreated = data => {
    this.app.$store.dispatch('copilotMessages/upsert', data);
  };

  onCacheInvalidate = data => {
    const keys = data.cache_keys;
    this.app.$store.dispatch('labels/revalidate', { newKey: keys.label });
    this.app.$store.dispatch('inboxes/revalidate', { newKey: keys.inbox });
    this.app.$store.dispatch('teams/revalidate', { newKey: keys.team });
  };
}

export default {
  init(store, pubsubToken) {
    return new ActionCableConnector({ $store: store }, pubsubToken);
  },
};
