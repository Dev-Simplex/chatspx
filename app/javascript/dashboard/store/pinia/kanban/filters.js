// Pinia store de filtros + view do Kanban (P1-04).
// Persistido em localStorage via piniaPluginPersistedstate.
// viewMode (kanban/list/agenda) e filtros locais (search, assignee, etc.).

import { defineStore, acceptHMRUpdate } from 'pinia';

export const useKanbanFiltersStore = defineStore('kanbanFilters', {
  state: () => ({
    viewMode: 'kanban', // 'kanban' | 'list' | 'calendar'
    filters: {
      query: '',
      stageIds: [],
      labelIds: [],
      assigneeId: null,
      status: 'all',
      inboxId: null,
    },
    filtersOpen: false,
  }),

  getters: {
    hasActiveFilters: state => {
      const f = state.filters;
      return Boolean(
        (f.query && f.query.trim().length) ||
          (Array.isArray(f.stageIds) && f.stageIds.length) ||
          (Array.isArray(f.labelIds) && f.labelIds.length) ||
          f.assigneeId ||
          (f.status && f.status !== 'all') ||
          f.inboxId
      );
    },
  },

  actions: {
    setViewMode(mode) {
      if (['kanban', 'list', 'calendar'].includes(mode)) this.viewMode = mode;
    },
    setFilter(key, value) {
      this.filters = { ...this.filters, [key]: value };
    },
    setFilters(patch) {
      this.filters = { ...this.filters, ...patch };
    },
    resetFilters() {
      this.filters = {
        query: '',
        stageIds: [],
        labelIds: [],
        assigneeId: null,
        status: 'all',
        inboxId: null,
      };
    },
    openFilters() {
      this.filtersOpen = true;
    },
    closeFilters() {
      this.filtersOpen = false;
    },
    toggleFilters() {
      this.filtersOpen = !this.filtersOpen;
    },
  },

  persist: {
    key: 'chatspx:kanban:filters',
    paths: ['viewMode', 'filters'],
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useKanbanFiltersStore, import.meta.hot)
  );
}
