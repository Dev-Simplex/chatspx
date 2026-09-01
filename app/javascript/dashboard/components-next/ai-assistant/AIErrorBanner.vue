<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';

/**
 * Banner de erro do copiloto, sóbrio e monocromático
 * (public/mockups/copiloto-v2.html, seletor `.errbar`): moldura `--oa-line`,
 * fundo `--oa-code`, texto `--oa-ink-2` e a ação como link sublinhado em
 * `--oa-ink`. **Sem vermelho e sem âmbar** — a regra C2 vale para o fio
 * inteiro do chat; a severidade aparece na palavra, não na cor.
 *
 * A variante `unauthorized` é a mais explícita das seis: diz que a credencial
 * foi recusada e deixa claro que **não é a conexão do agente**. Deixou de ser
 * o estado mais provável quando a chave foi renovada (2026-07-28), mas segue
 * sendo o que aparece quando a chave vence, quando o billing cai ou quando a
 * conta perde a integração — vale tratá-la como caminho de primeira classe.
 */

const props = defineProps({
  errorType: {
    type: String,
    required: true,
    // 'unauthorized' | 'rate_limit' | 'captain_unstable' | 'timeout'
    // | 'empty_response' | 'network'
  },
  retryAfterSeconds: {
    type: Number,
    default: 0,
  },
});

const emit = defineEmits(['retry', 'dismiss', 'cancel']);

const { t } = useI18n();

// Cada tipo de erro mapeia para: ícone, chaves de texto, urgência do
// aria-live e quais ações aparecem.
const VARIANTS = {
  unauthorized: {
    icon: 'i-lucide-key-round',
    titleKey: 'CONVERSATION.COPILOT_ERRORS.UNAUTHORIZED.TITLE',
    bodyKey: 'CONVERSATION.COPILOT_ERRORS.UNAUTHORIZED.BODY',
    ariaLive: 'polite',
    ctas: ['retry', 'dismiss'],
  },
  rate_limit: {
    icon: 'i-lucide-clock',
    titleKey: 'CONVERSATION.COPILOT_ERRORS.RATE_LIMIT.TITLE',
    bodyKey: 'CONVERSATION.COPILOT_ERRORS.RATE_LIMIT.BODY',
    ariaLive: 'polite',
    ctas: ['retry', 'dismiss'],
  },
  captain_unstable: {
    icon: 'i-lucide-cloud-off',
    titleKey: 'CONVERSATION.COPILOT_ERRORS.CAPTAIN_UNSTABLE.TITLE',
    bodyKey: 'CONVERSATION.COPILOT_ERRORS.CAPTAIN_UNSTABLE.BODY',
    ariaLive: 'polite',
    ctas: ['retry', 'dismiss'],
  },
  timeout: {
    icon: 'i-lucide-hourglass',
    titleKey: 'CONVERSATION.COPILOT_ERRORS.TIMEOUT.TITLE',
    bodyKey: 'CONVERSATION.COPILOT_ERRORS.TIMEOUT.BODY',
    ariaLive: 'polite',
    ctas: ['retry', 'cancel'],
  },
  empty_response: {
    icon: 'i-lucide-circle-help',
    titleKey: 'CONVERSATION.COPILOT_ERRORS.EMPTY_RESPONSE.TITLE',
    bodyKey: 'CONVERSATION.COPILOT_ERRORS.EMPTY_RESPONSE.BODY',
    ariaLive: 'polite',
    ctas: ['retry', 'dismiss'],
  },
  network: {
    icon: 'i-lucide-wifi-off',
    titleKey: 'CONVERSATION.COPILOT_ERRORS.NETWORK.TITLE',
    bodyKey: 'CONVERSATION.COPILOT_ERRORS.NETWORK.BODY',
    ariaLive: 'assertive',
    ctas: ['retry', 'dismiss'],
  },
};

const variant = computed(() => VARIANTS[props.errorType] || null);

const isRetryDisabled = computed(() => {
  return props.errorType === 'rate_limit' && props.retryAfterSeconds > 0;
});

const retryLabel = computed(() => {
  if (props.errorType === 'rate_limit' && props.retryAfterSeconds > 0) {
    return t('CONVERSATION.COPILOT_ERRORS.RATE_LIMIT.CTA_COUNTDOWN', {
      seconds: props.retryAfterSeconds,
    });
  }
  if (props.errorType === 'timeout') {
    return t('CONVERSATION.COPILOT_ERRORS.TIMEOUT.CTA_PRIMARY');
  }
  return t('CONVERSATION.COPILOT_ERRORS.CTA_RETRY');
});

const cancelLabel = computed(() =>
  t('CONVERSATION.COPILOT_ERRORS.TIMEOUT.CTA_CANCEL')
);
const dismissLabel = computed(() =>
  t('CONVERSATION.COPILOT_ERRORS.CTA_DISMISS')
);

