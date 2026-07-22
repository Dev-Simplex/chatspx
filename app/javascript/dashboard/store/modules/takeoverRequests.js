import camelcaseKeys from 'camelcase-keys';
import types from '../mutation-types';
import TakeoverRequestsAPI from '../../api/takeoverRequests';

// Pedidos de atendimento (D1 / Fase 3). Store separado, chaveado por id do
// pedido. `incoming` = pedidos que EU (dono) preciso responder; a lista é a
// superfície durável, porque o sino não serve de CTA (some na próxima mensagem).
export const state = {
  records: {},
  uiFlags: { isFetching: false, isCreating: false },
  // Último pedido MEU (solicitante) que foi respondido — o toaster mostra e limpa.
  // Sem isto o solicitante não saberia que foi NEGADO (no aprovado ele ganha a
  // conversa; no negado nada muda, então precisa de aviso explícito).
  resolvedNotice: null,
};

const normalize = record => camelcaseKeys(record, { deep: true });

export const getters = {
  // "incoming" = pedidos em que EU sou o dono (preciso responder). Filtra por
  // owner.id: create()/cancel() injetam a linha OUTGOING (owner=colega) no mesmo
  // mapa `records`, então sem o filtro por dono o pedido que EU enviei inflava o
  // meu próprio badge/lista "Pedidos".
  getIncoming(_state, _getters, _rootState, rootGetters) {
    const uid = rootGetters.getCurrentUserID;
    return Object.values(_state.records)
      .filter(r => r.status === 'pending' && r.owner?.id === uid)
      .sort((a, b) => b.createdAt - a.createdAt);
  },
  // Contador do item "Pedidos" na sidebar (padrão getterKeys.count).
  getIncomingCount(_state, _getters, _rootState, rootGetters) {
    const uid = rootGetters.getCurrentUserID;
    return Object.values(_state.records).filter(
      r => r.status === 'pending' && r.owner?.id === uid
    ).length;
  },
  // Pendentes de uma conversa específica (o banner no topo da conversa usa).
  getPendingForConversation: _state => conversationId =>
    Object.values(_state.records).filter(
      r => r.status === 'pending' && r.conversationId === conversationId
    ),
  getUIFlags(_state) {
    return _state.uiFlags;
  },
  getResolvedNotice(_state) {
    return _state.resolvedNotice;
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

  // Vindos do realtime dirigido (takeover_request.created/updated). Um evento só,
  // dois papéis: (1) DONO → refaz a lista/contador; (2) SOLICITANTE → se o MEU
  // pedido foi respondido, guarda o aviso p/ o toaster mostrar.
  handleRealtimeEvent: ({ commit, dispatch, rootGetters }, data = {}) => {
    dispatch('fetchIncoming'); // lado do dono (contador + lista)

    const myId = rootGetters.getCurrentUserID;
    const requesterId = data.requester?.id ?? data.requester_id;
    const status = data.status;
    // superseded: outro pedido foi aprovado / a conversa trocou de mãos — o MEU
    // pedido morreu. Sem este aviso o solicitante perdedor ficaria preso em
    // "Pedido enviado" (é o cenário multi-agente que a feature resolve).
    if (
      requesterId === myId &&
      ['approved', 'denied', 'superseded'].includes(status)
    ) {
      commit(types.SET_TAKEOVER_RESOLVED_NOTICE, {
        status,
        conversationId: data.conversation_id ?? data.conversationId,
        note: data.response_note ?? data.responseNote ?? null,
      });
    }
  },

  clearResolvedNotice: ({ commit }) => {
    commit(types.SET_TAKEOVER_RESOLVED_NOTICE, null);
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
  [types.SET_TAKEOVER_RESOLVED_NOTICE](_state, notice) {
    _state.resolvedNotice = notice;
  },
};

export default { namespaced: true, state, getters, actions, mutations };
