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
  isReports.value
    ? 'bg-n-solid-2/70 border-b border-n-container/60 backdrop-blur'
    : 'bg-n-slate-1'
);
const rowClass = computed(() =>
  isReports.value
    ? 'odd:bg-n-alpha-2/40 hover:bg-n-alpha-2/70 transition-colors'
    : ''
);
const cellClass = computed(() =>
  isReports.value ? 'py-3.5 px-5 text-sm text-n-slate-12' : ''
);
const headerCellClass = computed(() =>
  isReports.value
    ? 'text-left py-3 px-5 text-[11px] uppercase tracking-[0.2em] text-n-slate-10'
    : 'text-left py-3 px-5 font-medium text-sm text-n-slate-12'
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
          :style="{
            width: `${header.getSize()}px`,
          }"
          :class="[headerCellClass, headerClass]"
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

    <tbody class="divide-y divide-n-slate-2">
      <tr
        v-for="row in table.getRowModel().rows"
        :key="row.id"
        :class="rowClass"
      >
        <td
          v-for="cell in row.getVisibleCells()"
          :key="cell.id"
          :class="[
            isRelaxed ? 'py-4 px-5' : 'py-2 px-5',
            cellClass,
          ]"
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