const showCancel = computed(() => variant.value?.ctas?.includes('cancel'));
const showRetry = computed(() => variant.value?.ctas?.includes('retry'));
const showDismiss = computed(() => variant.value?.ctas?.includes('dismiss'));

const bodyText = computed(() => {
  if (!variant.value) return '';
  return t(variant.value.bodyKey, {
    seconds: props.retryAfterSeconds,
  });
});

// E2E specs target stable, variant-specific testids. Map snake_case props to
// kebab-case slugs and special-case empty_response → "empty" to match the
// matrix in spec/e2e/copilot/error-matrix.spec.js.
const TESTID_SLUGS = {
  unauthorized: 'unauthorized',
  rate_limit: 'rate-limit',
  captain_unstable: 'captain-unstable',
  timeout: 'timeout',
  empty_response: 'empty',
  network: 'network',
};
const variantTestId = computed(() => {
  const slug = TESTID_SLUGS[props.errorType];
  return slug ? `ai-error-banner-${slug}` : 'ai-error-banner';
});

// Ação como link sublinhado — o vocabulário do mockup para o `.errbar`.
// `oa-hit-44` estica só a área clicável (pseudo-elemento, ver _copilot-oa.scss):
// o link continua com 20px de altura, o dedo ganha 44×44.
//
// Recuperar e descartar NÃO têm o mesmo peso. O mockup pinta os dois botões do
// `.errbar` igual (semibold, `--oa-ink`), e visto na tela o agente não sabe
// qual é a saída: "Tentar de novo" e "Fechar" competem. Aqui a ação que
// resolve fica forte e a que só sai de cena fica em `--oa-ink-2` — a mesma
// gradação que o AISmartBanner usa entre a CTA e o "Dispensar", para os dois
// avisos do painel falarem a mesma língua.
// O desabilitado também não usa opacidade. O único botão que desabilita aqui é
// o retry durante o rate limit, e o rótulo dele é "Aguarde 42s" — o agente
// PRECISA ler quanto falta. A 50% (o que `_base.scss:286` impõe a todo
// `<button>`) esse texto media 3,59:1; em `--oa-ink-2` mede 6,15:1. O sinal de
// "não clicável" fica no sublinhado que sai e no cursor.
const LINK_BASE =
  'oa-hit-44 whitespace-nowrap border-0 bg-transparent p-0 text-[13px] underline underline-offset-2 transition-colors focus:outline-none focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--oa-focus)] disabled:cursor-not-allowed disabled:opacity-100 disabled:no-underline disabled:font-medium disabled:text-[var(--oa-ink-2)]';
const PRIMARY_ACTION_CLASS = `${LINK_BASE} font-semibold text-[var(--oa-ink)] hover:opacity-70`;
const SECONDARY_ACTION_CLASS = `${LINK_BASE} font-medium text-[var(--oa-ink-2)] hover:text-[var(--oa-ink)]`;
</script>

<template>
  <div
    v-if="variant"
    role="alert"
    :aria-live="variant.ariaLive"
    :data-testid="variantTestId"
    class="flex items-start gap-2.5 rounded-xl border border-solid border-[var(--oa-line)] bg-[var(--oa-code)] px-3.5 py-3 text-[13.5px] leading-normal text-[var(--oa-ink-2)]"
  >
    <Icon
      :icon="variant.icon"
      class="mt-0.5 size-4 shrink-0 text-[var(--oa-ink-2)]"
      aria-hidden="true"
    />
    <div class="flex min-w-0 flex-1 flex-col gap-1">
      <p class="font-semibold text-[var(--oa-ink)]">
        {{ t(variant.titleKey) }}
      </p>
      <p>{{ bodyText }}</p>
      <!--
        `gap-y-6` (24px) não é respiro: com 20px de altura, é o que garante
        44px de passo entre linhas quando as ações quebram — sem isso as duas
        áreas de toque de 44px se sobreporiam e o dedo acertaria a errada.
      -->
      <div class="mt-1 flex flex-wrap items-center gap-x-4 gap-y-6">
        <button
          v-if="showRetry"
          type="button"
          data-testid="ai-error-banner-retry"
          :class="PRIMARY_ACTION_CLASS"
          :disabled="isRetryDisabled"
          @click="emit('retry')"
        >
          {{ retryLabel }}
        </button>
        <button
          v-if="showCancel"
          type="button"
          data-testid="ai-error-banner-cancel"
          :class="SECONDARY_ACTION_CLASS"
          @click="emit('cancel')"
        >
          {{ cancelLabel }}
        </button>
        <button
          v-if="showDismiss"
          type="button"
          data-testid="ai-error-banner-dismiss"
          :class="SECONDARY_ACTION_CLASS"
          @click="emit('dismiss')"
        >
          {{ dismissLabel }}
        </button>
      </div>
    </div>
  </div>
</template>
