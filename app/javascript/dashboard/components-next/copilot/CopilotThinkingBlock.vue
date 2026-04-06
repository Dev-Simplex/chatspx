<script setup>
import Icon from '../../components-next/icon/Icon.vue';
defineProps({
  content: {
    type: String,
    required: true,
  },
});
</script>

<template>
  <div
    class="flex flex-col gap-2 px-3 py-2 rounded-lg bg-n-slate-2/50 border border-n-weak/50 transition-colors duration-200"
  >
    <div class="flex items-start gap-2">
      <Icon
        icon="i-lucide-sparkles"
        class="w-3.5 h-3.5 mt-0.5 flex-shrink-0 text-n-slate-9 animate-pulse"
      />
      <div class="text-xs text-n-slate-10 font-mono">
        {{ content }}
      </div>
    </div>
  </div>
</template>
