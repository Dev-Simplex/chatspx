<script setup>
import { ref } from 'vue';

defineProps({
  toolName: {
    type: String,
    default: '',
  },
  isLoading: {
    type: Boolean,
    default: true,
  },
  result: {
    type: String,
    default: '',
  },
});

const expanded = ref(false);

const TOOL_LABELS = {
  get_account_stats: 'Buscando estatísticas...',
  get_agent_workload: 'Verificando carga dos agentes...',
  get_team_info: 'Carregando info do time...',
  assign_conversation: 'Atribuindo conversa...',
  add_label: 'Adicionando label...',
  change_status: 'Alterando status...',
  change_priority: 'Alterando prioridade...',
  get_csat_data: 'Carregando dados de CSAT...',
  search_messages: 'Pesquisando mensagens...',
  get_inbox_info: 'Carregando info da inbox...',
  get_conversation_full: 'Carregando detalhes da conversa...',
  search_documentation: 'Pesquisando documentação...',
  get_conversation: 'Carregando conversa...',
  search_conversation: 'Pesquisando conversas...',
};
</script>

<template>
  <div class="rounded-lg border border-n-weak/50 bg-n-alpha-1 px-3 py-2">
    <button
      class="flex w-full items-center gap-2 text-xs"
      @click="expanded = !expanded"
    >
      <span
        v-if="isLoading"
        class="size-3.5 animate-spin rounded-full border-2 border-n-brand/30 border-t-n-brand"
      />
      <i
        v-else
        class="i-lucide-check-circle size-3.5 text-green-600 dark:text-green-400"
      />
      <span class="flex-1 text-left text-n-slate-11">
        {{ TOOL_LABELS[toolName] || `Executando ${toolName}...` }}
      </span>
      <i
        v-if="!isLoading && result"
        class="i-lucide-chevron-down size-3 transition-transform"
        :class="{ 'rotate-180': expanded }"
      />
    </button>
    <div
      v-if="expanded && !isLoading && result"
      class="mt-1.5 text-xs text-n-slate-10 line-clamp-3 break-words"
    >
      {{ result }}
    </div>
  </div>
</template>
