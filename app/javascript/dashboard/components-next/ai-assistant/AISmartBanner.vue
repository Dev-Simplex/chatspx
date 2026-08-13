<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { useReducedMotion } from 'dashboard/composables/useReducedMotion';

/**
 * Contextual banner shown at the top of the AI Assistant panel.
 *
 * Three variants (severity-driven) — all share the same structure but use
 * different colors, border accent and icon:
 *   - info     → long thread (purple)
 *   - warning  → negative sentiment (amber)
 *   - urgent   → customer waiting (red)
 *
 * Renders only the suggestion passed via the `suggestion` prop. Emits
 * `action` when the CTA is clicked and `dismiss` when the X is clicked.
 *
 * a11y:
 *   - role="status" + aria-live=polite for info/warning, assertive for urgent
 *   - dismiss button labeled via i18n; CTA label includes the body
 *     interpolation so screen readers announce context (e.g. "Summarize a
 *     thread of 23 messages with Copilot")
 *   - forced-colors fallback: visible 2px border on the root
 *   - reduced-motion: collapses transform animation to opacity-only
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

// Tone-driven Tailwind classes. Stays inline (not interpolated) so
// PurgeCSS keeps every variant.
const toneClasses = computed(() => {
  if (severity.value === 'urgent') {
    return [
      'bg-red-50 dark:bg-red-900/20',
      'border-l-4 border-red-500',
      'text-red-900 dark:text-red-100',
    ].join(' ');
  }
  if (severity.value === 'warning') {
    return [
      'bg-n-amber-3',
      'border-l-4 border-n-amber-9',
      'text-n-amber-12',
    ].join(' ');
  }
  return [
    'bg-n-violet-3',
    'border-l-4 border-n-violet-9',
    'text-n-violet-12',
  ].join(' ');
});

const iconColorClass = computed(() => {
  if (severity.value === 'urgent') {
    return 'text-red-600 dark:text-red-300';
  }
  if (severity.value === 'warning') {
    return 'text-n-amber-11';
  }
  return 'text-n-violet-11';
});

const ctaButtonClass = computed(() => {
  if (severity.value === 'urgent') {
    return 'bg-red-600 hover:bg-red-700 text-white focus-visible:ring-red-300';
  }
  if (severity.value === 'warning') {
    // amber-9/10 são claros nos dois temas: o texto tem de ser escuro fixo.
    return 'bg-n-amber-9 hover:bg-n-amber-10 text-n-black focus-visible:ring-n-amber-8';
  }
  return 'bg-n-violet-9 hover:bg-n-violet-10 dark:hover:bg-n-violet-8 text-white focus-visible:ring-n-violet-8';
});

const ariaLive = computed(() =>
  severity.value === 'urgent' ? 'assertive' : 'polite'
);

const bodyText = computed(() =>
  t(props.suggestion.textKey, props.suggestion.textParams || {})
);

const ctaLabel = computed(() => t(props.suggestion.ctaKey));

const ariaLabelCta = computed(() => `${ctaLabel.value} — ${bodyText.value}`);

const dismissTooltip = computed(() =>
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
      class="relative flex items-start gap-3 rounded-lg border-2 border-transparent px-3 py-3 pr-9 forced-colors:border-current"
      :class="toneClasses"
      :data-testid="variantTestId"
    >
      <Icon
        :icon="suggestion.icon"
        class="mt-0.5 size-4 shrink-0"
        :class="iconColorClass"
        aria-hidden="true"
      />

      <div class="flex min-w-0 flex-1 flex-col gap-2">
        <p class="text-xs leading-snug">{{ bodyText }}</p>
        <div class="flex items-center justify-end">
          <button
            type="button"
            :aria-label="ariaLabelCta"
            class="inline-flex items-center gap-1 rounded-md px-2.5 py-1 text-[11px] font-semibold transition-colors focus:outline-none focus-visible:ring-2"
            :class="ctaButtonClass"
            data-testid="ai-smart-banner-cta"
            @click="handleAction"
          >
            {{ ctaLabel }}
          </button>
        </div>
      </div>

      <button
        type="button"
        :aria-label="dismissTooltip"
        :title="dismissTooltip"
        class="absolute right-1.5 top-1.5 inline-flex size-6 items-center justify-center rounded-md opacity-70 transition-colors hover:bg-n-black/5 hover:text-current focus:outline-none focus-visible:ring-2 focus-visible:ring-n-violet-8 dark:hover:bg-white/10"
        data-testid="ai-smart-banner-dismiss"
        @click="handleDismiss"
      >
        <Icon icon="i-lucide-x" class="size-3.5" aria-hidden="true" />
      </button>
    </div>
  </Transition>
</template>
