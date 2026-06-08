import { defineStore, acceptHMRUpdate } from 'pinia';
import InboxMembersAPI from '../../api/inboxMembers';

// Espelho Pinia de store/modules/inboxMembers.js (Onda 2 P0-05).
export const useInboxMembersStore = defineStore('inboxMembers', {
  state: () => ({}),

  actions: {
    get({ inboxId }) {
      return InboxMembersAPI.show(inboxId);
    },

    create({ inboxId, agentList }) {
      return InboxMembersAPI.update({ inboxId, agentList });
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useInboxMembersStore, import.meta.hot)
  );
}
