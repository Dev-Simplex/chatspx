<script setup>
import { computed } from 'vue';
import AiAvatar from './AiAvatar.vue';
// Card de agente (grid do dashboard): avatar + nome + modelo + descrição + rodapé (caixas + uso).
//
// Três campos deste card liam chaves que a API do assistant NÃO devolve
// (`_assistant.json.jbuilder`), e o JavaScript entregava vazio/zero sem reclamar:
//   - `agent.config.model` / `agent.config.llm_model`: nenhuma das duas existe. O modelo
//     é da CONTA, não do agente — agora chega pronto pela prop `model`, de quem resolve
//     na fonte real (ver useCaptainAssistantModel).
//   - `agent.account_inbox_ids`: o nome certo é `inbox_ids`, então a contagem dava
//     sempre 0 mesmo com o agente atendendo caixas.
//   - `agent.active`: não existe no payload e NÃO EXISTE conceito de assistant
//     ativo/inativo no sistema (não há coluna nem método). `undefined !== false` deixava
//     o selo preso em "Ativo" para todo agente. Trocado por um fato verificável: o agente
//     atende alguma caixa ou não. Sem caixa, ele comprovadamente nunca roda.
const props = defineProps({
  agent: { type: Object, default: () => ({}) },
  model: { type: String, default: '' },
  inboxLabel: { type: String, default: '' },
  inUseLabel: { type: String, default: '' },
  noInboxLabel: { type: String, default: '' },
});
defineEmits(['select']);
defineOptions({ name: 'AiAgentCard' });
const inboxCount = computed(() => props.agent?.inbox_ids?.length || 0);
const hasInbox = computed(() => inboxCount.value > 0);
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
          :class="hasInbox ? 'bg-g-500' : 'bg-n-slate-7'"
        />
        {{ hasInbox ? inUseLabel : noInboxLabel }}
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
