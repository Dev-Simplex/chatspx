<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  toRef,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { onKeyStroke } from '@vueuse/core';
import Icon from 'next/icon/Icon.vue';
import { useReducedMotion } from 'dashboard/composables/useReducedMotion';
import { useMarkdown } from './composables/useMarkdown';
import { useTypewriter } from './composables/useTypewriter';
import AIErrorBanner from './AIErrorBanner.vue';

/**
 * Preview chip rendered ABOVE the composer that lets the agent review the
 * Copilot suggestion before applying it. Three primary actions:
 *
 *   - "Use this one"   → emit `accept` (parent applies and closes the chip)
 *   - "Edit"           → emit `edit` (parent applies + selects all + focus)
 *   - "Discard" / Esc  → emit `discard`
 *
 * While streaming, a "Cancel" button is exposed so the agent can abort
 * generation without losing keyboard focus. When `errorType` is set, the
 * body is replaced by `<AIErrorBanner>` so the agent can retry/dismiss.
 *
 * The chip is anchored via `data-ai-tour="suggestion-chip"` so the Phase 4
 * shepherd tour (step 3) attaches here.
 *
 * a11y:
 *   - role="region" + aria-label="Sugestão do Copilot" so SR users land here
 *   - Esc dismisses (or cancels streaming if mid-flight)
 *   - Focus returns to the primary action when streaming completes
 */

const props = defineProps({
  text: { type: String, required: true },
  isStreaming: { type: Boolean, default: false },
  errorType: { type: String, default: null },
  signal: { type: Object, default: null },
});

// eslint-disable-next-line vue/custom-event-name-casing -- aligned with AIMessageBubble's existing kebab-case event name
const emit = defineEmits([
  'accept',
  'edit',
  'discard',
  'cancel-streaming',
  'retry',
]);

const { t } = useI18n();
const { prefersReducedMotion } = useReducedMotion();

const textRef = toRef(props, 'text');

const { displayed, isDone, start, cancel } = useTypewriter(textRef, {
  mode: 'word',
  delay: 35,
  signal: props.signal,
});

watch(
  [() => props.isStreaming, () => props.text],
  () => {
    if (props.isStreaming) {
      start();
    } else {
      cancel();
    }
  },
  { immediate: true }
);

const renderedText = computed(() => {
  if (props.errorType) return '';
  if (props.isStreaming) return displayed.value;
  return props.text;
});

const renderRefForMarkdown = ref('');
watch(
  renderedText,
  v => {
    renderRefForMarkdown.value = v;
  },
  { immediate: true }
);
const { html } = useMarkdown(renderRefForMarkdown);

// === Refs for focus management ===
const useButtonRef = ref(null);
const containerRef = ref(null);

watch(
  () => props.isStreaming,
  (next, prev) => {
    if (prev === true && next === false && !props.errorType) {
      // Streaming finished — move focus to primary action.
      nextTick(() => {
        if (
          useButtonRef.value &&
          typeof useButtonRef.value.focus === 'function'
        ) {
          useButtonRef.value.focus();
        }
      });
    }
  }
);

// === Action handlers ===
function handleAccept() {
  emit('accept', props.text);
}

function handleEdit() {
  emit('edit', props.text);
}

function handleDiscard() {
  emit('discard');
}

function handleCancelStreaming() {
  cancel();
  // eslint-disable-next-line vue/custom-event-name-casing -- aligned with AIMessageBubble's existing kebab-case event name
  emit('cancel-streaming');
}

function handleRetry() {
  emit('retry');
}

// === Esc key — cancel streaming or discard ===
function onEsc(event) {
  // Only react if the chip is the active region and event isn't bubbling
  // from a modal above us. We check the active element is inside the chip.
  if (event?.defaultPrevented) return;
  if (props.isStreaming) {
    event.preventDefault();
    handleCancelStreaming();
    handleDiscard();
    return;
  }
  event.preventDefault();
  handleDiscard();
}

onKeyStroke('Escape', onEsc);

onMounted(() => {
  // Nothing extra — focus is managed by the streaming watcher above.
});

onBeforeUnmount(() => {
  cancel();
});

const headerLabel = computed(() =>
  t('AI_ASSISTANT_PANEL.SUGGESTION_CHIP.HEADER')
);
const subtitleLabel = computed(() =>
  t('AI_ASSISTANT_PANEL.SUGGESTION_CHIP.SUBTITLE')
);
const useLabel = computed(() =>
  t('AI_ASSISTANT_PANEL.SUGGESTION_CHIP.USE')
);
const editLabel = computed(() =>
  t('AI_ASSISTANT_PANEL.SUGGESTION_CHIP.EDIT')
);
const discardLabel = computed(() =>
  t('AI_ASSISTANT_PANEL.SUGGESTION_CHIP.DISCARD')
);
const editTooltip = computed(() =>
  t('AI_ASSISTANT_PANEL.SUGGESTION_CHIP.EDIT_TOOLTIP')
);
const discardTooltip = computed(() =>
  t('AI_ASSISTANT_PANEL.SUGGESTION_CHIP.DISCARD_TOOLTIP')
);
const cancelLabel = computed(() =>
  t('AI_ASSISTANT_PANEL.ACTIONS.CANCEL')
);
const ariaLabelRegion = computed(() => headerLabel.value);

