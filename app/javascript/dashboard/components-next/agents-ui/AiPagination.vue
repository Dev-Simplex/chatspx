<script setup>
// Paginação iOS: ‹ página/total ›.
defineProps({
  page: { type: Number, default: 1 },
  totalPages: { type: Number, default: 1 },
});
const emit = defineEmits(['update:page']);
defineOptions({ name: 'AiPagination' });
const go = p => emit('update:page', p);
const SEP = '/';
</script>

<template>
  <div
    v-if="totalPages > 1"
    class="flex gap-2 justify-center items-center pt-4"
  >
    <button
      type="button"
      :disabled="page <= 1"
      class="grid place-items-center rounded-lg border transition size-9 border-n-weak bg-n-solid-1 text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-40 active:scale-95"
      @click="go(page - 1)"
    >
      <span class="i-lucide-chevron-left size-4" />
    </button>
    <span class="text-[13px] font-semibold tabular-nums text-n-slate-11">
      {{ page }} {{ SEP }} {{ totalPages }}
    </span>
    <button
      type="button"
      :disabled="page >= totalPages"
      class="grid place-items-center rounded-lg border transition size-9 border-n-weak bg-n-solid-1 text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-40 active:scale-95"
      @click="go(page + 1)"
    >
      <span class="i-lucide-chevron-right size-4" />
    </button>
  </div>
</template>
