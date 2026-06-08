import { defineStore, acceptHMRUpdate } from 'pinia';
import ConversationAPI from '../../api/inbox/conversation';

// Espelho Pinia de store/modules/conversationTypingStatus.js (Onda 2 P0-05).
export const useConversationTypingStatusStore = defineStore(
  'conversationTypingStatus',
  {
    state: () => ({
      records: {},
    }),

    getters: {
      getUserList: state => id => state.records[Number(id)] || [],
    },

    actions: {
      async toggleTyping({ status, conversationId, isPrivate }) {
        try {
          await ConversationAPI.toggleTyping({
            status,
            conversationId,
            isPrivate,
          });
        } catch (error) {
          // Handle error
        }
      },

      create({ conversationId, user }) {
        const records = this.records[conversationId] || [];
        const exists = records.some(
          r => r.id === user.id && r.type === user.type
        );
        if (!exists) {
          this.records = {
            ...this.records,
            [conversationId]: [...records, user],
          };
        }
      },

      destroy({ conversationId, user }) {
        const records = this.records[conversationId] || [];
        this.records = {
          ...this.records,
          [conversationId]: records.filter(
            r => r.id !== user.id || r.type !== user.type
          ),
        };
      },
    },
  }
);

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useConversationTypingStatusStore, import.meta.hot)
  );
}
