import camelcaseKeys from 'camelcase-keys';
import types from '../mutation-types';
import ActiveAttendancesAPI from '../../api/activeAttendances';

// Store PRÓPRIO, separado de `contacts`: os records aqui são conversa-shaped e o
// store de contatos é chaveado por id de contato — misturá-los corromperia a aba
// "Todos os contatos". Um contato pode ter 2 atendimentos (2 caixas, 2 agentes),
// então a lista é de ATENDIMENTOS, não de contatos.
export const state = {
  records: [],
  meta: {
    count: 0,
    currentPage: 1,
  },
  uiFlags: {
    isFetching: false,
  },
};

export const getters = {
  getAttendances(_state) {
    return _state.records;
  },
  getMeta(_state) {
    return _state.meta;
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
  // A Fase 2 usa isto p/ avisar que o contato já está em atendimento.
  getByContactId: _state => contactId =>
    _state.records.filter(record => record.contact?.id === Number(contactId)),
};

export const actions = {
  get: async ({ commit }, { page = 1, contactId } = {}) => {
    commit(types.SET_ACTIVE_ATTENDANCES_UI_FLAG, { isFetching: true });
    try {
      const { data } = await ActiveAttendancesAPI.get({ page, contactId });
      commit(types.SET_ACTIVE_ATTENDANCES, data.payload ?? []);
      commit(types.SET_ACTIVE_ATTENDANCES_META, {
        count: data.meta?.count ?? 0,
        currentPage: Number(data.meta?.current_page) || 1,
      });
    } finally {
      commit(types.SET_ACTIVE_ATTENDANCES_UI_FLAG, { isFetching: false });
    }
  },
};

export const mutations = {
  [types.SET_ACTIVE_ATTENDANCES_UI_FLAG](_state, uiFlags) {
    _state.uiFlags = { ..._state.uiFlags, ...uiFlags };
  },
  [types.SET_ACTIVE_ATTENDANCES](_state, records) {
    // camelCase deep, igual ao store de contatos (contacts/mutations.js:4).
    _state.records = records.map(record =>
      camelcaseKeys(record, { deep: true })
    );
  },
  [types.SET_ACTIVE_ATTENDANCES_META](_state, meta) {
    _state.meta = { ..._state.meta, ...meta };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
