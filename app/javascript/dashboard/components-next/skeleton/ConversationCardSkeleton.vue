<script setup>
defineProps({
  count: {
    type: Number,
    default: 6,
  },
});
</script>

<template>
  <div class="flex flex-col">
    <div
      v-for="n in count"
      :key="n"
      class="flex items-center gap-3 px-4 py-3 border-b border-n-weak"
    >
      <!-- Avatar circle 40px -->
      <div class="bg-n-slate-3 animate-pulse rounded-full size-10 shrink-0" />
      <div class="flex-1 min-w-0 space-y-2">
        <!-- Name + timestamp row -->
        <div class="flex items-center justify-between gap-2">
          <div class="bg-n-slate-3 animate-pulse rounded h-3.5 w-28" />
          <div class="bg-n-slate-3 animate-pulse rounded h-3 w-10 shrink-0" />
        </div>
        <!-- Message preview line -->
        <div class="bg-n-slate-3 animate-pulse rounded h-3 w-3/4" />
      </div>
    </div>
  </div>
</template>
