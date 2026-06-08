/* eslint-disable no-underscore-dangle, no-useless-catch */
import { defineStore, acceptHMRUpdate } from 'pinia';
import { debounce } from '@chatwoot/utils';
import ConversationApi from '../../api/inbox/conversation';

// Espelho Pinia de store/modules/conversationStats.js (Onda 2 P0-05).
const META_FRESH_THRESHOLD_MS = 5000;

export const useConversationStatsStore = defineStore('conversationStats', {
  state: () => ({
    mineCount: 0,
    unAssignedCount: 0,
    allCount: 0,
    unattendedAssignedCount: 0,
    unattendedUnassignedCount: 0,
    unattendedAllCount: 0,
    updatedOn: null,
  }),

  getters: {
    getStats: state => ({
      mineCount: state.mineCount,
      unAssignedCount: state.unAssignedCount,
      allCount: state.allCount,
      unattendedAssignedCount: state.unattendedAssignedCount,
      unattendedUnassignedCount: state.unattendedUnassignedCount,
      unattendedAllCount: state.unattendedAllCount,
      updatedOn: state.updatedOn,
    }),
  },

  actions: {
    _applyMeta(payload = {}) {
      const {
        mine_count: mineCount,
        unassigned_count: unAssignedCount,
        all_count: allCount,
        unattended_assigned_to_me_count: unattendedAssignedCount,
        unattended_unassigned_count: unattendedUnassignedCount,
        unattended_all_count: unattendedAllCount,
      } = payload;
      this.mineCount = mineCount;
      this.allCount = allCount;
      this.unAssignedCount = unAssignedCount;
      if ('unattended_assigned_to_me_count' in payload) {
        this.unattendedAssignedCount = unattendedAssignedCount ?? 0;
      }
      if ('unattended_unassigned_count' in payload) {
        this.unattendedUnassignedCount = unattendedUnassignedCount ?? 0;
      }
      if ('unattended_all_count' in payload) {
        this.unattendedAllCount = unattendedAllCount ?? 0;
      }
      this.updatedOn = new Date();
    },

    async _fetchMetaData(params) {
      try {
        const response = await ConversationApi.meta(params);
        this._applyMeta(response.data.meta);
      } catch (error) {
        if (error?.name === 'AbortError' || error?.name === 'CanceledError')
          return;
        const status = error?.response?.status;
        if (status && status < 500) return;
        try {
          const response = await ConversationApi.meta(params);
          this._applyMeta(response.data.meta);
        } catch {
          // ignore after retry
        }
      }
    },

    async get(params) {
      if (params?.force) {
        const { force, ...apiParams } = params;
        await this._fetchMetaData(apiParams);
        return;
      }
      if (
        this.updatedOn &&
        Date.now() - new Date(this.updatedOn) < META_FRESH_THRESHOLD_MS
      ) {
        return;
      }
      if (this.updatedOn == null) {
        await this._fetchMetaData(params);
        return;
      }
      this._debouncedFetch(params);
    },

    _debouncedFetch(params) {
      // Cria debouncers lazy por instancia para preservar timing
      if (!this._debouncedFns) {
        const make = (wait, max) =>
          debounce(p => this._fetchMetaData(p), wait, false, max);
        this._debouncedFns = {
          short: make(500, 1500),
          medium: make(2000, 5000),
          long: make(5000, 10000),
          superLong: make(10000, 20000),
        };
      }
      if (this.allCount > 5000) this._debouncedFns.superLong(params);
      else if (this.allCount > 500) this._debouncedFns.long(params);
      else if (this.allCount > 100) this._debouncedFns.medium(params);
      else this._debouncedFns.short(params);
    },

    set(meta) {
      this._applyMeta(meta);
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useConversationStatsStore, import.meta.hot)
  );
}
