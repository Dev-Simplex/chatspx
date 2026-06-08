// KANBAN-P2-04: views salvas (pessoais) por kanban+user.
// CRUD via API + estado local. MVP: somente views pessoais.
import { defineStore, acceptHMRUpdate } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import KanbanAPI from 'dashboard/api/kanban';

const normalize = entity =>
  entity ? camelcaseKeys(entity, { deep: true }) : entity;

export const useKanbanViewsStore = defineStore('kanbanViews', {
  state: () => ({
    byKanban: {}, // { [kanbanId]: KanbanView[] }
    isFetching: {},
    isSaving: false,
  }),

  getters: {
    viewsOf: state => kanbanId => state.byKanban[Number(kanbanId)] || [],
  },

  actions: {
    async fetchViews(kanbanId) {
      if (!kanbanId) return [];
      const id = Number(kanbanId);
      this.isFetching[id] = true;
      try {
        const { data } = await KanbanAPI.getSavedViews(id);
        const list = Array.isArray(data) ? data : data?.views || [];
        this.byKanban[id] = list.map(normalize);
        return this.byKanban[id];
      } finally {
        this.isFetching[id] = false;
      }
    },

    async createView({ kanbanId, name, filters, sort, settings }) {
      if (!kanbanId || !name) return null;
      const id = Number(kanbanId);
      this.isSaving = true;
      try {
        const { data } = await KanbanAPI.createSavedView(id, {
          name,
          filters: filters || {},
          sort: sort || { by: 'last_activity_at', dir: 'desc' },
          settings: settings || {},
        });
        const view = normalize(data);
        const list = this.byKanban[id] || [];
        this.byKanban[id] = [...list, view];
        return view;
      } finally {
        this.isSaving = false;
      }
    },

    async updateView({ kanbanId, viewId, patch }) {
      const id = Number(kanbanId);
      const { data } = await KanbanAPI.updateSavedView(id, viewId, patch);
      const view = normalize(data);
      const list = this.byKanban[id] || [];
      this.byKanban[id] = list.map(v => (v.id === view.id ? view : v));
      return view;
    },

    async deleteView({ kanbanId, viewId }) {
      const id = Number(kanbanId);
      await KanbanAPI.deleteSavedView(id, viewId);
      const list = this.byKanban[id] || [];
      this.byKanban[id] = list.filter(v => v.id !== viewId);
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useKanbanViewsStore, import.meta.hot));
}
