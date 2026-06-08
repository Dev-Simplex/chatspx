import { defineStore, acceptHMRUpdate } from 'pinia';
import SearchAPI from '../../api/search';
import { useContactsStore } from './useContactsStore';

// Espelho Pinia de store/modules/conversationSearch.js (Onda 2 P0-05).
let conversationSearchAbortController = null;

export const useConversationSearchStore = defineStore('conversationSearch', {
  state: () => ({
    records: [],
    contactRecords: [],
    conversationRecords: [],
    lastConversationSearchRequestId: null,
    conversationSearchQuery: '',
    conversationSearchCompleted: false,
    messageRecords: [],
    articleRecords: [],
    uiFlags: {
      isFetching: false,
      isSearchCompleted: false,
      contact: { isFetching: false },
      conversation: { isFetching: false },
      message: { isFetching: false },
      article: { isFetching: false },
    },
  }),

  getters: {
    getConversations: state => state.records,
    getContactRecords: state => state.contactRecords,
    getConversationRecords: state => state.conversationRecords,
    getMessageRecords: state => state.messageRecords,
    getArticleRecords: state => state.articleRecords,
    getUIFlags: state => state.uiFlags,
    getConversationSearchQuery: state => state.conversationSearchQuery || '',
    getConversationSearchCompleted: state =>
      state.conversationSearchCompleted || false,
  },

  actions: {
    async get({ q }) {
      this.records = [];
      if (!q) return;
      this.uiFlags.isFetching = true;
      try {
        const {
          data: { payload },
        } = await SearchAPI.get({ q });
        this.records = payload;
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async fullSearch(payload) {
      const { q, ...filters } = payload;
      if (!q && !Object.keys(filters).length) return;
      this.uiFlags.isFetching = true;
      this.uiFlags.isSearchCompleted = false;
      try {
        await Promise.all([
          this.contactSearch({ q, ...filters }),
          this.conversationSearch({ q, ...filters }),
          this.messageSearch({ q, ...filters }),
          this.articleSearch({ q, ...filters }),
        ]);
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.isFetching = false;
        this.uiFlags.isSearchCompleted = true;
      }
    },

    async contactSearch(payload) {
      const { page = 1, ...searchParams } = payload;
      this.uiFlags.contact = { ...this.uiFlags.contact, isFetching: true };
      try {
        const { data } = await SearchAPI.contacts({ ...searchParams, page });
        const records = data.payload.contacts;
        const existingIds = new Set(this.contactRecords.map(r => r.id));
        const newRecords = records.filter(r => !existingIds.has(r.id));
        this.contactRecords = [...this.contactRecords, ...newRecords].slice(
          -500
        );
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.contact = { ...this.uiFlags.contact, isFetching: false };
      }
    },

    async conversationSearch(payload) {
      const { page = 1, ...searchParams } = payload;
      const requestId = Date.now();
      const query =
        typeof searchParams.q === 'string' ? searchParams.q.trim() : '';

      this.lastConversationSearchRequestId = requestId;
      this.conversationSearchQuery = query;
      this.conversationSearchCompleted = false;
      this.uiFlags.conversation = {
        ...this.uiFlags.conversation,
        isFetching: true,
      };

      if (conversationSearchAbortController) {
        conversationSearchAbortController.abort();
      }
      conversationSearchAbortController = new AbortController();

      try {
        const { data } = await SearchAPI.conversations(
          { ...searchParams, page },
          { signal: conversationSearchAbortController.signal }
        );
        if (this.lastConversationSearchRequestId !== requestId) return;
        const conversations = data.payload.conversations || [];
        const contactsStore = useContactsStore();
        const enriched = conversations.map(conv => {
          const normalized = { ...conv };
          if (normalized.meta) {
            if (!normalized.contact) {
              normalized.contact =
                normalized.meta.contact || normalized.meta.sender;
            }
            if (!normalized.sender && normalized.meta.sender) {
              normalized.sender = normalized.meta.sender;
            }
            if (!normalized.last_message && normalized.meta.last_message) {
              normalized.last_message = normalized.meta.last_message;
            }
            if (
              !normalized.last_non_activity_message &&
              normalized.meta.last_non_activity_message
            ) {
              normalized.last_non_activity_message =
                normalized.meta.last_non_activity_message;
            }
            if (
              !normalized.last_activity_message &&
              normalized.meta.last_activity_message
            ) {
              normalized.last_activity_message =
                normalized.meta.last_activity_message;
            }
          }
          const contactSource =
            normalized.contact ||
            normalized.sender ||
            normalized.meta?.contact ||
            normalized.meta?.sender;
          if (contactSource) {
            normalized.contact = {
              id: contactSource.id || null,
              name: contactSource.name || contactSource.full_name || 'Unknown',
              thumbnail:
                contactSource.thumbnail ||
                contactSource.avatar_url ||
                contactSource.avatar ||
                contactSource.profile_image_url ||
                '',
              availability_status:
                contactSource.availability_status || 'offline',
              ...contactSource,
            };
            if (normalized.contact.id && !normalized.contact.thumbnail) {
              const storeContact = contactsStore.getContact?.(
                normalized.contact.id
              );
              if (storeContact?.thumbnail) {
                normalized.contact.thumbnail = storeContact.thumbnail;
              }
              if (storeContact?.name && !normalized.contact.name) {
                normalized.contact.name = storeContact.name;
              }
            }
          }
          return normalized;
        });
        if (this.lastConversationSearchRequestId === requestId) {
          this.conversationRecords = enriched || [];
        }
      } catch (error) {
        if (error?.name === 'AbortError' || error?.code === 'ERR_CANCELED')
          return;
        // Ignore error
      } finally {
        if (this.lastConversationSearchRequestId === requestId) {
          this.uiFlags.conversation = {
            ...this.uiFlags.conversation,
            isFetching: false,
          };
          this.conversationSearchCompleted = true;
        }
      }
    },

    async messageSearch(payload) {
      const { page = 1, ...searchParams } = payload;
      this.uiFlags.message = { ...this.uiFlags.message, isFetching: true };
      try {
        const { data } = await SearchAPI.messages({ ...searchParams, page });
        const records = data.payload.messages;
        const existingIds = new Set(this.messageRecords.map(r => r.id));
        const newRecords = records.filter(r => !existingIds.has(r.id));
        this.messageRecords = [...this.messageRecords, ...newRecords].slice(
          -500
        );
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.message = { ...this.uiFlags.message, isFetching: false };
      }
    },

    async messageSearchInConversation({ q, conversation_id, page = 1 }) {
      this.messageRecords = [];
      this.uiFlags.message = { ...this.uiFlags.message, isFetching: true };
      try {
        const { data } = await SearchAPI.messages({ q, page, conversation_id });
        this.messageRecords = data.payload.messages || [];
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.message = { ...this.uiFlags.message, isFetching: false };
      }
    },

    async articleSearch(payload) {
      const { page = 1, ...searchParams } = payload;
      this.uiFlags.article = { ...this.uiFlags.article, isFetching: true };
      try {
        const { data } = await SearchAPI.articles({ ...searchParams, page });
        const records = data.payload.articles;
        const existingIds = new Set(this.articleRecords.map(r => r.id));
        const newRecords = records.filter(r => !existingIds.has(r.id));
        this.articleRecords = [...this.articleRecords, ...newRecords].slice(
          -500
        );
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.article = { ...this.uiFlags.article, isFetching: false };
      }
    },

    clearSearchResults() {
      this.contactRecords = [];
      this.conversationRecords = [];
      this.lastConversationSearchRequestId = null;
      this.conversationSearchQuery = '';
      this.conversationSearchCompleted = false;
      this.messageRecords = [];
      this.articleRecords = [];
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useConversationSearchStore, import.meta.hot)
  );
}
