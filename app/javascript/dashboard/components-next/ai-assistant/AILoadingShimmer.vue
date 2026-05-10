<script setup>
import { useReducedMotion } from 'dashboard/composables/useReducedMotion';
import { useI18n } from 'vue-i18n';

/**
 * Shimmer skeleton displayed while the panel waits for an AI response or
 * loads thread history. Uses Tailwind utilities + a project-level
 * `animate-shimmer` keyframe (declared in `tailwind.config.js`).
 *
 * Reduced-motion fallback: three pulsing dots via Tailwind's
 * `animate-pulse`, with `aria-busy="true"` so SR announces the loading
 * state without horizontal-motion noise. Per-item animation-delay is
 * applied via Tailwind arbitrary values to avoid inline styles.
 */

const { t } = useI18n();
const { prefersReducedMotion } = useReducedMotion();
</script>

<template>
  <div
    role="status"
    aria-busy="true"
    :aria-label="t('CONVERSATION.AI_ASSISTANT_PANEL.LOADING')"
    data-testid="ai-loading-shimmer"
    class="flex w-full max-w-[85%] flex-col gap-2 rounded-2xl rounded-tl-sm bg-n-solid-1 px-3 py-3 shadow-sm dark:bg-n-slate-12"
  >
    <span class="sr-only">
      {{ t('CONVERSATION.AI_ASSISTANT_PANEL.LOADING') }}
    </span>

    <template v-if="!prefersReducedMotion">
      <div
        class="h-3 w-11/12 rounded bg-gradient-to-r from-purple-50 via-purple-100 to-purple-50 bg-[length:200%_100%] animate-shimmer dark:from-purple-900/20 dark:via-purple-800/40 dark:to-purple-900/20"
        aria-hidden="true"
      />
      <div
        class="h-3 w-9/12 rounded bg-gradient-to-r from-purple-50 via-purple-100 to-purple-50 bg-[length:200%_100%] animate-shimmer dark:from-purple-900/20 dark:via-purple-800/40 dark:to-purple-900/20 [animation-delay:150ms]"
        aria-hidden="true"
      />
      <div
        class="h-3 w-7/12 rounded bg-gradient-to-r from-purple-50 via-purple-100 to-purple-50 bg-[length:200%_100%] animate-shimmer dark:from-purple-900/20 dark:via-purple-800/40 dark:to-purple-900/20 [animation-delay:300ms]"
        aria-hidden="true"
      />
    </template>

    <template v-else>
      <div class="flex items-center gap-1.5" aria-hidden="true">
        <span class="size-2 rounded-full bg-purple-500 animate-pulse" />
        <span
          class="size-2 rounded-full bg-purple-500 animate-pulse [animation-delay:200ms]"
        />
        <span
          class="size-2 rounded-full bg-purple-500 animate-pulse [animation-delay:400ms]"
        />
      </div>
    </template>
  </div>
</template>
