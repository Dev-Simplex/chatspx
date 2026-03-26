import types from '../mutation-types';
import ConversationApi from '../../api/inbox/conversation';
import { debounce } from '@chatwoot/utils';

const META_FRESH_THRESHOLD_MS = 5000;

const state = {
  mineCount: 0,
  unAssignedCount: 0,
  allCount: 0,
  unattendedAssignedCount: 0,
  unattendedUnassignedCount: 0,
  unattendedAllCount: 0,
  updatedOn: null,
};

export const getters = {
  getStats: $state => $state,
};

// Create a debounced version of the actual API call function
const fetchMetaData = async (commit, params) => {
  try {
    const response = await ConversationApi.meta(params);
    const {
      data: { meta },
    } = response;
    commit(types.SET_CONV_TAB_META, meta);
  } catch (error) {
    // ignore
  }
};

const debouncedFetchMetaData = debounce(fetchMetaData, 500, false, 1500);
const mediumDebouncedFetchMetaData = debounce(fetchMetaData, 2000, false, 5000);
const longDebouncedFetchMetaData = debounce(fetchMetaData, 5000, false, 10000);
const superLongDebouncedFetchMetaData = debounce(
  fetchMetaData,
  10000,
  false,
  20000
);

export const actions = {
  get: async ({ commit, state: $state }, params) => {
    // Skip threshold check when force flag is set (e.g., view/route change)
    if (
      !params?.force &&
      $state.updatedOn &&
      Date.now() - new Date($state.updatedOn) < META_FRESH_THRESHOLD_MS
    ) {
      return;
    }
    // Remove force flag before sending to API
    if (params?.force) {
      const { force, ...apiParams } = params;
      params = apiParams;
    }
    // First load: fetch meta immediately so tab counts appear without waiting for list
    if ($state.updatedOn == null) {
      await fetchMetaData(commit, params);
      return;
    }
    if ($state.allCount > 5000) {
      superLongDebouncedFetchMetaData(commit, params);
    } else if ($state.allCount > 500) {
      longDebouncedFetchMetaData(commit, params);
    } else if ($state.allCount > 100) {
      mediumDebouncedFetchMetaData(commit, params);
    } else {
      debouncedFetchMetaData(commit, params);
    }
  },
  set({ commit }, meta) {
    commit(types.SET_CONV_TAB_META, meta);
  },
};

export const mutations = {
  [types.SET_CONV_TAB_META]($state, payload = {}) {
    const {
      mine_count: mineCount,
      unassigned_count: unAssignedCount,
      all_count: allCount,
      unattended_assigned_to_me_count: unattendedAssignedCount,
      unattended_unassigned_count: unattendedUnassignedCount,
      unattended_all_count: unattendedAllCount,
    } = payload;
    $state.mineCount = mineCount;
    $state.allCount = allCount;
    $state.unAssignedCount = unAssignedCount;
    if ('unattended_assigned_to_me_count' in payload) {
      $state.unattendedAssignedCount = unattendedAssignedCount ?? 0;
    }
    if ('unattended_unassigned_count' in payload) {
      $state.unattendedUnassignedCount = unattendedUnassignedCount ?? 0;
    }
    if ('unattended_all_count' in payload) {
      $state.unattendedAllCount = unattendedAllCount ?? 0;
    }
    $state.updatedOn = new Date();
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
