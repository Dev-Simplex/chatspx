import types from '../mutation-types';
import ConversationApi from '../../api/inbox/conversation';
import { debounce } from '@chatwoot/utils';

const META_FRESH_THRESHOLD_MS = 5000;

const state = {
  mineCount: 0,
  unAssignedCount: 0,
  aiCount: 0,
  awaitingCount: 0,
  awaitingClosureCount: 0,
  allCount: 0,
  unattendedAssignedCount: 0,
  unattendedUnassignedCount: 0,
  unattendedAllCount: 0,
  updatedOn: null,
};

export const getters = {
  getStats: $state => $state,
  // Numeric getter for the sidebar badge. getStats returns the whole state
  // object, which renders as NaN when used as a count — this exposes just the
  // unassigned number.
  getUnAssignedCount: $state => $state.unAssignedCount || 0,
  // "Aguardando atendimento" (modelo B) sidebar badge: count of conversations
  // the AI handed off (custom_attributes.aguardando_humano_desde present) and is
  // still attending until a human takes over. Backed by awaiting_count from /meta.
  getAwaitingCount: $state => $state.awaitingCount || 0,
  // "Aguardando encerramento" badge. Backed by awaiting_closure_count from /meta.
  getAwaitingClosureCount: $state => $state.awaitingClosureCount || 0,
};

// Fetch metadata with single retry on transient failure
const fetchMetaData = async (commit, params) => {
  try {
    const response = await ConversationApi.meta(params);
    const {
      data: { meta },
    } = response;
    commit(types.SET_CONV_TAB_META, meta);
  } catch (error) {
    if (error?.name === 'AbortError' || error?.name === 'CanceledError') return;
    const status = error?.response?.status;
    if (status && status < 500) return;
    try {
      const response = await ConversationApi.meta(params);
      const {
        data: { meta },
      } = response;
      commit(types.SET_CONV_TAB_META, meta);
    } catch {
      // ignore after retry
    }
  }
};

const debouncedFetchMetaData = debounce(fetchMetaData, 1000, false, 5000);
const longDebouncedFetchMetaData = debounce(fetchMetaData, 7500, false, 20000);
const superLongDebouncedFetchMetaData = debounce(
  fetchMetaData,
  15000,
  false,
  30000
);

const metaDebouncers = {
  default: debouncedFetchMetaData,
  long: longDebouncedFetchMetaData,
  superLong: superLongDebouncedFetchMetaData,
};

// allCount is 0 until a meta request succeeds; under load it stays 0, so treat
// the unknown case as a large account and poll slowest instead of fastest.
export const getMetaDebounceKey = allCount => {
  if (allCount > 2000 || allCount === 0) return 'superLong';
  if (allCount > 100) return 'long';
  return 'default';
};

export const actions = {
  get: async ({ commit, state: $state }, params) => {
    // When force flag is set (view/route change), fetch immediately
    // bypassing both threshold and debounce
    if (params?.force) {
      const { force, ...apiParams } = params;
      await fetchMetaData(commit, apiParams);
      return;
    }
    if (
      $state.updatedOn &&
      Date.now() - new Date($state.updatedOn) < META_FRESH_THRESHOLD_MS
    ) {
      return;
    }
    // First load: fetch immediately so tab counts appear without waiting for list
    if ($state.updatedOn == null) {
      await fetchMetaData(commit, params);
      return;
    }
    metaDebouncers[getMetaDebounceKey($state.allCount)](commit, params);
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
      ai_count: aiCount,
      awaiting_count: awaitingCount,
      awaiting_closure_count: awaitingClosureCount,
      all_count: allCount,
      unattended_assigned_to_me_count: unattendedAssignedCount,
      unattended_unassigned_count: unattendedUnassignedCount,
      unattended_all_count: unattendedAllCount,
    } = payload;
    $state.mineCount = mineCount;
    $state.allCount = allCount;
    $state.unAssignedCount = unAssignedCount;
    // Meta arrives from two sources (/meta endpoint and conversation list
    // payloads) — only update when the field is present to avoid zeroing
    // the count with a partial payload.
    if ('ai_count' in payload) {
      $state.aiCount = aiCount ?? 0;
    }
    if ('awaiting_count' in payload) {
      $state.awaitingCount = awaitingCount ?? 0;
    }
    if ('awaiting_closure_count' in payload) {
      $state.awaitingClosureCount = awaitingClosureCount ?? 0;
    }
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
