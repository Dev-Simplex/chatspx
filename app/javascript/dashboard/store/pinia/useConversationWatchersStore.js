import { defineStore, acceptHMRUpdate } from 'pinia';
import { throwErrorMessage } from 'dashboard/store/utils/api';
import ConversationInboxApi from '../../api/inbox/conversation';

// Espelho Pinia de store/modules/conversationWatchers.js (Onda 2 P0-05).
export const useConversationWatchersStore = defineStore(
  'conversationWatchers',
  {
    state: () => ({
      records: {},
      uiFlags: {
        isFetching: false,
        isUpdating: false,
      },
    }),

    getters: {
      getUIFlags: state => state.uiFlags,
      getByConversationId: state => conversationId =>
        state.records[conversationId],
    },

    actions: {
      async show({ conversationId }) {
        this.uiFlags.isFetching = true;
        try {
          const response =
            await ConversationInboxApi.fetchParticipants(conversationId);
          this.records = { ...this.records, [conversationId]: response.data };
        } catch (error) {
          throwErrorMessage(error);
        } finally {
          this.uiFlags.isFetching = false;
        }
      },

      async update({ conversationId, userIds }) {
        this.uiFlags.isUpdating = true;
        try {
          const response = await ConversationInboxApi.updateParticipants({
            conversationId,
            userIds,
          });
          this.records = { ...this.records, [conversationId]: response.data };
        } catch (error) {
          throwErrorMessage(error);
        } finally {
          this.uiFlags.isUpdating = false;
        }
      },
    },
  }
);

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useConversationWatchersStore, import.meta.hot)
  );
}