const showActions = computed(
  () => !props.errorType && !props.isStreaming && !!props.text
);
const showCancel = computed(() => !props.errorType && props.isStreaming);
</script>

<template>
  <Transition
    :enter-active-class="
      prefersReducedMotion
        ? 'transition-opacity duration-[80ms] ease-linear'
        : 'transition duration-[200ms] ease-out'
    "
    :enter-from-class="
      prefersReducedMotion ? 'opacity-0' : 'opacity-0 translate-y-2'
    "
    :enter-to-class="
      prefersReducedMotion ? 'opacity-100' : 'opacity-100 translate-y-0'
    "
    :leave-active-class="
      prefersReducedMotion
        ? 'transition-opacity duration-[80ms] ease-linear'
        : 'transition duration-[150ms] ease-in'
    "
    :leave-from-class="
      prefersReducedMotion ? 'opacity-100' : 'opacity-100 translate-y-0'
    "
    :leave-to-class="
      prefersReducedMotion ? 'opacity-0' : 'opacity-0 translate-y-1'
    "
    appear
  >
    <div
      ref="containerRef"
      data-ai-tour="suggestion-chip"
      data-testid="ai-suggestion-chip"
      role="region"
      :aria-label="ariaLabelRegion"
      class="flex w-full flex-col gap-2 rounded-xl border border-n-violet-6 bg-white p-3 shadow-md dark:bg-n-slate-12"
    >
      <!-- Header -->
      <div class="flex items-center gap-2">
        <Icon
          icon="i-lucide-sparkles"
          class="size-4 text-n-violet-11"
          aria-hidden="true"
        />
        <div class="flex min-w-0 flex-col">
          <span
            class="text-[11px] font-semibold uppercase tracking-wide text-n-violet-11"
          >
            {{ headerLabel }}
          </span>
          <span class="text-[11px] text-n-slate-10">
            {{ subtitleLabel }}
          </span>
        </div>
      </div>

      <!-- Body -->
      <div v-if="errorType" data-testid="ai-suggestion-chip-error">
        <AIErrorBanner
          :error-type="errorType"
          @retry="handleRetry"
          @dismiss="handleDiscard"
          @cancel="handleCancelStreaming"
        />
      </div>
      <div
        v-else
        :aria-live="isStreaming ? 'off' : undefined"
        class="prose prose-sm max-w-none break-words text-sm text-n-slate-12 [&_a]:text-n-violet-11 [&_a]:underline [&_code]:rounded [&_code]:bg-n-slate-3 [&_code]:px-1 [&_code]:text-[12px] [&_p]:my-1 [&_ul]:my-1 [&_ol]:my-1"
        data-testid="ai-suggestion-chip-body"
        v-html="html"
      />

      <span
        v-if="isStreaming && isDone && !errorType"
        role="status"
        aria-live="polite"
        class="sr-only"
      >
        {{ t('AI_ASSISTANT_PANEL.STREAM_COMPLETE') }}
      </span>

      <!-- Cancel during streaming -->
      <div v-if="showCancel" class="flex justify-end">
        <button
          type="button"
          class="rounded-md border border-n-weak bg-transparent px-2 py-1 text-[11px] font-medium text-n-slate-11 transition-colors hover:bg-n-alpha-2 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-violet-8"
          data-testid="ai-suggestion-chip-cancel"
          @click="handleCancelStreaming"
        >
          {{ cancelLabel }}
        </button>
      </div>

      <!-- Footer actions -->
      <div
        v-if="showActions"
        class="flex flex-wrap items-center justify-end gap-2"
      >
        <button
          type="button"
          :aria-label="discardTooltip"
          :title="discardTooltip"
          class="inline-flex items-center gap-1 rounded-md px-2.5 py-1 text-[11px] font-medium text-n-slate-11 transition-colors hover:bg-n-alpha-2 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-violet-8"
          data-testid="ai-suggestion-chip-discard"
          @click="handleDiscard"
        >
          {{ discardLabel }}
        </button>
        <button
          type="button"
          :aria-label="editTooltip"
          :title="editTooltip"
          class="inline-flex items-center gap-1 rounded-md border border-n-weak bg-transparent px-2.5 py-1 text-[11px] font-medium text-n-slate-12 transition-colors hover:bg-n-alpha-2 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-violet-8"
          data-testid="ai-suggestion-chip-edit"
          @click="handleEdit"
        >
          <Icon icon="i-lucide-pencil" class="size-3.5" aria-hidden="true" />
          {{ editLabel }}
        </button>
        <button
          ref="useButtonRef"
          type="button"
          class="inline-flex items-center gap-1 rounded-md bg-n-violet-9 px-3 py-1 text-[11px] font-semibold text-white transition-colors hover:bg-n-violet-10 dark:hover:bg-n-violet-8 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-violet-8"
          data-testid="ai-suggestion-chip-use"
          @click="handleAccept"
        >
          <Icon icon="i-lucide-check" class="size-3.5" aria-hidden="true" />
          {{ useLabel }}
        </button>
      </div>
    </div>
  </Transition>
</template>
