<script setup>
import { computed } from 'vue';
import AiAvatar from './AiAvatar.vue';
// Card de agente (grid do dashboard): avatar + nome + modelo + descrição + rodapé (inboxes + status).
const props = defineProps({
  agent: { type: Object, default: () => ({}) },
  inboxLabel: { type: String, default: '' },
  activeLabel: { type: String, default: '' },
  inactiveLabel: { type: String, default: '' },
});
defineEmits(['select']);
defineOptions({ name: 'AiAgentCard' });
const model = computed(
  () => props.agent?.config?.model || props.agent?.config?.llm_model || ''
);
const inboxCount = computed(() => props.agent?.account_inbox_ids?.length || 0);
const isActive = computed(() => props.agent?.active !== false);
</script>

<template>
  <button
    type="button"
    class="flex flex-col p-4 text-left rounded-2xl border shadow-sm transition-all duration-200 ai-agent border-n-weak bg-n-solid-1/70 backdrop-blur-xl hover:-translate-y-0.5 hover:shadow-md hover:bg-n-solid-1/90 active:scale-[0.99]"
    @click="$emit('select', agent)"
  >
    <div class="flex gap-3 items-center w-full">
      <AiAvatar :name="agent.name" :size="44" />
      <div class="flex-1 min-w-0">
        <p class="text-[15px] font-bold truncate text-n-slate-12">
          {{ agent.name }}
        </p>
        <p v-if="model" class="font-mono text-[11px] truncate text-n-slate-10">
          {{ model }}
        </p>
      </div>
    </div>
    <p
      v-if="agent.description"
      class="mt-3 text-[12.5px] line-clamp-2 text-n-slate-11"
    >
      {{ agent.description }}
    </p>
    <div
      class="flex justify-between items-center pt-3 mt-auto text-[11.5px] border-t border-n-weak text-n-slate-10"
      :class="agent.description ? 'mt-3' : 'mt-4'"
    >
      <span class="inline-flex gap-1 items-center">
        <span class="i-lucide-inbox size-3.5" />
        {{ inboxCount }} {{ inboxLabel }}
      </span>
      <span class="inline-flex gap-1.5 items-center font-semibold">
        <span
          class="rounded-full size-2"
          :class="isActive ? 'bg-n-teal-9' : 'bg-n-slate-7'"
        />
        {{ isActive ? activeLabel : inactiveLabel }}
      </span>
    </div>
  </button>
</template>

<style scoped>
.ai-agent {
  animation: ai-rise 0.45s cubic-bezier(0.22, 1, 0.36, 1) both;
}
@keyframes ai-rise {
  from {
    opacity: 0;
    transform: translateY(10px);
  }
  to {
    opacity: 1;
    transform: none;
  }
}
@media (prefers-reduced-motion: reduce) {
  .ai-agent {
    animation: none;
  }
}
</style>
