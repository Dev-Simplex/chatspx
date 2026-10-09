<script setup>
import { computed, h, ref } from 'vue';
import {
  useVueTable,
  createColumnHelper,
  getCoreRowModel,
  getPaginationRowModel,
} from '@tanstack/vue-table';
import { useI18n } from 'vue-i18n';
import ReportDrilldownPanel from 'dashboard/components-next/reports/ReportDrilldownPanel.vue';
import { useUISettings } from 'dashboard/composables/useUISettings';

import Spinner from 'shared/components/Spinner.vue';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';
import Table from 'dashboard/components/table/Table.vue';
import Pagination from 'dashboard/components/table/Pagination.vue';

const props = defineProps({
  teams: {
    type: Array,
    default: () => [],
  },
  teamMetrics: {
    type: Array,
    default: () => [],
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  inboxId: {
    type: [Number, String],
    default: null,
  },
});

const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();

// UI Settings key for team table page size
const TEAM_TABLE_PAGE_SIZE_KEY = 'report_overview_team_table_page_size';

// Get the saved page size from UI settings or default to 10
const getPageSize = () => {
  return uiSettings.value[TEAM_TABLE_PAGE_SIZE_KEY] || 10;
};

const handlePageSizeChange = pageSize => {
  updateUISettings({ [TEAM_TABLE_PAGE_SIZE_KEY]: pageSize });
};

const getTeamMetrics = id =>
  props.teamMetrics.find(metrics => metrics.team_id === Number(id)) || {};

const tableData = computed(() =>
  props.teams
    .map(team => {
      const metric = getTeamMetrics(team.id);
      return {
        id: team.id,
        agent: team.name,
        open: metric.open || 0,
        unattended: metric.unattended || 0,
      };
    })
    .sort((a, b) => {
      // First sort by open tickets (descending)
      const openDiff = b.open - a.open;
      // If open tickets are equal, sort by name (ascending)
      if (openDiff === 0) {
        return a.agent.localeCompare(b.agent);
      }
      return openDiff;
    })
);

const defaulSpanRender = cellProps =>
  h(
    'span',
    {
      class: cellProps.getValue()
        ? 'capitalize text-n-slate-12'
        : 'capitalize text-n-slate-11',
    },
    cellProps.getValue() ? cellProps.getValue() : '---'
  );

// Abertas e nao atendidas de cada linha abrem as conversas (ReportDrilldownPanel ao vivo).
const drilldown = ref(null);
const liveCell = (metric, headerKey) => cellProps => {
  const value = cellProps.getValue();
  if (!value) return h('span', { class: 'text-n-slate-11' }, '---');
  const row = cellProps.row.original;
  return h(
    'button',
    {
      type: 'button',
      class:
        'p-0 m-0 text-[length:inherit] tabular-nums text-n-slate-12 underline decoration-dotted underline-offset-4 hover:text-n-brand',
      title: t('REPORT.DRILLDOWN.OPEN'),
      onClick: () => {
        drilldown.value = {
          metric: { key: metric, name: `${row.agent} · ${t(headerKey)}` },
          filters: { teamId: row.id, inboxId: props.inboxId },
        };
      },
    },
    value
  );
};

const columnHelper = createColumnHelper();
const columns = [
  columnHelper.accessor('agent', {
    header: t('OVERVIEW_REPORTS.TEAM_CONVERSATIONS.TABLE_HEADER.TEAM'),
    cell: defaulSpanRender,
    size: 250,
  }),
  columnHelper.accessor('open', {
    header: t('OVERVIEW_REPORTS.TEAM_CONVERSATIONS.TABLE_HEADER.OPEN'),
    cell: liveCell(
      'open',
      'OVERVIEW_REPORTS.TEAM_CONVERSATIONS.TABLE_HEADER.OPEN'
    ),
    size: 100,
  }),
  columnHelper.accessor('unattended', {
    header: t('OVERVIEW_REPORTS.TEAM_CONVERSATIONS.TABLE_HEADER.UNATTENDED'),
    cell: liveCell(
      'unattended',
      'OVERVIEW_REPORTS.TEAM_CONVERSATIONS.TABLE_HEADER.UNATTENDED'
    ),
    size: 100,
  }),
];

const table = useVueTable({
  get data() {
    return tableData.value;
  },
  columns,
  enableSorting: false,
  getCoreRowModel: getCoreRowModel(),
  getPaginationRowModel: getPaginationRowModel(),
  initialState: {
    pagination: {
      pageSize: getPageSize(),
    },
  },
});
</script>

<template>
  <div
    class="flex flex-col flex-1 relative hover:z-30 focus-within:z-30 rounded-[22px] border border-n-weak bg-n-solid-2/80 backdrop-blur-xl shadow-[inset_0_1px_0_rgb(255_255_255/0.7),0_14px_36px_rgb(16_24_40/0.08)] dark:shadow-[inset_0_1px_0_rgb(255_255_255/0.06),0_14px_36px_rgb(0_0_0/0.4)] overflow-hidden"
  >
    <Table
      :table="table"
      type="reports"
      class="max-h-[calc(100vh-21.875rem)]"
    />
    <Pagination
      class="px-4 py-3 border-t border-n-weak"
      :table="table"
      show-page-size-selector
      :default-page-size="getPageSize()"
      @page-size-change="handlePageSizeChange"
    />
    <div
      v-if="isLoading"
      class="items-center flex text-base justify-center p-8"
    >
      <Spinner />
      <span>
        {{ $t('OVERVIEW_REPORTS.TEAM_CONVERSATIONS.LOADING_MESSAGE') }}
      </span>
    </div>
    <EmptyState
      v-else-if="!isLoading && !teams.length"
      :title="$t('OVERVIEW_REPORTS.TEAM_CONVERSATIONS.NO_TEAMS')"
    />
    <ReportDrilldownPanel
      v-if="drilldown"
      :metric="drilldown.metric"
      :filters="drilldown.filters"
      source="live"
      @close="drilldown = null"
    />
  </div>
</template>
