<script setup>
import { FlexRender } from '@tanstack/vue-table';
import SortButton from './SortButton.vue';
import { computed } from 'vue';

const props = defineProps({
  table: {
    type: Object,
    required: true,
  },
  fixed: {
    type: Boolean,
    default: false,
  },
  type: {
    type: String,
    default: 'relaxed',
  },
});

const isRelaxed = computed(() => props.type === 'relaxed');
const isReports = computed(() => props.type === 'reports');
const headerClass = computed(() =>
  isRelaxed.value
    ? 'ltr:first:rounded-bl-lg ltr:first:rounded-tl-lg ltr:last:rounded-br-lg ltr:last:rounded-tr-lg rtl:first:rounded-br-lg rtl:first:rounded-tr-lg rtl:last:rounded-bl-lg rtl:last:rounded-tl-lg'
    : ''
);
const headerRowClass = computed(() =>
  isReports.value ? 'bg-n-slate-2/50 dark:bg-n-solid-3' : 'bg-n-slate-1'
);
const rowClass = computed(() =>
  isReports.value
    ? 'border-t border-n-weak/30 hover:bg-n-slate-3/30 transition-colors'
    : ''
);
const cellClass = computed(() =>
  isReports.value ? 'px-4 py-3 text-sm text-n-slate-12' : ''
);
</script>

<template>
  <table :class="{ 'table-fixed': fixed }">
    <thead class="sticky top-0 z-10" :class="headerRowClass">
      <tr
        v-for="headerGroup in table.getHeaderGroups()"
        :key="headerGroup.id"
        class="rounded-xl"
      >
        <th
          v-for="header in headerGroup.headers"
          :key="header.id"
          :colspan="header.colSpan"
          :style="{
            width: `${header.getSize()}px`,
          }"
          class="text-left px-4 py-3 text-xs font-medium text-n-slate-10 uppercase tracking-wider"
          :class="headerClass"
          @click="header.column.getCanSort() && header.column.toggleSorting()"
        >
          <div
            v-if="!header.isPlaceholder"
            class="flex place-items-center gap-1"
          >
            <FlexRender
              :render="header.column.columnDef.header"
              :props="header.getContext()"
            />
            <SortButton v-if="header.column.getCanSort()" :header="header" />
          </div>
        </th>
      </tr>
    </thead>

    <tbody class="divide-y divide-n-weak/30">
      <tr
        v-for="row in table.getRowModel().rows"
        :key="row.id"
        :class="rowClass"
      >
        <td
          v-for="cell in row.getVisibleCells()"
          :key="cell.id"
          :class="[isRelaxed ? 'py-4 px-5' : 'py-2 px-5', cellClass]"
        >
          <FlexRender
            :render="cell.column.columnDef.cell"
            :props="cell.getContext()"
          />
        </td>
      </tr>
    </tbody>
  </table>
</template>
