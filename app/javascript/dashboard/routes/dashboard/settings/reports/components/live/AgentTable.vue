<script setup>
import { computed, h } from 'vue';
import {
  useVueTable,
  createColumnHelper,
  getCoreRowModel,
  getPaginationRowModel,
} from '@tanstack/vue-table';
import { useI18n } from 'vue-i18n';
import { useUISettings } from 'dashboard/composables/useUISettings';

import Spinner from 'shared/components/Spinner.vue';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';
import Table from 'dashboard/components/table/Table.vue';
import Pagination from 'dashboard/components/table/Pagination.vue';
import BaseCell from 'dashboard/components/table/BaseCell.vue';
import Thumbnail from 'dashboard/components/widgets/Thumbnail.vue';
import { useMapGetter } from 'dashboard/composables/store';

const props = defineProps({
  agents: {
    type: Array,
    default: () => [],
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();
const isRTL = useMapGetter('accounts/isRTL');

const AGENT_TABLE_PAGE_SIZE_KEY = 'live_summary_agent_table_page_size';

const getPageSize = () => {
  return uiSettings.value[AGENT_TABLE_PAGE_SIZE_KEY] || 10;
};

const handlePageSizeChange = pageSize => {
  updateUISettings({ [AGENT_TABLE_PAGE_SIZE_KEY]: pageSize });
};

const statusConfig = status => {
  const configs = {
    online: {
      label: 'Online',
      class: 'text-n-teal-11',
      dotClass: 'bg-n-teal-10',
    },
    busy: {
      label: 'Ausente',
      class: 'text-n-amber-11',
      dotClass: 'bg-n-amber-10',
    },
    offline: {
      label: 'Offline',
      class: 'text-n-slate-11',
      dotClass: 'bg-n-slate-10',
    },
  };
  return configs[status] || configs.offline;
};

const statusCell = cellProps => {
  const status = cellProps.row.original.status || 'offline';
  const config = statusConfig(status);
  return h(
    'span',
    {
      class: `flex items-center gap-1.5 px-2 py-0.5 rounded-full text-xs font-medium ${config.class}`,
    },
    [
      h('span', {
        class: `w-1.5 h-1.5 rounded-full ${config.dotClass}`,
      }),
      config.label,
    ]
  );
};

const agentCell = cellProps =>
  h(BaseCell, null, {
    default: () =>
      h(
        'div',
        {
          class: `items-center flex text-left ${
            isRTL.value ? 'flex-row-reverse' : ''
          }`,
        },
        [
          h(Thumbnail, {
            src: cellProps.row.original.thumbnail,
            size: '32px',
            username: cellProps.row.original.name,
            status: cellProps.row.original.status,
          }),
          h('div', { class: 'items-start flex flex-col min-w-0 my-0 mx-2' }, [
            h('h6', {
              class:
                'overflow-hidden text-sm m-0 leading-[1.2] text-n-slate-12 whitespace-nowrap text-ellipsis',
            }, cellProps.row.original.name),
          ]),
        ]
      ),
  });

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

const columnHelper = createColumnHelper();
const columns = [
  columnHelper.accessor('name', {
    header: t('LIVE_REPORTS.SUMMARY.AGENT_TABLE.COLUMNS.AGENT'),
    cell: agentCell,
    size: 250,
  }),
  columnHelper.accessor('department', {
    header: t('LIVE_REPORTS.SUMMARY.AGENT_TABLE.COLUMNS.DEPARTMENT'),
    cell: defaulSpanRender,
    size: 200,
  }),
  columnHelper.accessor('status', {
    header: t('LIVE_REPORTS.SUMMARY.AGENT_TABLE.COLUMNS.STATUS'),
    cell: statusCell,
    size: 150,
  }),
  columnHelper.accessor('open', {
    header: t('LIVE_REPORTS.SUMMARY.AGENT_TABLE.COLUMNS.OPEN'),
    cell: defaulSpanRender,
    size: 100,
  }),
];

const table = useVueTable({
  get data() {
    return props.agents;
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
  <div class="flex flex-col flex-1">
    <h3 class="text-lg font-medium text-n-slate-12 mb-4">
      {{ $t('LIVE_REPORTS.SUMMARY.AGENT_TABLE.HEADER') }}
    </h3>
    <div
      class="flex-1 overflow-auto px-2 py-2 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
    >
      <Table :table="table" class="max-h-[calc(100vh-21.875rem)]" />
      <Pagination
        class="mt-2"
        :table="table"
        show-page-size-selector
        :default-page-size="getPageSize()"
        @page-size-change="handlePageSizeChange"
      />
    </div>
    <div
      v-if="isLoading"
      class="items-center flex text-base justify-center p-8"
    >
      <Spinner />
      <span class="ml-2 text-n-slate-11">
        {{ $t('LIVE_REPORTS.SUMMARY.LOADING') }}
      </span>
    </div>
    <EmptyState
      v-else-if="!isLoading && !agents.length"
      :title="$t('LIVE_REPORTS.SUMMARY.AGENT_TABLE.NO_AGENTS')"
    />
  </div>
</template>

