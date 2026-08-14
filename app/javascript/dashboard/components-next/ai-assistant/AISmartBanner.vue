<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { useReducedMotion } from 'dashboard/composables/useReducedMotion';

/**
 * Aviso contextual no topo do painel do copiloto ("conversa longa, quer um
 * resumo?", "o cliente está esperando há 6 min").
 *
 * Monocromático por decisão de produto (contrato C2: nenhuma cor de destaque
 * no fio do chat). A severidade continua existindo na API — ela só deixou de
 * ser hue e virou **peso**, no vocabulário do `.note` do mockup: uma régua à
 * esquerda que escurece conforme a urgência.
 *
 *   - info     → régua `--oa-line`     (fraca)
 *   - warning  → régua `--oa-ink-2`    (média)
 *   - urgent   → régua `--oa-ink`      (forte) + role="alert"/assertive
 *
 * A urgência que realmente importa para quem não enxerga cor continua no
 * `role`/`aria-live` e no texto — nunca dependeu do vermelho.
 *
 * LAYOUT (revisto em 2026-07-29): o "X" que flutuava no canto superior
 * direito saiu. Ele era um alvo de 24×24 solto sobre o texto e disputava a
 * leitura com o corpo do aviso — o agente lia a frase, achava o X antes da
 * ação e dispensava sem entender. Agora as duas ações moram na MESMA régua
 * abaixo do texto, alinhadas à esquerda com ele, no vocabulário do `.errbar`
 * do mockup: a ação principal em pílula escura, "Dispensar" como link
 * sublinhado. Quem quiser dispensar continua a um clique — só que agora lê
 * a frase primeiro.
 *
 * a11y:
 *   - role="status" + aria-live=polite para info/warning, alert/assertive
 *     para urgent;
 *   - a CTA inclui o corpo no aria-label para o leitor de tela anunciar o
 *     contexto; "Dispensar" virou texto visível (era só title/aria-label);
 *   - forced-colors: borda visível de 2px na raiz;
 *   - reduced-motion: a entrada vira só opacidade;
 *   - ambas as ações com área de toque de 44×44 via `oa-hit-44`.
 */

const props = defineProps({
  suggestion: {
    type: Object,
    required: true,
    validator: v =>
      !!v &&
      typeof v.id === 'string' &&
      typeof v.textKey === 'string' &&
      typeof v.ctaKey === 'string',
  },
});

const emit = defineEmits(['action', 'dismiss']);

const { t } = useI18n();
const { prefersReducedMotion } = useReducedMotion();

const severity = computed(() => props.suggestion?.severity || 'info');

// Classes por severidade. Ficam literais (não interpoladas) para o PurgeCSS
// manter as três variantes.
const toneClasses = computed(() => {
  if (severity.value === 'urgent') {
    return 'border-l-2 border-l-[var(--oa-ink)]';
  }
  if (severity.value === 'warning') {
    return 'border-l-2 border-l-[var(--oa-ink-2)]';
  }
  return 'border-l-2 border-l-[var(--oa-line)]';
});

const ariaLive = computed(() =>
  severity.value === 'urgent' ? 'assertive' : 'polite'
);

const bodyText = computed(() =>
  t(props.suggestion.textKey, props.suggestion.textParams || {})
);

const ctaLabel = computed(() => t(props.suggestion.ctaKey));

const ariaLabelCta = computed(() => `${ctaLabel.value} — ${bodyText.value}`);

// A chave nasceu como tooltip do X; virou o rótulo visível do link. O nome
// dela fica como está para não mexer no arquivo de i18n (frente A2).
const dismissLabel = computed(() =>
  t('CONVERSATION.AI_ASSISTANT_PANEL.SMART_BANNER.DISMISS_TOOLTIP')
);

function handleAction() {
  emit('action', props.suggestion);
}

function handleDismiss() {
  emit('dismiss', props.suggestion);
}

// Stable, suggestion-specific testid (e.g. `ai-smart-banner-long-thread`)
// so E2E specs can assert on the active variant without relying on text.
// Falls back to a generic id when the suggestion id is missing.
const variantTestId = computed(() => {
  const id = props.suggestion?.id;
  if (!id) return 'ai-smart-banner';
  const slug = String(id).replace(/_/g, '-');
  return `ai-smart-banner-${slug}`;
});
</script>

<template>
  <Transition
    :enter-active-class="
      prefersReducedMotion
        ? 'transition-opacity duration-[80ms] ease-linear'
        : 'transition duration-[200ms] ease-out'
    "
    :enter-from-class="
      prefersReducedMotion ? 'opacity-0' : 'opacity-0 -translate-y-2'
    "
    :enter-to-class="
      prefersReducedMotion ? 'opacity-100' : 'opacity-100 translate-y-0'
    "
    :leave-active-class="
      prefersReducedMotion
        ? 'transition-opacity duration-[80ms] ease-linear'
        : 'transition-opacity duration-[150ms] ease-in'
    "
    leave-from-class="opacity-100"
    leave-to-class="opacity-0"
    appear
  >
    <div
      :role="severity === 'urgent' ? 'alert' : 'status'"
      :aria-live="ariaLive"
      class="flex items-start gap-2.5 rounded-r-lg bg-[var(--oa-code)] px-3.5 py-3 text-[var(--oa-ink-2)] forced-colors:border-2 forced-colors:border-current"
      :class="toneClasses"
      :data-testid="variantTestId"
    >
      <Icon
        :icon="suggestion.icon"
        class="mt-0.5 size-4 shrink-0 text-[var(--oa-ink-2)]"
        aria-hidden="true"
      />

      <div class="flex min-w-0 flex-1 flex-col gap-2.5">
        <p class="text-[13px] leading-snug">{{ bodyText }}</p>
        <!--
          Régua de ações: mesma margem esquerda do texto, ação principal
          primeiro. `gap-y-3.5` (14px) é o que mantém 44px de passo entre
          linhas quando as duas ações quebram — a pílula tem 30px.
        -->
        <div class="flex flex-wrap items-center gap-x-4 gap-y-3.5">
          <button
            type="button"
            :aria-label="ariaLabelCta"
            class="oa-hit-44 inline-flex h-[30px] items-center rounded-[7px] bg-[var(--oa-send)] px-[11px] text-[12.5px] font-medium text-[var(--oa-send-ink)] transition-opacity hover:opacity-85 focus:outline-none focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-[var(--oa-focus)]"
            data-testid="ai-smart-banner-cta"
            @click="handleAction"
          >
            {{ ctaLabel }}
          </button>
          <button
            type="button"
            :title="dismissLabel"
            class="oa-hit-44 whitespace-nowrap border-0 bg-transparent p-0 text-[12.5px] font-medium text-[var(--oa-ink-2)] underline underline-offset-2 transition-colors hover:text-[var(--oa-ink)] focus:outline-none focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--oa-focus)]"
            data-testid="ai-smart-banner-dismiss"
            @click="handleDismiss"
          >
            {{ dismissLabel }}
          </button>
        </div>
      </div>
    </div>
  </Transition>
</template>
