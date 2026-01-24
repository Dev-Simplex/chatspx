<template>
  <div class="nps-history">
    <h3 class="text-sm font-semibold mb-3">Histórico de NPS</h3>
    <div
      v-if="history.length === 0"
      class="text-sm text-n-slate-11"
    >
      Nenhum NPS encontrado
    </div>
    <div
      v-for="item in history"
      :key="item.id"
      class="mb-3 p-2 border rounded"
    >
      <div class="flex items-center justify-between">
        <span class="text-sm font-medium">{{ item.score }}/10</span>
        <span class="text-xs text-n-slate-11">{{ formatDate(item.answered_at) }}</span>
      </div>
      <p
        v-if="item.comment"
        class="text-xs text-n-slate-11 mt-1"
      >
        {{ item.comment }}
      </p>
    </div>
  </div>
</template>

<script setup>
import { defineProps } from 'vue';

const props = defineProps({
  history: {
    type: Array,
    default: () => [],
  },
});

const formatDate = (date) => {
  if (!date) return '';
  return new Date(date).toLocaleDateString();
};
</script>
