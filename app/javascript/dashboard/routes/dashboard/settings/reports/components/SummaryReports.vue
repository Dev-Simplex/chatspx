<script setup>
import OverviewReportFilters from './OverviewReportFilters.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { formatTime } from '@chatwoot/utils';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useReportNarrative } from 'dashboard/composables/useReportNarrative';
import ReportNarrativeSummary from './ReportNarrativeSummary.vue';
import Table from 'dashboard/components/table/Table.vue';
import { generateFileName } from 'dashboard/helper/downloadHelper';
import {
  useVueTable,
  createColumnHelper,
  getCoreRowModel,
} from '@tanstack/vue-table';
import { computed, onMounted, ref, h } from 'vue';

const props = defineProps({
  type: {
    type: String,
    default: 'account',
  },
  getterKey: {
    type: String,
    default: '',
  },
  actionKey: {
    type: String,
    default: '',
  },
  summaryKey: {
    type: String,
    default: '',
  },
  fetchItemsKey: {
    type: String,
    required: true,
  },
});

const emit = defineEmits(['filterChange']);

const store = useStore();

const from = ref(0);
const to = ref(0);
const businessHours = ref(false);
const inboxId = ref(null);
import { useI18n } from 'vue-i18n';
import SummaryReportLink from './SummaryReportLink.vue';

const flagMap = {
  agent: 'isFetchingAgentSummaryReports',
  inbox: 'isFetchingInboxSummaryReports',
  team: 'isFetchingTeamSummaryReports',
  label: 'isFetchingLabelSummaryReports',
};

const uiFlags = useMapGetter('summaryReports/getUIFlags');
const isLoading = computed(() => uiFlags.value[flagMap[props.type]] ?? false);

const rowItems = useMapGetter([props.getterKey]) || [];
const reportMetrics = useMapGetter([props.summaryKey]) || [];

const getMetrics = id =>
  reportMetrics.value.find(metrics => metrics.id === Number(id)) || {};
const columnHelper = createColumnHelper();
const { t } = useI18n();

const { signalByMetric, dotClassFor, aggregateSignals } = useReportNarrative();

// TL;DR da média: agrega os signals de todas as entidades por métrica.
const aggregatedSignals = computed(() =>
  aggregateSignals((reportMetrics.value || []).map(row => row.signals || []))
);

const defaulSpanRender = cellProps =>
  h(
    'span',
    {
      class: cellProps.getValue() ? '' : 'text-n-slate-12',
    },
    cellProps.getValue()
  );

// Célula de métrica com pontinho de semáforo (cor do nível) antes do valor.
const metricCell = metricKey => cellProps => {
  const value = cellProps.getValue();
  const signal = cellProps.row.original.signalsByMetric?.[metricKey] || null;
  const dot = dotClassFor(signal);
  return h('span', { class: 'inline-flex items-center gap-1.5' }, [
    dot && h('span', { class: `inline-block w-2 h-2 rounded-full ${dot}` }),
    h('span', { class: value ? '' : 'text-n-slate-12' }, value),
  ]);
};

const columns = computed(() => [
  columnHelper.accessor('name', {
    header: t(`SUMMARY_REPORTS.${props.type.toUpperCase()}`),
    width: 300,
    cell: cellProps => h(SummaryReportLink, cellProps),
  }),
  columnHelper.accessor('conversationsCount', {
    header: t('SUMMARY_REPORTS.CONVERSATIONS'),
    width: 200,
    cell: defaulSpanRender,
  }),
  columnHelper.accessor('avgFirstResponseTime', {
    header: t('SUMMARY_REPORTS.AVG_FIRST_RESPONSE_TIME'),
    width: 200,
    cell: metricCell('first_response'),
  }),
  ...(props.type !== 'label'
    ? [
        columnHelper.accessor('avgFirstResponseTimeAfterAssignment', {
          header: t('SUMMARY_REPORTS.AVG_FIRST_RESPONSE_TIME_AFTER_TRANSFER'),
          width: 240,
          cell: defaulSpanRender,
        }),
      ]
    : []),
  columnHelper.accessor('avgResolutionTime', {
    header: t('SUMMARY_REPORTS.AVG_RESOLUTION_TIME'),
    width: 200,
    cell: metricCell('resolution'),
  }),
  columnHelper.accessor('avgReplyTime', {
    header: t('SUMMARY_REPORTS.AVG_REPLY_TIME'),
    width: 200,
    cell: metricCell('reply'),
  }),
  columnHelper.accessor('resolutionsCount', {
    header: t('SUMMARY_REPORTS.RESOLUTION_COUNT'),
    width: 200,
    cell: metricCell('resolution_rate'),
  }),
]);

