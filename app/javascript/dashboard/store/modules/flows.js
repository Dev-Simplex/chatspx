import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import FlowsAPI from '../../api/flows';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isDeleting: false,
    isUpdating: false,
    isExecuting: false,
    isSimulating: false,
    isFetchingLogs: false,
  },
};

export const getters = {
  getFlows(_state) {
    return _state.records.sort((a1, a2) => a1.id - a2.id);
  },
  getFlow: _state => id =>
    _state.records.find(record => record.id === Number(id)),
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  get: async function getFlows({ commit }) {
    commit(types.SET_FLOW_UI_FLAG, { isFetching: true });
    try {
      const response = await FlowsAPI.get();
      commit(types.SET_FLOWS, response.data.payload);
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.SET_FLOW_UI_FLAG, { isFetching: false });
    }
  },
  show: async function showFlow({ commit }, id) {
    commit(types.SET_FLOW_UI_FLAG, { isFetching: true });
    try {
      const response = await FlowsAPI.show(id);
      commit(types.ADD_FLOW, response.data);
      return response.data;
    } finally {
      commit(types.SET_FLOW_UI_FLAG, { isFetching: false });
    }
  },
  create: async function createFlow({ commit }, flowObj) {
    commit(types.SET_FLOW_UI_FLAG, { isCreating: true });
    try {
      const response = await FlowsAPI.create(flowObj);
      commit(types.ADD_FLOW, response.data);
      return response.data;
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_FLOW_UI_FLAG, { isCreating: false });
    }
  },
  update: async ({ commit }, { id, ...updateObj }) => {
    commit(types.SET_FLOW_UI_FLAG, { isUpdating: true });
    try {
      const response = await FlowsAPI.update(id, updateObj);
      commit(types.EDIT_FLOW, response.data);
      return response.data;
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_FLOW_UI_FLAG, { isUpdating: false });
    }
  },
  delete: async ({ commit }, id) => {
    commit(types.SET_FLOW_UI_FLAG, { isDeleting: true });
    try {
      await FlowsAPI.delete(id);
      commit(types.DELETE_FLOW, id);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_FLOW_UI_FLAG, { isDeleting: false });
    }
  },
  execute: async ({ commit }, { id, conversationIds }) => {
    commit(types.SET_FLOW_UI_FLAG, { isExecuting: true });
    try {
      await FlowsAPI.execute(id, conversationIds);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_FLOW_UI_FLAG, { isExecuting: false });
    }
  },
  // Simulação (dry-run). Deixa o erro do axios propagar CRU (sem `new Error(error)`) pra o overlay
  // conseguir ler `error.response.status` — o 422 "sem conversa" precisa ser distinguível.
  simulate: async ({ commit }, { id, conversationId = null }) => {
    commit(types.SET_FLOW_UI_FLAG, { isSimulating: true });
    try {
      const response = await FlowsAPI.simulate(id, conversationId);
      return response.data;
    } finally {
      commit(types.SET_FLOW_UI_FLAG, { isSimulating: false });
    }
  },
  getLogs: async ({ commit }, { id, page = 1 }) => {
    commit(types.SET_FLOW_UI_FLAG, { isFetchingLogs: true });
    try {
      const response = await FlowsAPI.getLogs(id, page);
      return response.data;
    } finally {
      commit(types.SET_FLOW_UI_FLAG, { isFetchingLogs: false });
    }
  },
};

export const mutations = {
  [types.SET_FLOW_UI_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  [types.ADD_FLOW]: MutationHelpers.create,
  [types.SET_FLOWS]: MutationHelpers.set,
  [types.EDIT_FLOW]: MutationHelpers.update,
  [types.DELETE_FLOW]: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  actions,
  state,
  getters,
  mutations,
};
