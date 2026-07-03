<script setup>
import { computed, onMounted, ref, h } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  useVueTable,
  createColumnHelper,
  getCoreRowModel,
  getSortedRowModel,
} from '@tanstack/vue-table';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Table from 'dashboard/components/table/Table.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import OverviewReportFilters from './OverviewReportFilters.vue';

const emit = defineEmits(['filterChange']);

const store = useStore();
const { t } = useI18n();

const from = ref(0);
const to = ref(0);
const businessHours = ref(false);

const uiFlags = useMapGetter('summaryReports/getUIFlags');
const isLoading = computed(
  () => uiFlags.value.isFetchingAgentAssignmentReports ?? false
);
const reportData = useMapGetter('summaryReports/getAgentAssignmentReports');

const columnHelper = createColumnHelper();

// Contagens: mostra o número real (incluindo 0), só cai pra '--' quando ausente.
const renderCount = value =>
  value === null || value === undefined ? '--' : Number(value).toLocaleString();

const countCell = cellProps =>
  h('span', { class: 'tabular-nums' }, renderCount(cellProps.getValue()));

// Colunas agrupadas por DIREÇÃO: "Recebidas" (o agente foi o destino, com o
// detalhamento por origem) vs "Atribuiu" (o agente atribuiu para outra pessoa).
const columns = computed(() => [
  columnHelper.accessor('name', {
    header: t('ASSIGNMENT_REPORTS.TABLE.AGENT'),
    width: 240,
    enableSorting: false,
    cell: cellProps =>
      h('span', { class: 'text-n-slate-12' }, cellProps.getValue()),
  }),
  columnHelper.group({
    id: 'received',
    header: t('ASSIGNMENT_REPORTS.TABLE.GROUP_RECEIVED'),
    columns: [
      columnHelper.accessor('receivedTotal', {
        header: t('ASSIGNMENT_REPORTS.TABLE.RECEIVED_TOTAL'),
        width: 110,
        cell: countCell,
      }),
      columnHelper.accessor('receivedManual', {
        header: t('ASSIGNMENT_REPORTS.TABLE.RECEIVED_MANUAL'),
        width: 130,
        cell: countCell,
      }),
      columnHelper.accessor('receivedAuto', {
        header: t('ASSIGNMENT_REPORTS.TABLE.RECEIVED_AUTO'),
        width: 140,
        cell: countCell,
      }),
      columnHelper.accessor('selfAssigned', {
        header: t('ASSIGNMENT_REPORTS.TABLE.SELF_ASSIGNED'),
        width: 150,
        cell: countCell,
      }),
    ],
  }),
  columnHelper.group({
    id: 'assigned',
    header: t('ASSIGNMENT_REPORTS.TABLE.GROUP_ASSIGNED'),
    columns: [
      columnHelper.accessor('assignedToOthers', {
        header: t('ASSIGNMENT_REPORTS.TABLE.ASSIGNED_TO_OTHERS'),
        width: 130,
        cell: countCell,
      }),
    ],
  }),
]);

const tableData = computed(() =>
  (reportData.value || []).map(row => ({
    id: row.id,
    name: row.name || '—',
    receivedTotal: row.receivedTotal ?? 0,
    receivedManual: row.receivedManual ?? 0,
    receivedAuto: row.receivedAuto ?? 0,
    selfAssigned: row.selfAssigned ?? 0,
    assignedToOthers: row.assignedToOthers ?? 0,
  }))
);

// Só mostra a tabela quando há atividade real (senão vira uma grade de zeros).
const hasData = computed(() =>
  (reportData.value || []).some(
    row => (row.receivedTotal ?? 0) > 0 || (row.assignedToOthers ?? 0) > 0
  )
);

// Resumo em linguagem simples (totais do time + composição em % + quem mais recebeu).
const summary = computed(() => {
  const rows = reportData.value || [];
  const acc = rows.reduce(
    (a, r) => ({
      total: a.total + (r.receivedTotal ?? 0),
      manual: a.manual + (r.receivedManual ?? 0),
      auto: a.auto + (r.receivedAuto ?? 0),
      self: a.self + (r.selfAssigned ?? 0),
    }),
    { total: 0, manual: 0, auto: 0, self: 0 }
  );
  const agents = rows.filter(
    r => (r.receivedTotal ?? 0) > 0 || (r.assignedToOthers ?? 0) > 0
  ).length;
  const top = [...rows]
    .filter(r => (r.receivedTotal ?? 0) > 0)
    .sort((a, b) => (b.receivedTotal ?? 0) - (a.receivedTotal ?? 0))[0];
  const pct = n => (acc.total ? Math.round((n / acc.total) * 100) : 0);
  return {
    total: acc.total,
    agents,
    top,
    pctManual: pct(acc.manual),
    pctAuto: pct(acc.auto),
    pctSelf: pct(acc.self),
  };
});

