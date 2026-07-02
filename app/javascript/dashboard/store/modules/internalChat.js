import InternalChatAPI from '../../api/internalChat';

export const state = {
  channels: [],
  // Modo auditoria (admin): TODOS os canais da conta, lista separada da do usuário.
  auditChannels: [],
  agents: [],
  messagesByChannel: {},
  hasMoreByChannel: {},
  typingByChannel: {},
  pendingMention: null,
  // Canal aberto no momento (para não notificar mensagens do canal que estou
  // olhando) e a última notificação pendente de nova mensagem (a Sidebar, sempre
  // montada, observa isso e dispara o toast + som + notificação desktop).
  activeChannelId: null,
  pendingNotification: null,
  uiFlags: {
    isFetchingChannels: false,
    isFetchingMessages: false,
    isSending: false,
    // True when the last channel-list fetch failed (so the list can show a
    // real error + retry instead of the misleading "no conversations" state).
    channelsLoadError: false,
  },
};

export const getters = {
  getChannels: $state => $state.channels,
  getAuditChannels: $state => $state.auditChannels,
  getAgents: $state => $state.agents,
  getMessages: $state => channelId => $state.messagesByChannel[channelId] || [],
  getUIFlags: $state => $state.uiFlags,
  getTotalUnread: $state =>
    $state.channels.reduce((sum, c) => sum + (c.unread_count || 0), 0),
  getPendingMention: $state => $state.pendingMention,
  getPendingNotification: $state => $state.pendingNotification,
  getActiveChannelId: $state => $state.activeChannelId,
  getTypingNames: $state => channelId =>
    Object.values($state.typingByChannel[channelId] || {}).map(u => u.name),
  getHasMore: $state => channelId =>
    Boolean($state.hasMoreByChannel[channelId]),
};

