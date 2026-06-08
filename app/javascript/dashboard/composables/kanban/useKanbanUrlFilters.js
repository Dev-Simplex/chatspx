// KANBAN-P2-04: sincroniza filtros (Pinia) ↔ querystring.
// Lê URL on mount → aplica filtros; observa filtros → atualiza URL (replace).
// Keys mapeadas:
//   q         <-> filters.query
//   labels    <-> filters.labelIds (csv)
//   assignee  <-> filters.assigneeId
//   inbox     <-> filters.inboxId
//   status    <-> filters.status
//   stages    <-> filters.stageIds (csv)
//   view      <-> viewMode

import { watch, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useKanbanFiltersStore } from 'dashboard/store/pinia/kanban/filters';

const parseCsv = v =>
  (v || '')
    .split(',')
    .map(s => Number(s))
    .filter(n => Number.isFinite(n) && n > 0);

const stringifyCsv = arr =>
  Array.isArray(arr) && arr.length ? arr.map(Number).join(',') : null;

export const useKanbanUrlFilters = () => {
  const route = useRoute();
  const router = useRouter();
  const store = useKanbanFiltersStore();

  const applyFromUrl = () => {
    const q = route.query || {};
    const patch = {};
    if (q.q != null) patch.query = String(q.q);
    if (q.labels != null) patch.labelIds = parseCsv(q.labels);
    if (q.assignee != null) patch.assigneeId = Number(q.assignee) || null;
    if (q.inbox != null) patch.inboxId = Number(q.inbox) || null;
    if (q.status != null) patch.status = String(q.status);
    if (q.stages != null) patch.stageIds = parseCsv(q.stages);
    if (Object.keys(patch).length) store.setFilters(patch);
    if (q.view && ['kanban', 'list', 'calendar'].includes(q.view)) {
      store.setViewMode(q.view);
    }
  };

  const buildQuery = () => {
    const f = store.filters || {};
    const next = { ...route.query };
    const set = (key, val) => {
      if (val == null || val === '' || val === 'all') delete next[key];
      else next[key] = String(val);
    };
    set('q', f.query);
    set('labels', stringifyCsv(f.labelIds));
    set('assignee', f.assigneeId);
    set('inbox', f.inboxId);
    set('status', f.status === 'all' ? null : f.status);
    set('stages', stringifyCsv(f.stageIds));
    set('view', store.viewMode === 'kanban' ? null : store.viewMode);
    return next;
  };

  onMounted(applyFromUrl);

  watch(
    () => [store.filters, store.viewMode],
    () => {
      const newQuery = buildQuery();
      // Evita push duplicado (compara stringified)
      const currentStr = JSON.stringify(route.query || {});
      const nextStr = JSON.stringify(newQuery);
      if (currentStr === nextStr) return;
      router.replace({ query: newQuery }).catch(() => {});
    },
    { deep: true }
  );

  return { applyFromUrl };
};
