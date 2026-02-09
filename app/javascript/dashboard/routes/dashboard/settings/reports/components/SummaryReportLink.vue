<script setup>
import { computed } from 'vue';
const props = defineProps({
  row: {
    type: Object,
    required: true,
  },
});

const routeName = computed(() => `${props.row.original.type}_reports_show`);
</script>

<template>
  <router-link
    :to="{ name: routeName, params: { id: row.original.id } }"
    class="group inline-flex items-center gap-1 text-n-slate-12 hover:text-n-brand transition-colors"
  >
    <span class="truncate">{{ row.original.name }}</span>
    <span class="i-lucide-arrow-up-right text-n-slate-10 group-hover:text-n-brand" />
  </router-link>
</template>