export const actions = {
  fetchChannels: async ({ commit }) => {
    commit('SET_UI_FLAG', {
      isFetchingChannels: true,
      channelsLoadError: false,
    });
    try {
      const { data } = await InternalChatAPI.getChannels();
      commit('SET_CHANNELS', data);
    } catch (error) {
      commit('SET_UI_FLAG', { channelsLoadError: true });
    } finally {
      commit('SET_UI_FLAG', { isFetchingChannels: false });
    }
  },

  fetchAgents: async ({ commit }) => {
    const { data } = await InternalChatAPI.getAgents();
    commit('SET_AGENTS', data);
  },

  // Admin: carrega TODOS os canais da conta para auditoria (somente leitura).
  fetchAuditChannels: async ({ commit }) => {
    const { data } = await InternalChatAPI.getAllChannels();
    commit('SET_AUDIT_CHANNELS', data);
  },

  createDm: async ({ commit, dispatch }, userId) => {
    const { data } = await InternalChatAPI.createDm(userId);
    commit('UPSERT_CHANNEL', data);
    await dispatch('fetchChannels');
    return data;
  },

  createGroup: async ({ commit, dispatch }, { name, memberIds }) => {
    const { data } = await InternalChatAPI.createGroup(name, memberIds);
    commit('UPSERT_CHANNEL', data);
    await dispatch('fetchChannels');
    return data;
  },

  createTeamChannel: async ({ commit, dispatch }, teamId) => {
    const { data } = await InternalChatAPI.createTeamChannel(teamId);
    commit('UPSERT_CHANNEL', data);
    await dispatch('fetchChannels');
    return data;
  },

  fetchMessages: async ({ commit }, channelId) => {
    commit('SET_UI_FLAG', { isFetchingMessages: true });
    // Abrir um canal = ele vira o ativo (não notifica msgs deste enquanto aberto).
    commit('SET_ACTIVE_CHANNEL', channelId);
    try {
      const { data } = await InternalChatAPI.getMessages(channelId);
      commit('SET_MESSAGES', { channelId, messages: data.messages });
      commit('SET_HAS_MORE', { channelId, hasMore: data.has_more });
      // Best-effort: em auditoria (admin não-membro) o markRead retorna 403 —
      // ignorar, pois auditoria é somente leitura e não deve marcar como lido.
      try {
        await InternalChatAPI.markRead(channelId);
        commit('CLEAR_UNREAD', channelId);
      } catch (e) {
        // não-membro/auditoria: silencioso
      }
    } finally {
      commit('SET_UI_FLAG', { isFetchingMessages: false });
    }
  },

  // Sair da tela do chat (ou desmarcar canal) — qualquer mensagem volta a notificar.
  clearActiveChannel: ({ commit }) => commit('SET_ACTIVE_CHANNEL', null),

  // Advance the read cursor for a channel (clears the badge + fires the read
  // receipt to other members). Best-effort: audit/non-members get 403.
  markRead: async ({ commit }, channelId) => {
    try {
      await InternalChatAPI.markRead(channelId);
      commit('CLEAR_UNREAD', channelId);
    } catch (e) {
      // non-member / audit — read is not applicable
    }
  },

  // Load older history (pagination) before the oldest loaded message.
  fetchOlderMessages: async ({ commit, state: $state }, channelId) => {
    const list = $state.messagesByChannel[channelId] || [];
    if (!list.length) return;
    commit('SET_UI_FLAG', { isFetchingMessages: true });
    try {
      const { data } = await InternalChatAPI.getMessages(channelId, list[0].id);
      commit('PREPEND_MESSAGES', { channelId, messages: data.messages });
      commit('SET_HAS_MORE', { channelId, hasMore: data.has_more });
    } finally {
      commit('SET_UI_FLAG', { isFetchingMessages: false });
    }
  },

  sendMessage: async (
    { commit, rootGetters },
    {
      channelId,
      content,
      attachments = [],
      mentionedUserIds = [],
      replyToId = null,
      sharedConversationId = null,
      echoId = null,
    }
  ) => {
    // Optimistic bubble: render the message immediately (status 'progress') so a
    // slow network doesn't leave the sender staring at nothing. The server copy
    // (same echo_id) reconciles it; a failure flips it to 'failed' (with retry).
    if (echoId) {
      const me = rootGetters.getCurrentUser || {};
      commit('APPEND_MESSAGE', {
        channelId,
        message: {
          id: echoId,
          echo_id: echoId,
          content,
          created_at: Math.floor(Date.now() / 1000),
          status: 'progress',
          reactions: {},
          mentioned_user_ids: mentionedUserIds,
          attachments: [],
          user: { id: me.id, name: me.name, avatar_url: me.avatar_url },
        },
      });
    }
    commit('SET_UI_FLAG', { isSending: true });
    try {
      const { data } = await InternalChatAPI.sendMessage(channelId, {
        content,
        attachments,
        mentionedUserIds,
        replyToId,
        sharedConversationId,
        echoId,
      });
      commit('APPEND_MESSAGE', { channelId, message: data });
      return data;
    } catch (error) {
      if (echoId) commit('MARK_MESSAGE_FAILED', { channelId, echoId });
      throw error;
    } finally {
      commit('SET_UI_FLAG', { isSending: false });
    }
  },

  // Fase 5: group management.
  renameChannel: async ({ commit }, { channelId, name }) => {
    const { data } = await InternalChatAPI.renameChannel(channelId, name);
    commit('UPSERT_CHANNEL', data);
    return data;
  },
  addMember: async ({ commit }, { channelId, userId }) => {
    const { data } = await InternalChatAPI.addMember(channelId, userId);
    commit('UPSERT_CHANNEL', data);
    return data;
  },
  removeMember: async ({ commit }, { channelId, userId }) => {
    const { data } = await InternalChatAPI.removeMember(channelId, userId);
    commit('UPSERT_CHANNEL', data);
    return data;
  },
  leaveChannel: async ({ commit }, channelId) => {
    await InternalChatAPI.leaveChannel(channelId);
    commit('REMOVE_CHANNEL', channelId);
  },
  // Real-time: a channel's name/membership changed elsewhere.
  applyChannelUpdated: ({ dispatch }) => dispatch('fetchChannels'),

  // Fase 3: share a customer conversation into a channel or a colleague's DM.
  shareConversation: async (
    { dispatch },
    { channelId, userId, conversationDisplayId, note }
  ) => {
    let targetId = channelId;
    if (!targetId && userId) {
      const channel = await dispatch('createDm', userId);
      targetId = channel?.id;
    }
    if (!targetId) return null;
    await dispatch('sendMessage', {
      channelId: targetId,
      content: note || '',
      sharedConversationId: conversationDisplayId,
    });
    return targetId;
  },

  // Real-time: a message pushed over ActionCable (RoomChannel).
  applyIncomingMessage: (
    { commit, state: $state, rootGetters, dispatch },
    payload
  ) => {
    const channelId = payload.internal_channel_id;
    const message = payload.message;
    if ($state.messagesByChannel[channelId]) {
      commit('APPEND_MESSAGE', { channelId, message });
    }

    // Notifica qualquer mensagem nova de canais de que sou membro (DM, grupo ou
    // time), exceto: minhas próprias, @menções (a notificação de menção já cobre,
    // evita som duplo) e o canal que estou olhando agora (aba visível). A Sidebar
    // observa pendingNotification e dispara toast + som + notificação desktop.
    const channel = $state.channels.find(c => c.id === channelId);
    const currentUserId = rootGetters.getCurrentUserID;
    const fromMe = message.user?.id === currentUserId;
    const mentionsMe =
      Array.isArray(message.mentioned_user_ids) &&
      message.mentioned_user_ids.includes(currentUserId);
    const viewingThis =
      $state.activeChannelId === channelId &&
      typeof document !== 'undefined' &&
      !document.hidden;

    // Unread bookkeeping: my own echoed message never counts; and while I'm
    // actively viewing the channel, keep it read (advances the server cursor +
    // the sender's read receipt) instead of inflating the badge.
    if (!fromMe) {
      if (viewingThis) dispatch('markRead', channelId);
      else commit('BUMP_UNREAD', channelId);
    }

    if (!fromMe && !mentionsMe && !viewingThis) {
      const sender = message.user?.name || '';
      const isDm = channel?.channel_type === 'direct';
      const title = isDm
        ? sender || 'Nova mensagem'
        : [sender, channel?.name].filter(Boolean).join(' · ') ||
          'Nova mensagem';
      commit('SET_PENDING_NOTIFICATION', {
        title,
        body: message.content || '📎',
        channelId,
        at: Date.now(),
      });
    }
  },

  // Real-time: a message was edited / deleted / reacted-to.
  applyUpdatedMessage: ({ commit }, payload) => {
    commit('UPDATE_MESSAGE', {
      channelId: payload.internal_channel_id,
      message: payload.message,
    });
  },

  editMessage: async ({ commit }, { channelId, messageId, content }) => {
    const { data } = await InternalChatAPI.editMessage(
      channelId,
      messageId,
      content
    );
    commit('UPDATE_MESSAGE', { channelId, message: data });
  },

  deleteMessage: async ({ commit }, { channelId, messageId }) => {
    const { data } = await InternalChatAPI.deleteMessage(channelId, messageId);
    commit('UPDATE_MESSAGE', { channelId, message: data });
  },

  reactToMessage: async ({ commit }, { channelId, messageId, emoji }) => {
    const { data } = await InternalChatAPI.reactToMessage(
      channelId,
      messageId,
      emoji
    );
    commit('UPDATE_MESSAGE', { channelId, message: data });
  },

  // "Digitando…" — best-effort; failures are silent (cosmetic feature).
  sendTyping: async (_ctx, { channelId, typing }) => {
    try {
      await InternalChatAPI.sendTyping(channelId, typing);
    } catch (e) {
      // ignore
    }
  },

  applyTyping: (
    { commit },
    { internal_channel_id: channelId, user, typing }
  ) => {
    commit('SET_TYPING', {
      channelId,
      userId: user.id,
      name: user.name,
      typing,
    });
    if (typing) {
      // Safety net: auto-clear if the "stopped typing" event is ever lost.
      setTimeout(
        () =>
          commit('SET_TYPING', { channelId, userId: user.id, typing: false }),
        5000
      );
    }
  },

  // Real-time read receipt: another member read up to last_read_at.
  applyRead: (
    { commit },
    { internal_channel_id: channelId, user_id, last_read_at }
  ) => {
    commit('SET_MEMBER_READ', {
      channelId,
      userId: user_id,
      lastReadAt: last_read_at,
    });
  },

  // Real-time: I was @mentioned. A fresh object (with `at`) guarantees the
  // always-mounted Sidebar watcher fires even for repeated mentions.
  applyIncomingMention: ({ commit }, data) => {
    commit('SET_PENDING_MENTION', {
      from: data.from,
      channel: data.channel_title,
      channelId: data.internal_channel_id,
      at: Date.now(),
    });
  },
};

