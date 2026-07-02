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
import {
  downloadCsvFile,
  generateFileName,
} from 'dashboard/helper/downloadHelper';
import Table from 'dashboard/components/table/Table.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import OverviewReportFilters from './OverviewReportFilters.vue';

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

// A célula formata pra exibição; o valor cru (número) fica no acessor pra ordenação numérica.
const countCell = cellProps =>
  h('span', { class: 'tabular-nums' }, renderCount(cellProps.getValue()));

const columns = computed(() => [
  columnHelper.accessor('name', {
    header: t('ASSIGNMENT_REPORTS.TABLE.AGENT'),
    width: 260,
    enableSorting: false,
    cell: cellProps =>
      h('span', { class: 'text-n-slate-12' }, cellProps.getValue()),
  }),
  columnHelper.accessor('receivedTotal', {
    header: t('ASSIGNMENT_REPORTS.TABLE.RECEIVED_TOTAL'),
    width: 150,
    cell: countCell,
  }),
  columnHelper.accessor('receivedManual', {
    header: t('ASSIGNMENT_REPORTS.TABLE.RECEIVED_MANUAL'),
    width: 150,
    cell: countCell,
  }),
  columnHelper.accessor('receivedAuto', {
    header: t('ASSIGNMENT_REPORTS.TABLE.RECEIVED_AUTO'),
    width: 150,
    cell: countCell,
  }),
  columnHelper.accessor('selfAssigned', {
    header: t('ASSIGNMENT_REPORTS.TABLE.SELF_ASSIGNED'),
    width: 160,
    cell: countCell,
  }),
  columnHelper.accessor('assignedToOthers', {
    header: t('ASSIGNMENT_REPORTS.TABLE.ASSIGNED_TO_OTHERS'),
    width: 170,
    cell: countCell,
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
  fetchReports();
};

onMounted(() => fetchReports());

// CSV a partir do JSON já carregado (números brutos, sem formatação de exibição).
const csvEscape = value => `"${String(value ?? '').replace(/"/g, '""')}"`;

const downloadReports = () => {
  const rows = reportData.value || [];
  const header = [
    t('ASSIGNMENT_REPORTS.TABLE.AGENT'),
    t('ASSIGNMENT_REPORTS.TABLE.RECEIVED_TOTAL'),
    t('ASSIGNMENT_REPORTS.TABLE.RECEIVED_MANUAL'),
    t('ASSIGNMENT_REPORTS.TABLE.RECEIVED_AUTO'),
    t('ASSIGNMENT_REPORTS.TABLE.SELF_ASSIGNED'),
    t('ASSIGNMENT_REPORTS.TABLE.ASSIGNED_TO_OTHERS'),
  ];
  const body = rows.map(row => [
    row.name,
    row.receivedTotal ?? 0,
    row.receivedManual ?? 0,
    row.receivedAuto ?? 0,
    row.selfAssigned ?? 0,
    row.assignedToOthers ?? 0,
  ]);
  const csv = [header, ...body]
    .map(line => line.map(csvEscape).join(','))
    .join('\n');
  const fileName = generateFileName({
    type: 'agent-assignment',
    to: to.value,
    businessHours: businessHours.value,
  });
  downloadCsvFile(fileName, csv);
};

defineExpose({ downloadReports });
</script>

<template>
  <OverviewReportFilters
    :disabled="isLoading"
    @filter-change="onFilterChange"
  />
  <div
    class="relative flex-1 overflow-auto px-2 py-2 mt-5 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
  >
    <Table :table="table" />
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
</template>
