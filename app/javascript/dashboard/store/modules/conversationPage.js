import * as types from '../mutation-types';

const state = {
  currentPage: {
    me: 0,
    unassigned: 0,
    all: 0,
    appliedFilters: 0,
  },
  nextCursor: {
    me: null,
    unassigned: null,
    all: null,
    appliedFilters: null,
  },
  hasEndReached: {
    me: false,
    unassigned: false,
    all: false,
    appliedFilters: false,
  },
};

export const getters = {
  getHasEndReached: $state => filter => {
    return $state.hasEndReached[filter];
  },
  getCurrentPageFilter: $state => filter => {
    return $state.currentPage[filter];
  },
  getNextCursor: $state => filter => {
    return $state.nextCursor[filter];
  },
  getCurrentPage: $state => {
    return $state.currentPage;
  },
};

export const actions = {
  setCurrentPage({ commit }, { filter, page }) {
    commit(types.default.SET_CURRENT_PAGE, { filter, page });
  },
  setNextCursor({ commit }, { filter, nextCursor }) {
    commit(types.default.SET_NEXT_CURSOR, { filter, nextCursor });
  },
  setEndReached({ commit }, { filter }) {
    commit(types.default.SET_CONVERSATION_END_REACHED, { filter });
  },
  reset({ commit }) {
    commit(types.default.CLEAR_CONVERSATION_PAGE);
  },
};

export const mutations = {
  [types.default.SET_CURRENT_PAGE]: ($state, { filter, page }) => {
    $state.currentPage = {
      ...$state.currentPage,
      [filter]: page,
    };
  },
  [types.default.SET_NEXT_CURSOR]: ($state, { filter, nextCursor }) => {
    $state.nextCursor = {
      ...$state.nextCursor,
      [filter]: nextCursor,
    };
  },
  [types.default.SET_CONVERSATION_END_REACHED]: ($state, { filter }) => {
    if (filter === 'all') {
      $state.hasEndReached = {
        ...$state.hasEndReached,
        unassigned: true,
        me: true,
      };
    }
    $state.hasEndReached = {
      ...$state.hasEndReached,
      [filter]: true,
    };
  },
  [types.default.CLEAR_CONVERSATION_PAGE]: $state => {
    $state.currentPage = {
      me: 0,
      unassigned: 0,
      all: 0,
      appliedFilters: 0,
    };
    $state.nextCursor = {
      me: null,
      unassigned: null,
      all: null,
      appliedFilters: null,
    };
    $state.hasEndReached = {
      me: false,
      unassigned: false,
      all: false,
      appliedFilters: false,
    };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
