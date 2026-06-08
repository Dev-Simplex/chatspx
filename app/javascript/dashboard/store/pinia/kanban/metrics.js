// KANBAN-P2-05: métricas do board (cache 60s no backend).
// 4 números: total, valor pipeline (cents), aging médio, win rate.
import { defineStore, acceptHMRUpdate } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import KanbanAPI from 'dashboard/api/kanban';

const normalize = entity =>
  entity ? camelcaseKeys(entity, { deep: true }) : entity;

export const useKanbanMetricsStore = defineStore('kanbanMetrics', {
  state: () => ({
    byKanban: {}, // { [kanbanId]: { total, activeTotal, pipelineValueCents, averageAgingDays, winRate, generatedAt } }
    isFetching: {}, // { [kanbanId]: bool }
  }),

  getters: {
    metricsOf: state => kanbanId => state.byKanban[kanbanId] || null,
  },

  actions: {
    async fetchMetrics(kanbanId, { force = false } = {}) {
      if (!kanbanId) return null;
      const id = Number(kanbanId);
      if (this.isFetching[id]) return this.byKanban[id] || null;
      const cached = this.byKanban[id];
      if (
        !force &&
        cached &&
        Date.now() - new Date(cached.generatedAt).getTime() < 30000
      ) {
        return cached;
      }
      this.isFetching[id] = true;
      try {
        const { data } = await KanbanAPI.getMetrics(id);
        this.byKanban[id] = normalize(data);
        return this.byKanban[id];
      } finally {
        this.isFetching[id] = false;
      }
    },

    invalidate(kanbanId) {
      const id = Number(kanbanId);
      delete this.byKanban[id];
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useKanbanMetricsStore, import.meta.hot)
  );
}
