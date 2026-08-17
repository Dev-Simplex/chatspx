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
import { useImpersonation } from 'dashboard/composables/useImpersonation';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const { isImpersonating } = useImpersonation();
const UNREAD_COUNTS_REFETCH_THROTTLE_MS = 5000;
const FILTERED_UNREAD_COUNTS_REFRESH_RETRY_MS = 30000;
const FILTERED_UNREAD_COUNTS_REFRESH_RETRY_JITTER_MS = 15000;
const MENTION_UNREAD_COUNTS_REFETCH_DELAY_MS =
  UNREAD_COUNTS_REFETCH_THROTTLE_MS;
const getFilteredUnreadCountsRefreshRetryDelay = () =>
  FILTERED_UNREAD_COUNTS_REFRESH_RETRY_MS +
  Math.random() * FILTERED_UNREAD_COUNTS_REFRESH_RETRY_JITTER_MS;

class ActionCableConnector extends BaseActionCableConnector {
  constructor(app, pubsubToken) {
    const { websocketURL = '' } = window.chatwootConfig || {};
    super(app, pubsubToken, websocketURL);
    this.CancelTyping = {};
    this.lastUnreadCountsFetchAt = null;
    this.unreadCountsFetchTimer = null;
    this.mentionUnreadCountsFetchTimer = null;
    this.mentionUnreadCountsRetryTimer = null;
    this.filteredUnreadCountsRetryTimer = null;
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
      'conversation.unread_count_changed':
        this.onConversationUnreadCountChanged,
      'account.cache_invalidated': this.onCacheInvalidate,
      'account.enrichment_completed': this.onEnrichmentCompleted,
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

  // D1 (Fase 3): pedido de atendimento criado/respondido. Um evento, dois papéis
  // (dono refaz a lista; solicitante recebe o aviso de resposta) — a lógica mora
  // na action p/ ficar testável e fora do connector.
  onTakeoverRequestChanged = data => {
    this.app.$store.dispatch('takeoverRequests/handleRealtimeEvent', data);
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

  onConversationUnreadCountChanged = () => {
    this.refreshConversationUnreadCountsWithFilteredRetry();
  };

  refreshConversationUnreadCountsWithFilteredRetry = () => {
    this.throttledFetchConversationUnreadCounts();
    this.scheduleFilteredUnreadCountsRetry();
  };

  throttledFetchConversationUnreadCounts = () => {
    const now = Date.now();
    const elapsedTime = now - this.lastUnreadCountsFetchAt;

    if (
      this.lastUnreadCountsFetchAt === null ||
      elapsedTime >= UNREAD_COUNTS_REFETCH_THROTTLE_MS
    ) {
      this.clearUnreadCountsFetchTimer();
      this.fetchConversationUnreadCounts();
      return;
    }

    if (this.unreadCountsFetchTimer) return;

    this.unreadCountsFetchTimer = setTimeout(() => {
      this.unreadCountsFetchTimer = null;
      this.fetchConversationUnreadCounts();
    }, UNREAD_COUNTS_REFETCH_THROTTLE_MS - elapsedTime);
  };

  clearUnreadCountsFetchTimer = () => {
    if (!this.unreadCountsFetchTimer) return;

    clearTimeout(this.unreadCountsFetchTimer);
    this.unreadCountsFetchTimer = null;
  };

  scheduleMentionUnreadCountsFetch = () => {
    if (!this.isFilteredUnreadCountsEnabled()) return;

    // Mention invalidation runs through the async dispatcher, and stale snapshots
    // can be served until the filtered-count backend refresh window opens.
    this.scheduleUnreadCountsFetchAfter(
      'mentionUnreadCountsFetchTimer',
      MENTION_UNREAD_COUNTS_REFETCH_DELAY_MS
    );
    this.scheduleUnreadCountsFetchAfter(
      'mentionUnreadCountsRetryTimer',
      getFilteredUnreadCountsRefreshRetryDelay(),
      { reset: true }
    );
  };

  scheduleFilteredUnreadCountsRetry = () => {
    if (!this.isFilteredUnreadCountsEnabled()) return;

    // Filtered snapshots can intentionally stay stale until the backend
    // refresh window opens.
    this.scheduleUnreadCountsFetchAfter(
      'filteredUnreadCountsRetryTimer',
      getFilteredUnreadCountsRefreshRetryDelay(),
      { reset: true }
    );
  };

  scheduleUnreadCountsFetchAfter = (
    timerName,
    delay,
    { reset = false } = {}
  ) => {
    if (this[timerName]) {
      if (!reset) return;

      clearTimeout(this[timerName]);
    }

    this[timerName] = setTimeout(() => {
      this[timerName] = null;
      this.throttledFetchConversationUnreadCounts();
    }, delay);
  };

  fetchConversationUnreadCounts = () => {
    if (!this.isConversationUnreadCountsEnabled()) return;

    this.lastUnreadCountsFetchAt = Date.now();
    this.app.$store.dispatch('conversationUnreadCounts/get');
  };

  isConversationUnreadCountsEnabled = () => {
    const accountId = this.app.$store.getters.getCurrentAccountId;
    const isFeatureEnabled =
      this.app.$store.getters['accounts/isFeatureEnabledonAccount'];

    return isFeatureEnabled?.(
      accountId,
      FEATURE_FLAGS.CONVERSATION_UNREAD_COUNTS
    );
  };

  isFilteredUnreadCountsEnabled = () => {
    const accountId = this.app.$store.getters.getCurrentAccountId;
    const isFeatureEnabled =
      this.app.$store.getters['accounts/isFeatureEnabledonAccount'];

    return (
      isFeatureEnabled?.(accountId, FEATURE_FLAGS.CONVERSATION_UNREAD_COUNTS) &&
      isFeatureEnabled?.(accountId, FEATURE_FLAGS.UNREAD_COUNT_FOR_FILTERS)
    );
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
    this.scheduleMentionUnreadCountsFetch();
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

  onEnrichmentCompleted = () => {
    this.app.$store.dispatch('accounts/get', { silent: true });
  };

  onCacheInvalidate = data => {
    const keys = data.cache_keys;
    this.app.$store.dispatch('labels/revalidate', { newKey: keys.label });
    this.app.$store.dispatch('inboxes/revalidate', { newKey: keys.inbox });
    this.app.$store.dispatch('teams/revalidate', { newKey: keys.team });

    if (this.isFilteredUnreadCountsEnabled()) {
      // Inbox/team/label visibility changes can change the accessible set used
      // by filtered unread counts even when no conversation row changes.
      this.refreshConversationUnreadCountsWithFilteredRetry();
    }
  };

}

export default {
  init(store, pubsubToken) {
    return new ActionCableConnector({ $store: store }, pubsubToken);
  },
};
