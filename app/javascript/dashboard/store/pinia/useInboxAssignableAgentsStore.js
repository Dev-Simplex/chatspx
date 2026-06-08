import { defineStore, acceptHMRUpdate } from 'pinia';
import AssignableAgentsAPI from '../../api/assignableAgents';

// Espelho Pinia de store/modules/inboxAssignableAgents.js (Onda 2 P0-05).
export const useInboxAssignableAgentsStore = defineStore(
  'inboxAssignableAgents',
  {
    state: () => ({
      records: {},
      uiFlags: {
        isFetching: false,
      },
    }),

    getters: {
      getAssignableAgents: state => inboxId => {
        const all = state.records[inboxId] || [];
        return all.filter(r => r.confirmed);
      },
      getUIFlags: state => state.uiFlags,
    },

    actions: {
      async fetch(inboxIds) {
        this.uiFlags.isFetching = true;
        try {
          const {
            data: { payload },
          } = await AssignableAgentsAPI.get(inboxIds);
          this.records = { ...this.records, [inboxIds.join(',')]: payload };
        } catch (error) {
          throw new Error(error);
        } finally {
          this.uiFlags.isFetching = false;
        }
      },
    },
  }
);

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useInboxAssignableAgentsStore, import.meta.hot)
  );
}
