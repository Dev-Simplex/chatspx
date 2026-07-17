import camelcaseKeys from 'camelcase-keys';
import types from '../mutation-types';
import TakeoverRequestsAPI from '../../api/takeoverRequests';

// Pedidos de atendimento (D1 / Fase 3). Store separado, chaveado por id do
// pedido. `incoming` = pedidos que EU (dono) preciso responder; a lista é a
// superfície durável, porque o sino não serve de CTA (some na próxima mensagem).
export const state = {
  records: {},
  uiFlags: { isFetching: false, isCreating: false },
};

const normalize = record => camelcaseKeys(record, { deep: true });

export const getters = {
  getIncoming(_state) {
    return Object.values(_state.records)
      .filter(r => r.status === 'pending' && r.owner)
      .sort((a, b) => b.createdAt - a.createdAt);
  },
  // Pendentes de uma conversa específica (o banner no topo da conversa usa).
  getPendingForConversation: _state => conversationId =>
    Object.values(_state.records).filter(
      r => r.status === 'pending' && r.conversationId === conversationId
    ),
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  create: async ({ commit }, { conversationId, reason }) => {
    commit(types.SET_TAKEOVER_REQUEST_UI_FLAG, { isCreating: true });
    try {
      const { data } = await TakeoverRequestsAPI.create({
        conversationId,
        reason,
      });
      commit(types.SET_TAKEOVER_REQUEST, data);
      return data;
    } finally {
      commit(types.SET_TAKEOVER_REQUEST_UI_FLAG, { isCreating: false });
    }
  },

  fetchIncoming: async ({ commit }) => {
    commit(types.SET_TAKEOVER_REQUEST_UI_FLAG, { isFetching: true });
    try {
      const { data } = await TakeoverRequestsAPI.get({
        scope: 'incoming',
        status: 'pending',
      });
      commit(types.SET_TAKEOVER_REQUESTS, data.payload ?? []);
    } finally {
      commit(types.SET_TAKEOVER_REQUEST_UI_FLAG, { isFetching: false });
    }
  },

  approve: async ({ commit }, { id, responseNote }) => {
    const { data } = await TakeoverRequestsAPI.approve(id, responseNote);
    commit(types.SET_TAKEOVER_REQUEST, data);
    return data;
  },

  deny: async ({ commit }, { id, responseNote }) => {
    const { data } = await TakeoverRequestsAPI.deny(id, responseNote);
    commit(types.SET_TAKEOVER_REQUEST, data);
    return data;
  },

  cancel: async ({ commit }, { id }) => {
    const { data } = await TakeoverRequestsAPI.cancel(id);
    commit(types.SET_TAKEOVER_REQUEST, data);
    return data;
  },

  // Vindos do realtime dirigido (takeover_request_created/updated).
  upsertFromRealtime: ({ commit }, record) => {
    commit(types.SET_TAKEOVER_REQUEST, record);
  },
};

export const mutations = {
  [types.SET_TAKEOVER_REQUEST_UI_FLAG](_state, uiFlags) {
    _state.uiFlags = { ..._state.uiFlags, ...uiFlags };
  },
  [types.SET_TAKEOVER_REQUEST](_state, record) {
    const normalized = normalize(record);
    _state.records = { ..._state.records, [normalized.id]: normalized };
  },
  [types.SET_TAKEOVER_REQUESTS](_state, records) {
    const map = {};
    records.forEach(record => {
      const normalized = normalize(record);
      map[normalized.id] = normalized;
    });
    _state.records = map;
  },
};

export default { namespaced: true, state, getters, actions, mutations };
