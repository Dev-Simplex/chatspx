<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useCollapsibleText } from 'dashboard/composables/useCollapsibleText';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const currentChat = useMapGetter('getSelectedChat');
const currentAccountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

// O card "Resumo da IA" só aparece em conta com o módulo de IA ativo (mesmo
// sinal canônico das rotas de Agentes IA).
const isCaptainEnabled = computed(() =>
  isFeatureEnabledonAccount.value(
    currentAccountId.value,
    FEATURE_FLAGS.CAPTAIN_V2
  )
);

const customAttributes = computed(
  () => currentChat.value?.custom_attributes || {}
);
const aiSummary = computed(
  () => customAttributes.value.resumo_atendimento_ia || ''
);

// Resumo da IA nasce colapsado (clamp de 3 linhas). É somente leitura pro
// humano — só a IA escreve nele.
const {
  contentRef: aiSummaryRef,
  isExpanded: isAiSummaryExpanded,
  isOverflowing: isAiSummaryOverflowing,
  toggle: toggleAiSummary,
} = useCollapsibleText(aiSummary);
</script>

<template>
  <!-- Resumo da IA (realçado, somente leitura — só a IA escreve nele) -->
  <div>
    <div
      v-if="isCaptainEnabled"
      class="flex flex-col gap-2 px-3 py-3 border-b border-n-weak/50"
    >
      <div class="px-3 py-2.5 border rounded-lg border-n-brand/30 bg-n-brand/5">
        <div class="flex items-center gap-1.5 mb-1">
          <span class="i-lucide-sparkles size-3.5 text-n-brand" />
          <span class="text-xs font-semibold text-n-slate-12">
            {{ $t('CONVERSATION_SIDEBAR.SUMMARY.AI_TITLE') }}
          </span>
        </div>
        <template v-if="aiSummary">
          <p
            ref="aiSummaryRef"
            class="text-xs leading-relaxed text-n-slate-12 whitespace-pre-line"
            :class="{ 'line-clamp-3': !isAiSummaryExpanded }"
          >
            {{ aiSummary }}
          </p>
          <button
            v-if="isAiSummaryOverflowing || isAiSummaryExpanded"
            type="button"
            class="mt-1 text-xs font-medium text-n-brand hover:opacity-80"
            @click="toggleAiSummary"
          >
            {{
              isAiSummaryExpanded
                ? $t('CONVERSATION_SIDEBAR.SUMMARY.READ_LESS')
                : $t('CONVERSATION_SIDEBAR.SUMMARY.READ_MORE')
            }}
          </button>
        </template>
        <p v-else class="text-xs italic text-n-slate-10">
          {{ $t('CONVERSATION_SIDEBAR.SUMMARY.AI_EMPTY') }}
        </p>
      </div>
    </div>
  </div>
</template>
