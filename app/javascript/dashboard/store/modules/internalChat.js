import InternalChatAPI from '../../api/internalChat';

export const state = {
  channels: [],
  agents: [],
  messagesByChannel: {},
  pendingMention: null,
  uiFlags: {
    isFetchingChannels: false,
    isFetchingMessages: false,
    isSending: false,
  },
};

export const getters = {
  getChannels: $state => $state.channels,
  getAgents: $state => $state.agents,
  getMessages: $state => channelId => $state.messagesByChannel[channelId] || [],
  getUIFlags: $state => $state.uiFlags,
  getTotalUnread: $state =>
    $state.channels.reduce((sum, c) => sum + (c.unread_count || 0), 0),
  getPendingMention: $state => $state.pendingMention,
};

export const actions = {
  fetchChannels: async ({ commit }) => {
    commit('SET_UI_FLAG', { isFetchingChannels: true });
    try {
      const { data } = await InternalChatAPI.getChannels();
      commit('SET_CHANNELS', data);
    } finally {
      commit('SET_UI_FLAG', { isFetchingChannels: false });
    }
  },

  fetchAgents: async ({ commit }) => {
    const { data } = await InternalChatAPI.getAgents();
    commit('SET_AGENTS', data);
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
    try {
      const { data } = await InternalChatAPI.getMessages(channelId);
      commit('SET_MESSAGES', { channelId, messages: data });
      await InternalChatAPI.markRead(channelId);
      commit('CLEAR_UNREAD', channelId);
    } finally {
      commit('SET_UI_FLAG', { isFetchingMessages: false });
    }
  },

  sendMessage: async (
    { commit },
    { channelId, content, attachments = [], mentionedUserIds = [] }
  ) => {
    commit('SET_UI_FLAG', { isSending: true });
    try {
      const { data } = await InternalChatAPI.sendMessage(channelId, {
        content,
        attachments,
        mentionedUserIds,
      });
      commit('APPEND_MESSAGE', { channelId, message: data });
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSending: false });
    }
  },

  // Real-time: a message pushed over ActionCable (RoomChannel).
  applyIncomingMessage: ({ commit, state: $state }, payload) => {
    const channelId = payload.internal_channel_id;
    const message = payload.message;
    if ($state.messagesByChannel[channelId]) {
      commit('APPEND_MESSAGE', { channelId, message });
    }
    commit('BUMP_UNREAD', channelId);
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
  SET_AGENTS($state, agents) {
    $state.agents = agents;
  },
  UPSERT_CHANNEL($state, channel) {
    const idx = $state.channels.findIndex(c => c.id === channel.id);
    if (idx === -1) $state.channels.unshift(channel);
    else $state.channels.splice(idx, 1, channel);
  },
  SET_MESSAGES($state, { channelId, messages }) {
    $state.messagesByChannel = {
      ...$state.messagesByChannel,
      [channelId]: messages,
    };
  },
  APPEND_MESSAGE($state, { channelId, message }) {
    const existing = $state.messagesByChannel[channelId] || [];
    if (existing.some(m => m.id === message.id)) return;
    $state.messagesByChannel = {
      ...$state.messagesByChannel,
      [channelId]: [...existing, message],
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
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
