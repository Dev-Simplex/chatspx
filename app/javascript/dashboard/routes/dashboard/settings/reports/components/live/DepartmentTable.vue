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

const props = defineProps({
  departments: {
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

const DEPARTMENT_TABLE_PAGE_SIZE_KEY = 'live_summary_department_table_page_size';

const getPageSize = () => {
  return uiSettings.value[DEPARTMENT_TABLE_PAGE_SIZE_KEY] || 10;
};

const handlePageSizeChange = pageSize => {
  updateUISettings({ [DEPARTMENT_TABLE_PAGE_SIZE_KEY]: pageSize });
};

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
    header: t('LIVE_REPORTS.SUMMARY.DEPARTMENT_TABLE.COLUMNS.DEPARTMENT'),
    cell: defaulSpanRender,
    size: 250,
  }),
  columnHelper.accessor('online', {
    header: t('LIVE_REPORTS.SUMMARY.DEPARTMENT_TABLE.COLUMNS.ONLINE'),
    cell: defaulSpanRender,
    size: 100,
  }),
  columnHelper.accessor('offline', {
    header: t('LIVE_REPORTS.SUMMARY.DEPARTMENT_TABLE.COLUMNS.OFFLINE'),
    cell: defaulSpanRender,
    size: 100,
  }),
  columnHelper.accessor('absent', {
    header: t('LIVE_REPORTS.SUMMARY.DEPARTMENT_TABLE.COLUMNS.ABSENT'),
    cell: defaulSpanRender,
    size: 100,
  }),
  columnHelper.accessor('inQueue', {
    header: t('LIVE_REPORTS.SUMMARY.DEPARTMENT_TABLE.COLUMNS.IN_QUEUE'),
    cell: defaulSpanRender,
    size: 100,
  }),
  columnHelper.accessor('open', {
    header: t('LIVE_REPORTS.SUMMARY.DEPARTMENT_TABLE.COLUMNS.OPEN'),
    cell: defaulSpanRender,
    size: 100,
  }),
];

const table = useVueTable({
  get data() {
    return props.departments;
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
      {{ $t('LIVE_REPORTS.SUMMARY.DEPARTMENT_TABLE.HEADER') }}
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
      v-else-if="!isLoading && !departments.length"
      :title="$t('LIVE_REPORTS.SUMMARY.DEPARTMENT_TABLE.NO_DEPARTMENTS')"
    />
  </div>
</template>

