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
const teamId = ref('');
const inboxId = ref('');

const uiFlags = useMapGetter('summaryReports/getUIFlags');
const isLoading = computed(
  () => uiFlags.value.isFetchingAgentAssignmentReports ?? false
);
const reportData = useMapGetter('summaryReports/getAgentAssignmentReports');
const teams = useMapGetter('teams/getTeams');
const inboxes = useMapGetter('inboxes/getInboxes');

// A resposta agora é { rows, matrix }.
const rows = computed(() => reportData.value?.rows || []);
const matrixData = computed(() => reportData.value?.matrix || []);

const columnHelper = createColumnHelper();

// Contagens: mostra o número real (incluindo 0), só cai pra '--' quando ausente.
const renderCount = value =>
  value === null || value === undefined ? '--' : Number(value).toLocaleString();

const countCell = cellProps =>
  h('span', { class: 'tabular-nums' }, renderCount(cellProps.getValue()));

// Resumo curto exibido no tooltip de cada cabeçalho (reusa a legenda).
const tip = key => t(`ASSIGNMENT_REPORTS.LEGEND.${key}`);

// Colunas agrupadas por DIREÇÃO: "Recebidas" (o agente foi o destino, com o
// detalhamento por origem) vs "Atribuiu" (o agente atribuiu para outra pessoa).
// meta.tooltip → o Table.vue mostra um resumo ao passar o mouse no cabeçalho.
const columns = computed(() => [
  columnHelper.accessor('name', {
    header: t('ASSIGNMENT_REPORTS.TABLE.AGENT'),
    width: 240,
    enableSorting: false,
    meta: { tooltip: tip('AGENT') },
    cell: cellProps =>
      h('span', { class: 'text-n-slate-12' }, cellProps.getValue()),
  }),
  columnHelper.group({
    id: 'received',
    header: t('ASSIGNMENT_REPORTS.TABLE.GROUP_RECEIVED'),
    meta: { tooltip: tip('RECEIVED') },
    columns: [
      columnHelper.accessor('receivedTotal', {
        header: t('ASSIGNMENT_REPORTS.TABLE.RECEIVED_TOTAL'),
        width: 110,
        meta: { tooltip: tip('RECEIVED') },
        cell: countCell,
      }),
      columnHelper.accessor('receivedManual', {
        header: t('ASSIGNMENT_REPORTS.TABLE.RECEIVED_MANUAL'),
        width: 130,
        meta: { tooltip: tip('RECEIVED_MANUAL') },
        cell: countCell,
      }),
      columnHelper.accessor('receivedAuto', {
        header: t('ASSIGNMENT_REPORTS.TABLE.RECEIVED_AUTO'),
        width: 140,
        meta: { tooltip: tip('RECEIVED_AUTO') },
        cell: countCell,
      }),
      columnHelper.accessor('selfAssigned', {
        header: t('ASSIGNMENT_REPORTS.TABLE.SELF_ASSIGNED'),
        width: 150,
        meta: { tooltip: tip('SELF_ASSIGNED') },
        cell: countCell,
      }),
    ],
  }),
  columnHelper.group({
    id: 'assigned',
    header: t('ASSIGNMENT_REPORTS.TABLE.GROUP_ASSIGNED'),
    meta: { tooltip: tip('ASSIGNED_TO_OTHERS') },
    columns: [
      columnHelper.accessor('assignedToOthers', {
        header: t('ASSIGNMENT_REPORTS.TABLE.ASSIGNED_TO_OTHERS'),
        width: 130,
        meta: { tooltip: tip('ASSIGNED_TO_OTHERS') },
        cell: countCell,
      }),
    ],
  }),
]);

