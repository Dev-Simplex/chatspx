import AssistantLogsAPI from 'dashboard/api/captain/assistantLogs';

const state = {
  records: [],
  meta: {},
  uiFlags: { isFetching: false },
};

const getters = {
  getLogs: s => s.records,
  getMeta: s => s.meta,
  getUIFlags: s => s.uiFlags,
};

const mutations = {
  SET_LOGS(s, { data, meta }) {
    s.records = data;
    s.meta = meta;
  },
  SET_FETCHING(s, flag) {
    s.uiFlags = { ...s.uiFlags, isFetching: flag };
  },
};

const actions = {
  async fetch({ commit }, params = {}) {
    commit('SET_FETCHING', true);
    try {
      const { data } = await AssistantLogsAPI.get(params);
      commit('SET_LOGS', data);
    } catch (error) {
      // noop
    } finally {
      commit('SET_FETCHING', false);
    }
  },
};

export default {
  namespaced: true,
  state,
  getters,
  mutations,
  actions,
};
