import InternalChatAPI from '../../api/internalChat';

export const state = {
  channels: [],
  agents: [],
  messagesByChannel: {},
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

  sendMessage: async ({ commit }, { channelId, content }) => {
    commit('SET_UI_FLAG', { isSending: true });
    try {
      const { data } = await InternalChatAPI.sendMessage(channelId, content);
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
  CLEAR_UNREAD($state, channelId) {
    const channel = $state.channels.find(c => c.id === channelId);
    if (channel) channel.unread_count = 0;
  },
  BUMP_UNREAD($state, channelId) {
    const channel = $state.channels.find(c => c.id === channelId);
    if (channel) channel.unread_count = (channel.unread_count || 0) + 1;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