const tableData = computed(() =>
  rows.value.map(row => ({
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
  rows.value.some(
    row => (row.receivedTotal ?? 0) > 0 || (row.assignedToOthers ?? 0) > 0
  )
);

// Resumo em linguagem simples (totais do time + composição em % + quem mais recebeu).
const summary = computed(() => {
  const acc = rows.value.reduce(
    (a, r) => ({
      total: a.total + (r.receivedTotal ?? 0),
      manual: a.manual + (r.receivedManual ?? 0),
      auto: a.auto + (r.receivedAuto ?? 0),
      self: a.self + (r.selfAssigned ?? 0),
    }),
    { total: 0, manual: 0, auto: 0, self: 0 }
  );
  const agents = rows.value.filter(
    r => (r.receivedTotal ?? 0) > 0 || (r.assignedToOthers ?? 0) > 0
  ).length;
  const top = [...rows.value]
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

// Matriz "quem atribuiu pra quem": deriva os eixos (autores × destinos) e um
// mapa de células a partir dos pares vindos do backend.
const matrixAxes = computed(() => {
  const authors = new Map();
  const dests = new Map();
  const cells = {};
  matrixData.value.forEach(p => {
    authors.set(p.fromId, p.fromName);
    dests.set(p.toId, p.toName);
    cells[`${p.fromId}-${p.toId}`] = p.count;
  });
  return {
    authors: [...authors].map(([id, name]) => ({ id, name })),
    dests: [...dests].map(([id, name]) => ({ id, name })),
    cells,
  };
});
const hasMatrix = computed(() => matrixData.value.length > 0);
const cellCount = (fromId, toId) =>
  matrixAxes.value.cells[`${fromId}-${toId}`] || 0;

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
  try {
    await store.dispatch('summaryReports/fetchAgentAssignmentReports', {
      since: from.value,
      until: to.value,
      businessHours: businessHours.value,
      teamId: teamId.value || undefined,
      inboxId: inboxId.value || undefined,
    });
  } catch {
    useAlert(t('REPORT.SUMMARY_FETCHING_FAILED'));
  }
};

// Propaga todos os filtros pro pai (index) montar os filtros do PDF brandeado.
const emitFilters = () => {
  emit('filterChange', {
    from: from.value,
    to: to.value,
    businessHours: businessHours.value,
    teamId: teamId.value || undefined,
    inboxId: inboxId.value || undefined,
  });
};

const onFilterChange = ({ from: f, to: t2, businessHours: bh }) => {
  from.value = f;
  to.value = t2;
  businessHours.value = bh;
  emitFilters();
  fetchReports();
};

// Time/inbox mudou → re-busca com o mesmo período.
const onScopeChange = () => {
  emitFilters();
  fetchReports();
};

onMounted(() => {
  store.dispatch('teams/get');
  store.dispatch('inboxes/get');
});
</script>

<template>
  <OverviewReportFilters
    :disabled="isLoading"
    @filter-change="onFilterChange"
  />

  <!-- Filtros de recorte: time e inbox -->
  <div class="flex flex-wrap items-center gap-4 -mt-2">
    <label class="flex items-center gap-2 text-sm text-n-slate-11">
      {{ $t('ASSIGNMENT_REPORTS.FILTER.TEAM') }}
      <select
        v-model="teamId"
        class="reset-base h-9 mb-0 px-2 text-sm border rounded-lg outline-none cursor-pointer bg-n-alpha-1 border-transparent focus:border-n-brand text-n-slate-12"
        @change="onScopeChange"
      >
        <option value="">
          {{ $t('ASSIGNMENT_REPORTS.FILTER.ALL_TEAMS') }}
        </option>
        <option v-for="team in teams" :key="team.id" :value="team.id">
          {{ team.name }}
        </option>
      </select>
    </label>
    <label class="flex items-center gap-2 text-sm text-n-slate-11">
      {{ $t('ASSIGNMENT_REPORTS.FILTER.INBOX') }}
      <select
        v-model="inboxId"
        class="reset-base h-9 mb-0 px-2 text-sm border rounded-lg outline-none cursor-pointer bg-n-alpha-1 border-transparent focus:border-n-brand text-n-slate-12"
        @change="onScopeChange"
      >
        <option value="">
          {{ $t('ASSIGNMENT_REPORTS.FILTER.ALL_INBOXES') }}
        </option>
        <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
          {{ inbox.name }}
        </option>
      </select>
    </label>
  </div>

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

  <!-- Matriz: quem atribuiu pra quem -->
  <div
    v-if="hasMatrix"
    class="p-4 mt-4 outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
  >
    <p class="text-xs font-medium tracking-wider uppercase text-n-slate-10">
      {{ $t('ASSIGNMENT_REPORTS.MATRIX.TITLE') }}
    </p>
    <p class="mt-1 mb-3 text-xs text-n-slate-10">
      {{ $t('ASSIGNMENT_REPORTS.MATRIX.HINT') }}
    </p>
    <div class="overflow-auto">
      <table class="text-sm border-collapse">
        <thead>
          <tr>
            <th
              class="sticky left-0 px-3 py-2 text-xs font-semibold text-left border-b border-n-weak text-n-slate-10 bg-n-solid-2"
            >
              {{ $t('ASSIGNMENT_REPORTS.MATRIX.FROM_TO') }}
            </th>
            <th
              v-for="d in matrixAxes.dests"
              :key="d.id"
              class="px-3 py-2 text-xs font-medium capitalize border-b border-n-weak text-n-slate-11 whitespace-nowrap"
            >
              {{ d.name }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="a in matrixAxes.authors" :key="a.id">
            <th
              class="sticky left-0 px-3 py-2 text-xs font-medium text-left capitalize border-b border-n-weak text-n-slate-12 bg-n-solid-2 whitespace-nowrap"
            >
              {{ a.name }}
            </th>
            <td
              v-for="d in matrixAxes.dests"
              :key="d.id"
              class="px-3 py-2 text-center border-b border-n-weak tabular-nums"
              :class="
                cellCount(a.id, d.id)
                  ? 'text-n-slate-12 font-medium'
                  : 'text-n-slate-9'
              "
            >
              {{ cellCount(a.id, d.id) || '·' }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
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
