<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

/**
 * Estado "carregando" do copiloto, na linguagem da OpenAI: **três pontinhos
 * monocromáticos, nunca um spinner** e nunca uma barra colorida
 * (public/mockups/copiloto-v2.html, seletor `.thinking`).
 *
 * Sem bolha — a resposta que virá também não tem, então o placeholder ocupa
 * exatamente o mesmo lugar do texto e a tela não "pula" quando o primeiro
 * token chega.
 *
 * Reduced-motion: a animação `oa-bob` é desligada por media query em
 * `_copilot-oa.scss`; os pontos ficam estáticos e legíveis, sem duplicar a
 * regra em JavaScript.
 *
 * a11y: `role="status"` + `aria-busy="true"`; o rótulo é texto visível de
 * verdade (não sr-only), então o leitor de tela anuncia o mesmo que o agente
 * enxerga e o estado não depende do movimento.
 */

const props = defineProps({
  /** Texto opcional do que está sendo feito ("consultando o pedido"). */
  label: { type: String, default: '' },
});

const { t } = useI18n();

const loadingLabel = computed(
  () => props.label || t('CONVERSATION.AI_ASSISTANT_PANEL.LOADING')
);
</script>

<template>
  <div
    role="status"
    aria-busy="true"
    :aria-label="loadingLabel"
    data-testid="ai-loading-shimmer"
    class="flex w-full items-center gap-2 text-[13.5px] text-[var(--oa-ink-2)]"
  >
    <span class="flex gap-1" aria-hidden="true">
      <i class="oa-dot" data-testid="ai-loading-dot" />
      <i class="oa-dot oa-dot--2" data-testid="ai-loading-dot" />
      <i class="oa-dot oa-dot--3" data-testid="ai-loading-dot" />
    </span>
    <span>{{ loadingLabel }}</span>
  </div>
</template>
