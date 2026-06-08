import { defineStore, acceptHMRUpdate } from 'pinia';
import AuditLogsAPI from '../../api/auditLogs';
import { throwErrorMessage } from 'dashboard/store/utils/api';

// Espelho Pinia de store/modules/auditlogs.js (Onda 2 P0-05).
export const useAuditlogsStore = defineStore('auditlogs', {
  state: () => ({
    records: [],
    meta: {
      currentPage: 1,
      perPage: 15,
      totalEntries: 0,
    },
    uiFlags: {
      fetchingList: false,
    },
  }),

  getters: {
    getAuditLogs: state => state.records,
    getUIFlags: state => state.uiFlags,
    getMeta: state => state.meta,
  },

  actions: {
    async fetch({ page } = {}) {
      this.uiFlags.fetchingList = true;
      try {
        const response = await AuditLogsAPI.get({ page });
        const { audit_logs: logs = [] } = response.data;
        const {
          total_entries: totalEntries,
          per_page: perPage,
          current_page: currentPage,
        } = response.data;
        this.records = logs;
        this.meta = { ...this.meta, totalEntries, perPage, currentPage };
        return logs;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.uiFlags.fetchingList = false;
      }
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useAuditlogsStore, import.meta.hot));
}
