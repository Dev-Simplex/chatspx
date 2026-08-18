<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';

/**
 * A barra de salvar das quatro telas novas.
 *
 * `role="region"` + `aria-live="polite"` porque o numero de alteracoes
 * pendentes muda enquanto o foco esta em OUTRO lugar da tela (23-plano §B.0.5):
 * quem navega por leitor de tela precisa ser avisado de que ha pendencia sem
 * ter de tabular ate a barra para descobrir. E a barra vem DEPOIS do conteudo
 * na ordem de foco, nunca antes.
 */
const props = defineProps({
  dirtyCount: { type: Number, default: 0 },
  isSaving: { type: Boolean, default: false },
  errorMessage: { type: String, default: '' },
});

defineEmits(['save', 'discard']);

const { t } = useI18n();

const isVisible = computed(() => props.dirtyCount > 0 || !!props.errorMessage);

const pendingLabel = computed(() =>
  t('INBOX_WIDGET.SAVE_BAR.PENDING', props.dirtyCount, {
    named: { count: props.dirtyCount },
  })
);
</script>

<template>
  <div
    v-if="isVisible"
    role="region"
    aria-live="polite"
    :aria-label="t('INBOX_WIDGET.SAVE_BAR.REGION_LABEL')"
    class="sticky bottom-0 z-10 flex flex-col gap-2 px-4 py-3 border-t bg-n-solid-1 border-n-weak"
  >
    <p
      v-if="errorMessage"
      class="text-sm text-n-ruby-11"
      data-testid="save-error"
    >
      {{ errorMessage }}
    </p>
    <div class="flex items-center justify-between gap-4">
      <span class="text-sm text-n-slate-11" data-testid="pending-count">
        {{ pendingLabel }}
      </span>
      <div class="flex items-center gap-2">
        <NextButton
          faded
          slate
          data-testid="discard-button"
          :label="t('INBOX_WIDGET.SAVE_BAR.DISCARD')"
          :disabled="isSaving || dirtyCount === 0"
          @click="$emit('discard')"
        />
        <NextButton
          data-testid="save-button"
          :label="t('INBOX_WIDGET.SAVE_BAR.SAVE')"
          :is-loading="isSaving"
          :disabled="isSaving || dirtyCount === 0"
          @click="$emit('save')"
        />
      </div>
    </div>
  </div>
</template>
