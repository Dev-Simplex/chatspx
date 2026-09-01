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
 * Prévia da sugestão do copiloto ACIMA do composer, para o agente revisar
 * antes de enviar. Três ações principais:
 *
 *   - "Usar essa"      → emite `accept` (o pai aplica e fecha a prévia)
 *   - "Editar"         → emite `edit` (o pai aplica + seleciona tudo + foca)
 *   - "Descartar"/Esc  → emite `discard`
 *
 * Durante o streaming aparece "Parar", para abortar sem perder o foco de
 * teclado. Com `errorType`, o corpo dá lugar ao `<AIErrorBanner>`.
 *
 * Visual: mesmo vocabulário monocromático do fio do copiloto
 * (public/mockups/copiloto-v2.html). A sugestão fica em texto solto, sem
 * bolha; a única ação pintada é a primária, e ela é preta/branca — o verde e
 * o roxo ficam para a conversa do cliente, ao lado.
 *
 * Ancorada por `data-ai-tour="suggestion-chip"` para o passo 3 do tour.
 *
 * a11y:
 *   - role="region" + aria-label="Sugestão do Copilot"
 *   - Esc descarta (ou cancela o streaming, se estiver no meio)
 *   - o foco volta para a ação primária quando o streaming termina
 */

const props = defineProps({
  text: { type: String, required: true },
  isStreaming: { type: Boolean, default: false },
  errorType: { type: String, default: null },
  signal: { type: Object, default: null },
  /** Fonte citada — mesmo chip discreto do fio do copiloto. */
  sources: { type: Array, default: () => [] },
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

const normalizedSources = computed(() =>
  (props.sources || [])
    .map((source, index) => {
      if (!source) return null;
      if (typeof source === 'string') {
        return { key: `src-${index}`, label: source };
      }
      const label = source.label || source.title || source.name || '';
      if (!label) return null;
      return { key: String(source.id ?? `src-${index}`), label };
    })
    .filter(Boolean)
);

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
  t('CONVERSATION.AI_ASSISTANT_PANEL.SUGGESTION_CHIP.HEADER')
);
const subtitleLabel = computed(() =>
  t('CONVERSATION.AI_ASSISTANT_PANEL.SUGGESTION_CHIP.SUBTITLE')
);
const useLabel = computed(() =>
  t('CONVERSATION.AI_ASSISTANT_PANEL.SUGGESTION_CHIP.USE')
);
const editLabel = computed(() =>
  t('CONVERSATION.AI_ASSISTANT_PANEL.SUGGESTION_CHIP.EDIT')
);
const discardLabel = computed(() =>
  t('CONVERSATION.AI_ASSISTANT_PANEL.SUGGESTION_CHIP.DISCARD')
);
const editTooltip = computed(() =>
  t('CONVERSATION.AI_ASSISTANT_PANEL.SUGGESTION_CHIP.EDIT_TOOLTIP')
);
const discardTooltip = computed(() =>
  t('CONVERSATION.AI_ASSISTANT_PANEL.SUGGESTION_CHIP.DISCARD_TOOLTIP')
);
const stopLabel = computed(() =>
  t('CONVERSATION.AI_ASSISTANT_PANEL.ACTIONS.STOP')
);
const ariaLabelRegion = computed(() => headerLabel.value);

const showActions = computed(
  () => !props.errorType && !props.isStreaming && !!props.text
);
const showCancel = computed(() => !props.errorType && props.isStreaming);

// Ação secundária: 30px de altura, sem preenchimento, hover só no fundo.
const GHOST_ACTION_CLASS =
  'inline-flex h-[30px] items-center gap-1.5 rounded-[7px] border-0 bg-transparent px-[11px] text-[12.5px] font-medium text-[var(--oa-ink-2)] transition-colors hover:bg-[var(--oa-hover)] hover:text-[var(--oa-ink)] focus:outline-none focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-[var(--oa-focus)]';
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
      class="flex w-full flex-col gap-2 rounded-xl border border-[var(--oa-line)] bg-[var(--oa-bg)] p-3 shadow-sm"
    >
      <!-- Header -->
      <div class="flex items-center gap-2">
        <Icon
          icon="i-lucide-sparkles"
          class="size-3.5 shrink-0 text-[var(--oa-ink-2)]"
          aria-hidden="true"
        />
        <div class="flex min-w-0 flex-wrap items-baseline gap-x-2">
          <span class="text-xs font-semibold text-[var(--oa-ink)]">
            {{ headerLabel }}
          </span>
          <span class="text-[11px] text-[var(--oa-ink-2)]">
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
        class="oa-prose max-w-full"
        data-testid="ai-suggestion-chip-body"
        v-html="html"
      />

      <!-- Fonte citada -->
      <div
        v-if="!errorType && normalizedSources.length"
        class="flex flex-wrap gap-2"
      >
        <span
          v-for="source in normalizedSources"
          :key="source.key"
          data-testid="ai-suggestion-chip-source"
          class="inline-flex max-w-full items-center gap-1.5 rounded-lg border border-[var(--oa-line)] px-2.5 py-1 text-[11.5px] text-[var(--oa-ink-2)]"
        >
          <Icon
            icon="i-lucide-file-text"
            class="size-3 shrink-0"
            aria-hidden="true"
          />
          <span class="truncate">{{ source.label }}</span>
        </span>
      </div>

      <span
        v-if="isStreaming && isDone && !errorType"
        role="status"
        aria-live="polite"
        class="sr-only"
      >
        {{ t('CONVERSATION.AI_ASSISTANT_PANEL.STREAM_COMPLETE') }}
      </span>

      <!-- Parar, durante o streaming -->
      <div v-if="showCancel" class="flex justify-end">
        <button
          type="button"
          :class="GHOST_ACTION_CLASS"
          data-testid="ai-suggestion-chip-cancel"
          @click="handleCancelStreaming"
        >
          <Icon icon="i-lucide-square" class="size-3" aria-hidden="true" />
          {{ stopLabel }}
        </button>
      </div>

      <!-- Footer actions -->
      <div
        v-if="showActions"
        class="flex flex-wrap items-center justify-end gap-1"
      >
        <button
          type="button"
          :aria-label="discardTooltip"
          :title="discardTooltip"
          :class="GHOST_ACTION_CLASS"
          data-testid="ai-suggestion-chip-discard"
          @click="handleDiscard"
        >
          {{ discardLabel }}
        </button>
        <button
          type="button"
          :aria-label="editTooltip"
          :title="editTooltip"
          :class="GHOST_ACTION_CLASS"
          data-testid="ai-suggestion-chip-edit"
          @click="handleEdit"
        >
          <Icon icon="i-lucide-pencil" class="size-3.5" aria-hidden="true" />
          {{ editLabel }}
        </button>
        <button
          ref="useButtonRef"
          type="button"
          class="inline-flex h-[30px] items-center gap-1.5 rounded-[7px] bg-[var(--oa-send)] px-[11px] text-[12.5px] font-medium text-[var(--oa-send-ink)] transition-opacity hover:opacity-85 focus:outline-none focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-[var(--oa-focus)]"
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
