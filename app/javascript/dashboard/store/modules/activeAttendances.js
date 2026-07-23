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
    perPage: 15,
  },
  uiFlags: {
    isFetching: false,
    // hasError existe porque "deu erro" e "não tem ninguém em atendimento" são
    // respostas OPOSTAS que ficariam idênticas na tela (lista vazia). Numa aba
    // que existe p/ responder "alguém já atende este contato?", engolir a falha
    // e dizer "ninguém" é justamente a resposta errada — e a Fase 2 usa esta
    // mesma fonte p/ decidir se avisa o agente.
    hasError: false,
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
  // (A Fase 2 NÃO lê do store: usa useAttendanceGate.fetchAttendances, que chama a
  // API direto — por isso não existe um getter por contato aqui.)
};

export const actions = {
  get: async ({ commit }, { page = 1, contactId } = {}) => {
    commit(types.SET_ACTIVE_ATTENDANCES_UI_FLAG, {
      isFetching: true,
      hasError: false,
    });
    try {
      const { data } = await ActiveAttendancesAPI.get({ page, contactId });
      commit(types.SET_ACTIVE_ATTENDANCES, data.payload ?? []);
      commit(types.SET_ACTIVE_ATTENDANCES_META, {
        count: data.meta?.count ?? 0,
        currentPage: Number(data.meta?.current_page) || 1,
        perPage: Number(data.meta?.per_page) || 15,
      });
    } catch (error) {
      // Zera os records: manter a página anterior na tela enquanto a URL/paginação
      // dizem outra coisa mente tanto quanto o "ninguém em atendimento".
      commit(types.SET_ACTIVE_ATTENDANCES, []);
      commit(types.SET_ACTIVE_ATTENDANCES_UI_FLAG, { hasError: true });
      throw error;
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
