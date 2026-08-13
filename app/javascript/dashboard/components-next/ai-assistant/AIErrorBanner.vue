<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  errorType: {
    type: String,
    required: true,
    // 'rate_limit' | 'captain_unstable' | 'timeout' | 'empty_response' | 'network'
  },
  retryAfterSeconds: {
    type: Number,
    default: 0,
  },
});

const emit = defineEmits(['retry', 'dismiss', 'cancel']);

const { t } = useI18n();

// Maps each error type to:
// - color tokens (Tailwind classes for bg/border/icon),
// - copy keys (title, body),
// - aria-live politeness,
// - which CTAs to show.
const VARIANTS = {
  rate_limit: {
    tone: 'amber',
    icon: 'i-lucide-clock',
    titleKey: 'COPILOT_ERRORS.RATE_LIMIT.TITLE',
    bodyKey: 'COPILOT_ERRORS.RATE_LIMIT.BODY',
    ariaLive: 'polite',
    ctas: ['retry', 'dismiss'],
  },
  captain_unstable: {
    tone: 'red',
    icon: 'i-lucide-cloud-off',
    titleKey: 'COPILOT_ERRORS.CAPTAIN_UNSTABLE.TITLE',
    bodyKey: 'COPILOT_ERRORS.CAPTAIN_UNSTABLE.BODY',
    ariaLive: 'polite',
    ctas: ['retry', 'dismiss'],
  },
  timeout: {
    tone: 'amber',
    icon: 'i-lucide-hourglass',
    titleKey: 'COPILOT_ERRORS.TIMEOUT.TITLE',
    bodyKey: 'COPILOT_ERRORS.TIMEOUT.BODY',
    ariaLive: 'polite',
    ctas: ['retry', 'cancel'],
  },
  empty_response: {
    tone: 'red',
    icon: 'i-lucide-circle-help',
    titleKey: 'COPILOT_ERRORS.EMPTY_RESPONSE.TITLE',
    bodyKey: 'COPILOT_ERRORS.EMPTY_RESPONSE.BODY',
    ariaLive: 'polite',
    ctas: ['retry', 'dismiss'],
  },
  network: {
    tone: 'red',
    icon: 'i-lucide-wifi-off',
    titleKey: 'COPILOT_ERRORS.NETWORK.TITLE',
    bodyKey: 'COPILOT_ERRORS.NETWORK.BODY',
    ariaLive: 'assertive',
    ctas: ['retry', 'dismiss'],
  },
};

const variant = computed(() => VARIANTS[props.errorType] || null);

// Toolwind palette per tone (kept in template via static maps so PurgeCSS keeps them).
const toneClasses = computed(() => {
  if (!variant.value) return '';
  if (variant.value.tone === 'amber') {
    return 'border-n-amber-6 bg-n-amber-3 text-n-amber-12 dark:bg-n-amber-2';
  }
  return 'border-red-300 bg-red-50 text-red-900 dark:border-red-800/40 dark:bg-n-ruby-2 dark:text-red-100';
});

const iconColorClass = computed(() => {
  if (!variant.value) return '';
  return variant.value.tone === 'amber'
    ? 'text-n-amber-11'
    : 'text-red-600 dark:text-red-400';
});

const isRetryDisabled = computed(() => {
  return props.errorType === 'rate_limit' && props.retryAfterSeconds > 0;
});

const retryLabel = computed(() => {
  if (props.errorType === 'rate_limit' && props.retryAfterSeconds > 0) {
    return t('COPILOT_ERRORS.RATE_LIMIT.CTA_COUNTDOWN', {
      seconds: props.retryAfterSeconds,
    });
  }
  if (props.errorType === 'timeout') {
    return t('COPILOT_ERRORS.TIMEOUT.CTA_PRIMARY');
  }
  return t('COPILOT_ERRORS.CTA_RETRY');
});

const cancelLabel = computed(() =>
  t('COPILOT_ERRORS.TIMEOUT.CTA_CANCEL')
);
const dismissLabel = computed(() =>
  t('COPILOT_ERRORS.CTA_DISMISS')
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
</script>

<template>
  <div
    v-if="variant"
    role="alert"
    :aria-live="variant.ariaLive"
    :data-testid="variantTestId"
    class="flex flex-col gap-2 rounded-lg border px-3 py-2.5"
    :class="toneClasses"
  >
    <div class="flex items-start gap-2.5">
      <Icon
        :icon="variant.icon"
        class="mt-0.5 size-4 shrink-0"
        :class="iconColorClass"
      />
      <div class="flex min-w-0 flex-1 flex-col gap-0.5">
        <p class="text-xs font-semibold leading-tight">
          {{ t(variant.titleKey) }}
        </p>
        <p class="text-[11px] leading-snug opacity-90">
          {{ bodyText }}
        </p>
      </div>
    </div>
    <div class="flex flex-wrap items-center justify-end gap-2">
      <button
        v-if="showCancel"
        type="button"
        class="rounded-md border border-transparent bg-white/40 px-2.5 py-1 text-[11px] font-medium text-current transition-colors hover:bg-white/70 focus:outline-none focus:ring-2 focus:ring-n-violet-8 dark:bg-white/5 dark:hover:bg-white/10"
        @click="emit('cancel')"
      >
        {{ cancelLabel }}
      </button>
      <button
        v-if="showDismiss"
        type="button"
        class="rounded-md border border-transparent bg-white/40 px-2.5 py-1 text-[11px] font-medium text-current transition-colors hover:bg-white/70 focus:outline-none focus:ring-2 focus:ring-n-violet-8 dark:bg-white/5 dark:hover:bg-white/10"
        @click="emit('dismiss')"
      >
        {{ dismissLabel }}
      </button>
      <button
        v-if="showRetry"
        type="button"
        class="inline-flex items-center gap-1 rounded-md bg-n-violet-9 px-2.5 py-1 text-[11px] font-semibold text-white transition-colors hover:bg-n-violet-10 dark:hover:bg-n-violet-8 focus:outline-none focus:ring-2 focus:ring-n-violet-8 disabled:cursor-not-allowed disabled:opacity-60"
        :disabled="isRetryDisabled"
        @click="emit('retry')"
      >
        {{ retryLabel }}
      </button>
    </div>
  </div>
</template>