const table = useVueTable({
  get data() {
    return tableData.value;
  },
  get columns() {
    return columns.value;
  },
  initialState: { sorting: [{ id: 'receivedTotal', desc: true }] },
  enableSorting: true,
  getCoreRowModel: getCoreRowModel(),
  getSortedRowModel: getSortedRowModel(),
});

const fetchReports = async () => {
  const params = {
    since: from.value,
    until: to.value,
    businessHours: businessHours.value,
  };
  try {
    await store.dispatch('summaryReports/fetchAgentAssignmentReports', params);
  } catch {
    useAlert(t('REPORT.SUMMARY_FETCHING_FAILED'));
  }
};

const onFilterChange = ({
  from: fromValue,
  to: toValue,
  businessHours: bh,
}) => {
  from.value = fromValue;
  to.value = toValue;
  businessHours.value = bh;
  // Propaga pro pai (index) montar os filtros do PDF brandeado.
  emit('filterChange', { from: fromValue, to: toValue, businessHours: bh });
  fetchReports();
};

onMounted(() => fetchReports());
</script>

<template>
  <OverviewReportFilters
    :disabled="isLoading"
    @filter-change="onFilterChange"
  />

  <!-- Resumo do período (TL;DR em linguagem simples) -->
  <div
    v-if="hasData"
    class="p-4 mt-5 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
  >
    <p class="text-xs font-medium tracking-wider uppercase text-n-slate-10">
      {{ $t('ASSIGNMENT_REPORTS.SUMMARY.TITLE') }}
    </p>
    <p class="mt-1 text-sm font-medium text-n-slate-12">
      {{
        $t('ASSIGNMENT_REPORTS.SUMMARY.TOTAL', {
          total: summary.total.toLocaleString(),
          agents: summary.agents,
        })
      }}
    </p>
    <p class="mt-0.5 text-sm text-n-slate-11">
      {{
        $t('ASSIGNMENT_REPORTS.SUMMARY.COMPOSITION', {
          manual: summary.pctManual,
          auto: summary.pctAuto,
          self: summary.pctSelf,
        })
      }}
    </p>
    <p v-if="summary.top" class="mt-0.5 text-sm text-n-slate-11">
      {{
        $t('ASSIGNMENT_REPORTS.SUMMARY.TOP', {
          name: summary.top.name || '—',
          count: (summary.top.receivedTotal || 0).toLocaleString(),
        })
      }}
    </p>
    <p class="mt-2 text-xs text-n-slate-10">
      {{ $t('ASSIGNMENT_REPORTS.SUMMARY.FORWARD_ONLY') }}
    </p>
  </div>

  <!-- Tabela (ou estado vazio) -->
  <div
    class="relative flex-1 px-2 py-2 mt-5 overflow-auto shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
  >
    <Table v-if="hasData" :table="table" />
    <div
      v-else-if="!isLoading"
      class="flex flex-col items-center justify-center gap-1 py-16 text-center"
    >
      <span class="text-3xl opacity-50 i-lucide-inbox text-n-slate-10" />
      <p class="text-sm font-medium text-n-slate-12">
        {{ $t('ASSIGNMENT_REPORTS.EMPTY.TITLE') }}
      </p>
      <p class="max-w-md text-xs text-n-slate-10">
        {{ $t('ASSIGNMENT_REPORTS.EMPTY.BODY') }}
      </p>
    </div>
    <Transition
      enter-active-class="transition-opacity duration-300 ease-out"
      leave-active-class="transition-opacity duration-200 ease-in"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div
        v-if="isLoading"
        class="absolute inset-0 flex justify-center pt-[12.5rem] bg-n-solid-1/70 rounded-xl pointer-events-none"
      >
        <Spinner :size="32" class="text-n-brand" />
      </div>
    </Transition>
  </div>

  <!-- Legenda: o que significa cada coluna -->
  <div
    v-if="hasData"
    class="p-4 mt-4 outline-1 outline outline-n-container rounded-xl bg-n-solid-1"
  >
    <p class="text-xs font-medium tracking-wider uppercase text-n-slate-10">
      {{ $t('ASSIGNMENT_REPORTS.LEGEND.TITLE') }}
    </p>
    <ul class="mt-2 space-y-1 text-xs leading-relaxed text-n-slate-11">
      <li>{{ $t('ASSIGNMENT_REPORTS.LEGEND.RECEIVED') }}</li>
      <li>{{ $t('ASSIGNMENT_REPORTS.LEGEND.RECEIVED_MANUAL') }}</li>
      <li>{{ $t('ASSIGNMENT_REPORTS.LEGEND.RECEIVED_AUTO') }}</li>
      <li>{{ $t('ASSIGNMENT_REPORTS.LEGEND.SELF_ASSIGNED') }}</li>
      <li>{{ $t('ASSIGNMENT_REPORTS.LEGEND.ASSIGNED_TO_OTHERS') }}</li>
    </ul>
  </div>
</template>
