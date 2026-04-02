<script setup>
import { computed } from 'vue';

const props = defineProps({
  headers: {
    type: Array,
    default: () => [],
  },
  items: {
    type: Array,
    default: () => [],
  },
  noDataMessage: {
    type: String,
    default: '',
  },
  loading: {
    type: Boolean,
    default: false,
  },
});

const hasHeaderSlot = computed(() => !!props.headers.length);
const showHeaders = computed(
  () => hasHeaderSlot.value && props.items.length > 0
);
</script>

<template>
  <div class="w-full">
    <table class="min-w-full table-auto divide-y divide-n-weak">
      <thead v-if="showHeaders" class="bg-n-slate-2/50 dark:bg-n-solid-3">
        <tr>
          <th
            v-for="(header, index) in headers"
            :key="index"
            class="px-4 py-3 text-start text-xs font-medium text-n-slate-10 uppercase tracking-wider"
          >
            <slot :name="`header-${index}`" :header="header">
              {{ header }}
            </slot>
          </th>
        </tr>
      </thead>
      <tbody class="divide-y divide-n-weak/30 text-n-slate-11">
        <template v-if="items.length">
          <slot name="row" :items="items" />
        </template>
        <tr v-else-if="noDataMessage && !loading">
          <td
            :colspan="headers.length || 1"
            class="py-20 text-center text-body-main !text-base text-n-slate-11"
          >
            {{ noDataMessage }}
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
