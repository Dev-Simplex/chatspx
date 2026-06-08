// KANBAN-P2-01: Pinia store dos templates pré-prontos.
// Lista oficial (locale=pt-BR + is_official) + da conta. Service `applyTemplate`
// cria 1 Kanban + N Stages a partir do template.
import { defineStore, acceptHMRUpdate } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import KanbanAPI from 'dashboard/api/kanban';

const normalize = entity =>
  entity ? camelcaseKeys(entity, { deep: true }) : entity;

export const useKanbanTemplatesStore = defineStore('kanbanTemplates', {
  state: () => ({
    templates: [],
    isFetching: false,
    isApplying: false,
  }),

  getters: {
    byVertical: state => {
      const grouped = {};
      state.templates.forEach(t => {
        const key = t.vertical || 'other';
        grouped[key] ||= [];
        grouped[key].push(t);
      });
      return grouped;
    },
    findBySlug: state => slug =>
      state.templates.find(t => t.slug === slug) || null,
  },

  actions: {
    async fetchTemplates() {
      this.isFetching = true;
      try {
        const { data } = await KanbanAPI.getTemplates();
        const list = Array.isArray(data) ? data : data?.templates || [];
        this.templates = list.map(normalize);
        return this.templates;
      } finally {
        this.isFetching = false;
      }
    },

    async applyTemplate({ templateId, options = {} }) {
      this.isApplying = true;
      try {
        const { data } = await KanbanAPI.applyTemplate(templateId, options);
        return normalize(data);
      } finally {
        this.isApplying = false;
      }
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useKanbanTemplatesStore, import.meta.hot)
  );
}
