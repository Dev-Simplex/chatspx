<script setup>
defineProps({
  rows: {
    type: Number,
    default: 4,
  },
});
</script>

<template>
  <div class="flex flex-col gap-6 p-6">
    <div v-for="n in rows" :key="n" class="space-y-2">
      <!-- Label -->
      <div class="bg-n-slate-3 animate-pulse rounded h-3 w-24" />
      <!-- Input field -->
      <div class="bg-n-slate-3 animate-pulse rounded-lg h-10 w-full" />
    </div>
    <!-- Submit button -->
    <div class="bg-n-slate-3 animate-pulse rounded-lg h-9 w-28 mt-2" />
  </div>
</template>
