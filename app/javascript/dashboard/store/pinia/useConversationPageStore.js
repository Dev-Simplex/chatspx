import { defineStore, acceptHMRUpdate } from 'pinia';

// Espelho Pinia de store/modules/conversationPage.js (Onda 2 P0-05).
export const useConversationPageStore = defineStore('conversationPage', {
  state: () => ({
    currentPage: { me: 0, unassigned: 0, all: 0, appliedFilters: 0 },
    nextCursor: { me: null, unassigned: null, all: null, appliedFilters: null },
    hasEndReached: {
      me: false,
      unassigned: false,
      all: false,
      appliedFilters: false,
    },
  }),

  getters: {
    getHasEndReached: state => filter => state.hasEndReached[filter],
    getCurrentPageFilter: state => filter => state.currentPage[filter],
    getNextCursor: state => filter => state.nextCursor[filter],
    getCurrentPage: state => state.currentPage,
  },

  actions: {
    setCurrentPage({ filter, page }) {
      this.currentPage = { ...this.currentPage, [filter]: page };
    },

    setNextCursor({ filter, nextCursor }) {
      this.nextCursor = { ...this.nextCursor, [filter]: nextCursor };
    },

    setEndReached({ filter }) {
      if (filter === 'all') {
        this.hasEndReached = {
          ...this.hasEndReached,
          unassigned: true,
          me: true,
        };
      }
      this.hasEndReached = { ...this.hasEndReached, [filter]: true };
    },

    reset() {
      this.currentPage = { me: 0, unassigned: 0, all: 0, appliedFilters: 0 };
      this.nextCursor = {
        me: null,
        unassigned: null,
        all: null,
        appliedFilters: null,
      };
      this.hasEndReached = {
        me: false,
        unassigned: false,
        all: false,
        appliedFilters: false,
      };
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useConversationPageStore, import.meta.hot)
  );
}
