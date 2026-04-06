<script setup>
defineProps({
  header: {
    type: Object,
    required: true,
  },
});

const sortIconMap = {
  default: 'i-lucide-chevrons-up-down',
  asc: 'i-lucide-chevron-up',
  desc: 'i-lucide-chevron-down',
};
</script>

<template>
  <span
    :class="[
      sortIconMap[header.column.getIsSorted() || 'default'],
      header.column.getIsSorted() ? 'text-n-brand' : 'text-n-slate-10',
    ]"
  />
</template>
