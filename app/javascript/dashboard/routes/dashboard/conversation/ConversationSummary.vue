<script setup>
import { computed, ref } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { useCollapsibleText } from 'dashboard/composables/useCollapsibleText';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const store = useStore();
const { t } = useI18n();
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
const humanSummary = computed(
  () => customAttributes.value.resumo_atendimento_humano || ''
);

// Resumo da IA nasce colapsado (clamp de 3 linhas). É somente leitura pro
// humano — só a IA escreve nele.
const {
  contentRef: aiSummaryRef,
  isExpanded: isAiSummaryExpanded,
  isOverflowing: isAiSummaryOverflowing,
  toggle: toggleAiSummary,
} = useCollapsibleText(aiSummary);

// Edição é exclusiva do "Resumo do humano".
const editing = ref(false);
const draft = ref('');
const saving = ref(false);

const startEdit = () => {
  editing.value = true;
  draft.value = humanSummary.value;
};

const cancelEdit = () => {
  editing.value = false;
  draft.value = '';
};

const save = async () => {
  saving.value = true;
  try {
    await store.dispatch('updateCustomAttributes', {
      conversationId: currentChat.value.id,
      customAttributes: {
        ...customAttributes.value,
        resumo_atendimento_humano: draft.value.trim(),
      },
    });
    editing.value = false;
    draft.value = '';
  } catch (error) {
    useAlert(t('CONVERSATION_SIDEBAR.SUMMARY.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-2 px-3 py-3 border-b border-n-weak/50">
    <!-- Resumo da IA (realçado, somente leitura — só a IA escreve nele) -->
    <div
      v-if="isCaptainEnabled"
      class="px-3 py-2.5 border rounded-lg border-n-brand/30 bg-n-brand/5"
    >
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

    <!-- Resumo do humano (editável) -->
    <div class="px-3 py-2.5 border rounded-lg border-n-weak bg-n-solid-2">
      <div class="flex items-center justify-between mb-1">
        <div class="flex items-center gap-1.5">
          <span class="i-lucide-user-round size-3.5 text-n-slate-11" />
          <span class="text-xs font-semibold text-n-slate-12">
            {{ $t('CONVERSATION_SIDEBAR.SUMMARY.HUMAN_TITLE') }}
          </span>
        </div>
        <button
          v-if="!editing"
          class="flex items-center justify-center rounded size-5 text-n-slate-10 hover:bg-n-slate-3 hover:text-n-slate-12"
          :title="$t('CONVERSATION_SIDEBAR.SUMMARY.EDIT')"
          @click="startEdit"
        >
          <span class="i-lucide-pencil size-3" />
        </button>
      </div>
      <template v-if="editing">
        <textarea
          v-model="draft"
          rows="4"
          class="w-full px-2 py-1.5 text-xs border rounded resize-y border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-brand"
        />
        <div class="flex items-center justify-end gap-3 mt-1.5">
          <button
            class="text-xs text-n-slate-11 hover:text-n-slate-12"
            @click="cancelEdit"
          >
            {{ $t('CONVERSATION_SIDEBAR.SUMMARY.CANCEL') }}
          </button>
          <button
            class="text-xs font-medium text-n-brand disabled:opacity-50"
            :disabled="saving"
            @click="save"
          >
            {{ $t('CONVERSATION_SIDEBAR.SUMMARY.SAVE') }}
          </button>
        </div>
      </template>
      <p
        v-else-if="humanSummary"
        class="text-xs leading-relaxed text-n-slate-12 whitespace-pre-line"
      >
        {{ humanSummary }}
      </p>
      <button
        v-else
        type="button"
        class="text-xs italic text-left text-n-slate-10 hover:text-n-slate-11"
        @click="startEdit"
      >
        {{ $t('CONVERSATION_SIDEBAR.SUMMARY.HUMAN_EMPTY') }}
      </button>
    </div>
  </div>
</template>
