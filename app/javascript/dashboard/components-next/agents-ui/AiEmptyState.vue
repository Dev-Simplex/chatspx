<script setup>
// Estado vazio iOS: ícone em pílula + título + descrição + ação (slot). Entrada com fade.
defineProps({
  icon: { type: String, default: 'i-lucide-inbox' },
  title: { type: String, default: '' },
  description: { type: String, default: '' },
});
defineOptions({ name: 'AiEmptyState' });
</script>

<template>
  <div
    class="flex flex-col items-center px-6 py-14 text-center rounded-2xl border border-dashed ai-empty border-n-weak bg-n-alpha-1"
  >
    <span
      class="grid mb-3 rounded-2xl place-items-center size-14 bg-n-alpha-2 text-n-slate-10"
    >
      <span :class="icon" class="size-7" />
    </span>
    <h3 v-if="title" class="mb-1 text-base font-bold text-n-slate-12">
      {{ title }}
    </h3>
    <p v-if="description" class="max-w-md text-[13px] text-n-slate-10">
      {{ description }}
    </p>
    <div v-if="$slots.action" class="mt-4"><slot name="action" /></div>
  </div>
</template>

<style scoped>
.ai-empty {
  animation: ai-fade 0.4s ease both;
}
@keyframes ai-fade {
  from {
    opacity: 0;
    transform: translateY(6px);
  }
  to {
    opacity: 1;
    transform: none;
  }
}
@media (prefers-reduced-motion: reduce) {
  .ai-empty {
    animation: none;
  }
}
</style>