export const mutations = {
  SET_UI_FLAG($state, flags) {
    $state.uiFlags = { ...$state.uiFlags, ...flags };
  },
  SET_CHANNELS($state, channels) {
    $state.channels = channels;
  },
  SET_AUDIT_CHANNELS($state, channels) {
    $state.auditChannels = channels;
  },
  SET_AGENTS($state, agents) {
    $state.agents = agents;
  },
  UPSERT_CHANNEL($state, channel) {
    const idx = $state.channels.findIndex(c => c.id === channel.id);
    if (idx === -1) $state.channels.unshift(channel);
    else $state.channels.splice(idx, 1, channel);
  },
  REMOVE_CHANNEL($state, channelId) {
    $state.channels = $state.channels.filter(c => c.id !== channelId);
  },
  SET_MESSAGES($state, { channelId, messages }) {
    $state.messagesByChannel = {
      ...$state.messagesByChannel,
      [channelId]: messages,
    };
  },
  SET_HAS_MORE($state, { channelId, hasMore }) {
    $state.hasMoreByChannel = {
      ...$state.hasMoreByChannel,
      [channelId]: hasMore,
    };
  },
  PREPEND_MESSAGES($state, { channelId, messages }) {
    const existing = $state.messagesByChannel[channelId] || [];
    const ids = new Set(existing.map(m => m.id));
    const fresh = messages.filter(m => !ids.has(m.id));
    $state.messagesByChannel = {
      ...$state.messagesByChannel,
      [channelId]: [...fresh, ...existing],
    };
  },
  APPEND_MESSAGE($state, { channelId, message }) {
    const existing = $state.messagesByChannel[channelId] || [];
    // Reconcile an optimistic bubble (temp id === echo_id) with its server copy,
    // whichever arrives first (HTTP response or the socket echo).
    if (message.echo_id) {
      const tempIdx = existing.findIndex(m => m.id === message.echo_id);
      if (tempIdx !== -1) {
        const next = existing.slice();
        next.splice(tempIdx, 1, message);
        $state.messagesByChannel = {
          ...$state.messagesByChannel,
          [channelId]: next,
        };
        return;
      }
    }
    if (existing.some(m => m.id === message.id)) return;
    $state.messagesByChannel = {
      ...$state.messagesByChannel,
      [channelId]: [...existing, message],
    };
  },
  MARK_MESSAGE_FAILED($state, { channelId, echoId }) {
    const existing = $state.messagesByChannel[channelId];
    if (!existing) return;
    const idx = existing.findIndex(m => m.id === echoId);
    if (idx === -1) return;
    const next = existing.slice();
    next.splice(idx, 1, { ...next[idx], status: 'failed' });
    $state.messagesByChannel = {
      ...$state.messagesByChannel,
      [channelId]: next,
    };
  },
  UPDATE_MESSAGE($state, { channelId, message }) {
    const existing = $state.messagesByChannel[channelId];
    if (!existing) return;
    const idx = existing.findIndex(m => m.id === message.id);
    if (idx === -1) return;
    const next = existing.slice();
    next.splice(idx, 1, message);
    $state.messagesByChannel = {
      ...$state.messagesByChannel,
      [channelId]: next,
    };
  },
  CLEAR_UNREAD($state, channelId) {
    const channel = $state.channels.find(c => c.id === channelId);
    if (channel) channel.unread_count = 0;
  },
  BUMP_UNREAD($state, channelId) {
    const channel = $state.channels.find(c => c.id === channelId);
    if (channel) channel.unread_count = (channel.unread_count || 0) + 1;
  },
  SET_PENDING_MENTION($state, mention) {
    $state.pendingMention = mention;
  },
  SET_PENDING_NOTIFICATION($state, notification) {
    $state.pendingNotification = notification;
  },
  SET_ACTIVE_CHANNEL($state, channelId) {
    $state.activeChannelId = channelId;
  },
  SET_TYPING($state, { channelId, userId, name, typing }) {
    const current = { ...($state.typingByChannel[channelId] || {}) };
    if (typing) current[userId] = { name };
    else delete current[userId];
    $state.typingByChannel = {
      ...$state.typingByChannel,
      [channelId]: current,
    };
  },
  SET_MEMBER_READ($state, { channelId, userId, lastReadAt }) {
    const channel = $state.channels.find(c => c.id === channelId);
    if (!channel?.members) return;
    const member = channel.members.find(m => m.id === userId);
    if (member) member.last_read_at = lastReadAt;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