const renderAvgTime = value => (value ? formatTime(value) : '--');

const renderCount = value => (value ? value.toLocaleString() : '--');

const tableData = computed(() =>
  rowItems.value.map(row => {
    const rowMetrics = getMetrics(row.id);
    const {
      conversationsCount,
      avgFirstResponseTime,
      avgFirstResponseTimeAfterAssignment,
      avgResolutionTime,
      avgReplyTime,
      resolvedConversationsCount,
      signals,
    } = rowMetrics;
    return {
      id: row.id,
      // we fallback on title, label for instance does not have a name property
      name: row.name ?? row.title,
      type: props.type,
      conversationsCount: renderCount(conversationsCount),
      avgFirstResponseTime: renderAvgTime(avgFirstResponseTime),
      avgFirstResponseTimeAfterAssignment: renderAvgTime(
        avgFirstResponseTimeAfterAssignment
      ),
      avgReplyTime: renderAvgTime(avgReplyTime),
      avgResolutionTime: renderAvgTime(avgResolutionTime),
      resolutionsCount: renderCount(resolvedConversationsCount),
      signalsByMetric: {
        first_response: signalByMetric(signals, 'first_response'),
        resolution: signalByMetric(signals, 'resolution'),
        reply: signalByMetric(signals, 'reply'),
        resolution_rate: signalByMetric(signals, 'resolution_rate'),
      },
    };
  })
);

const fetchReportsWithRetry = async () => {
  const params = {
    since: from.value,
    until: to.value,
    businessHours: businessHours.value,
    inboxId: inboxId.value,
  };
  try {
    await store.dispatch(props.actionKey, params);
  } catch {
    try {
      await store.dispatch(props.actionKey, params);
    } catch {
      useAlert(t('REPORT.SUMMARY_FETCHING_FAILED'));
    }
  }
};

const fetchAllData = () => {
  store.dispatch(props.fetchItemsKey);
  fetchReportsWithRetry();
};

onMounted(() => fetchAllData());

const onFilterChange = updatedFilter => {
  from.value = updatedFilter.from;
  to.value = updatedFilter.to;
  businessHours.value = updatedFilter.businessHours;
  inboxId.value = updatedFilter.inboxId || null;
  emit('filterChange', {
    from: from.value,
    to: to.value,
    businessHours: businessHours.value,
    inboxId: inboxId.value,
  });
  fetchAllData();
};

const table = useVueTable({
  get data() {
    return tableData.value;
  },
  get columns() {
    return columns.value;
  },
  enableSorting: false,
  getCoreRowModel: getCoreRowModel(),
});

// downloadReports method is not used in this component
// but it is exposed to be used in the parent component
const downloadReports = () => {
  const dispatchMethods = {
    agent: 'downloadAgentReports',
    label: 'downloadLabelReports',
    inbox: 'downloadInboxReports',
    team: 'downloadTeamReports',
  };
  if (dispatchMethods[props.type]) {
    const fileName = generateFileName({
      type: props.type,
      to: to.value,
      businessHours: businessHours.value,
    });
    const params = {
      from: from.value,
      to: to.value,
      fileName,
      businessHours: businessHours.value,
      inboxId: inboxId.value,
    };
    store.dispatch(dispatchMethods[props.type], params);
  }
};

defineExpose({ downloadReports });
</script>

<template>
  <OverviewReportFilters
    :disabled="isLoading"
    :show-inbox-scope="type !== 'inbox'"
    @filter-change="onFilterChange"
  />
  <ReportNarrativeSummary :signals="aggregatedSignals" />
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
