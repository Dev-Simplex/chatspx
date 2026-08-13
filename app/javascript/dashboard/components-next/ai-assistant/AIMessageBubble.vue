<script setup>
import { computed, ref, toRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { toast } from 'vue-sonner';
import Icon from 'next/icon/Icon.vue';
import { useMarkdown } from './composables/useMarkdown';
import { useTypewriter } from './composables/useTypewriter';

/**
 * Renders a single bubble inside the AI Assistant chat history. Three
 * variants are supported:
 *
 *   - `user`       — agent's own prompt; right-aligned purple bubble.
 *   - `assistant`  — Captain reply with markdown rendering and action chips
 *                    (copy/apply/retry/feedback). Optionally streamed via
 *                    `useTypewriter` when `isStreaming` is true.
 *   - `thinking`   — placeholder shown while Captain is generating; renders
 *                    a sparkles icon + animated dots.
 *
 * a11y: the streaming output uses `aria-live="off"` to avoid flooding screen
 * readers token-by-token; once streaming completes a separate `role="status"`
 * region announces the short "Resposta gerada" string instead of replaying
 * the full body.
 */

const props = defineProps({
  type: {
    type: String,
    required: true,
    validator: v => ['user', 'assistant', 'thinking'].includes(v),
  },
  text: { type: String, default: '' },
  isStreaming: { type: Boolean, default: false },
  signal: { type: Object, default: null },
});

const emit = defineEmits([
  'copy',
  'apply',
  'retry',
  'feedback',
  'cancel-streaming',
]);

const { t } = useI18n();

const textRef = toRef(props, 'text');

// Typewriter for assistant streaming. When `isStreaming` is false we still
// expose the full text via the same composable so tests/snapshots are stable.
const { displayed, isDone, start, cancel } = useTypewriter(textRef, {
  mode: 'word',
  delay: 35,
  signal: props.signal,
});

watch(
  [() => props.type, () => props.isStreaming, () => props.text],
  () => {
    if (props.type !== 'assistant') return;
    if (props.isStreaming) {
      start();
    } else {
      cancel();
    }
  },
  { immediate: true }
);

const renderedText = computed(() => {
  if (props.type !== 'assistant') return props.text;
  if (props.isStreaming) return displayed.value;
  return props.text;
});
const renderedRef = computed(() => renderedText.value);
const renderRefForMarkdown = ref('');
watch(
  renderedRef,
  v => {
    renderRefForMarkdown.value = v;
  },
  { immediate: true }
);
const { html } = useMarkdown(renderRefForMarkdown);

// === Action handlers (assistant only) ===
const lastFeedbackAt = ref(0);

async function handleCopy() {
  try {
    if (navigator?.clipboard?.writeText) {
      await navigator.clipboard.writeText(props.text || '');
    }
    toast.success(t('AI_ASSISTANT_PANEL.TOAST.COPIED'));
    emit('copy');
  } catch {
    toast.error(t('AI_ASSISTANT_PANEL.TOAST.COPY_FAILED'), {
      important: true,
    });
  }
}

function handleApply() {
  emit('apply', props.text);
  toast.success(t('AI_ASSISTANT_PANEL.TOAST.APPLIED'));
}

function handleRetry() {
  emit('retry');
}

function handleFeedback(kind) {
  // Debounce 300ms so a double-tap or accidental double-click does not
  // emit twice.
  const now = Date.now();
  if (now - lastFeedbackAt.value < 300) return;
  lastFeedbackAt.value = now;
  emit('feedback', kind);
  toast.success(t('AI_ASSISTANT_PANEL.TOAST.FEEDBACK_SAVED'));
}

function handleCancelStreaming() {
  cancel();
  emit('cancel-streaming');
}

const showActions = computed(
  () => props.type === 'assistant' && !props.isStreaming && !!props.text
);
const showCancel = computed(
  () => props.type === 'assistant' && props.isStreaming
);
</script>

<template>
  <div
    class="flex w-full"
    :class="type === 'user' ? 'justify-end' : 'justify-start'"
  >
    <!-- User (agent) bubble -->
    <div
      v-if="type === 'user'"
      data-testid="ai-message-bubble-user"
      class="max-w-[85%] rounded-2xl rounded-tr-sm bg-n-violet-4 px-3 py-2 text-sm text-n-slate-12 shadow-sm dark:bg-n-violet-3"
    >
      <p class="whitespace-pre-wrap break-words leading-snug">{{ text }}</p>
    </div>

    <!-- Thinking placeholder -->
    <div
      v-else-if="type === 'thinking'"
      role="status"
      :aria-label="t('AI_ASSISTANT_PANEL.LOADING')"
      data-testid="ai-message-bubble-thinking"
      class="flex max-w-[85%] items-center gap-2 rounded-2xl rounded-tl-sm bg-n-solid-1 px-3 py-2 text-sm text-n-slate-11 shadow-sm dark:bg-n-slate-12"
    >
      <Icon
        icon="i-lucide-sparkles"
        class="size-4 animate-pulse text-n-violet-11"
        aria-hidden="true"
      />
      <span>{{ t('AI_ASSISTANT_PANEL.LOADING') }}</span>
      <span class="flex gap-0.5" aria-hidden="true">
        <span class="size-1 animate-bounce rounded-full bg-current" />
        <span
          class="size-1 animate-bounce rounded-full bg-current"
          style="animation-delay: 120ms"
        />
        <span
          class="size-1 animate-bounce rounded-full bg-current"
          style="animation-delay: 240ms"
        />
      </span>
    </div>

    <!-- Assistant bubble -->
    <div
      v-else
      data-testid="ai-message-bubble-assistant"
      class="flex max-w-[85%] flex-col gap-2 rounded-2xl rounded-tl-sm bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 shadow-sm dark:bg-n-slate-12"
    >
      <div class="flex items-center gap-1.5">
        <Icon
          icon="i-lucide-sparkles"
          class="size-3.5 text-n-violet-11"
          aria-hidden="true"
        />
        <span
          class="text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
        >
          Copilot
        </span>
      </div>

      <!-- Streaming body — silent for SR -->
      <div
        :aria-live="isStreaming ? 'off' : undefined"
        class="prose prose-sm max-w-none break-words text-n-slate-12 [&_a]:text-n-violet-11 [&_a]:underline [&_code]:rounded [&_code]:bg-n-slate-3 [&_code]:px-1 [&_code]:text-[12px] [&_p]:my-1 [&_ul]:my-1 [&_ol]:my-1"
        v-html="html"
      />

      <!-- "Resposta gerada" announcement once streaming finishes -->
      <span
        v-if="isStreaming && isDone"
        role="status"
        aria-live="polite"
        class="sr-only"
      >
        {{ t('AI_ASSISTANT_PANEL.STREAM_COMPLETE') }}
      </span>

      <div v-if="showCancel" class="flex justify-end">
        <button
          type="button"
          class="rounded-md border border-n-weak bg-transparent px-2 py-1 text-[11px] font-medium text-n-slate-11 transition-colors hover:bg-n-alpha-2 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-violet-8"
          @click="handleCancelStreaming"
        >
          {{ t('AI_ASSISTANT_PANEL.ACTIONS.CANCEL') }}
        </button>
      </div>

      <!-- Action chips -->
      <div v-if="showActions" class="-mb-1 flex flex-wrap items-center gap-1">
        <button
          type="button"
          :aria-label="t('AI_ASSISTANT_PANEL.ACTIONS.COPY')"
          class="inline-flex items-center gap-1 rounded-md px-2 py-1 text-[11px] font-medium text-n-slate-11 transition-colors hover:bg-n-alpha-2 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-violet-8"
          @click="handleCopy"
        >
          <Icon icon="i-lucide-copy" class="size-3.5" aria-hidden="true" />
          {{ t('AI_ASSISTANT_PANEL.ACTIONS.COPY') }}
        </button>
        <button
          type="button"
          :aria-label="t('AI_ASSISTANT_PANEL.ACTIONS.APPLY')"
          class="inline-flex items-center gap-1 rounded-md px-2 py-1 text-[11px] font-medium text-n-slate-11 transition-colors hover:bg-n-alpha-2 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-violet-8"
          @click="handleApply"
        >
          <Icon icon="i-lucide-pencil" class="size-3.5" aria-hidden="true" />
          {{ t('AI_ASSISTANT_PANEL.ACTIONS.APPLY') }}
        </button>
        <button
          type="button"
          :aria-label="t('AI_ASSISTANT_PANEL.ACTIONS.RETRY')"
          class="inline-flex items-center gap-1 rounded-md px-2 py-1 text-[11px] font-medium text-n-slate-11 transition-colors hover:bg-n-alpha-2 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-violet-8"
          @click="handleRetry"
        >
          <Icon
            icon="i-lucide-refresh-ccw"
            class="size-3.5"
            aria-hidden="true"
          />
          {{ t('AI_ASSISTANT_PANEL.ACTIONS.RETRY') }}
        </button>
        <span class="mx-0.5 h-3 w-px bg-n-weak" aria-hidden="true" />
        <button
          type="button"
          :aria-label="
            t('AI_ASSISTANT_PANEL.ACTIONS.FEEDBACK_GOOD')
          "
          class="inline-flex items-center gap-1 rounded-md px-1.5 py-1 text-[11px] font-medium text-n-slate-11 transition-colors hover:bg-n-alpha-2 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-violet-8"
          @click="handleFeedback('up')"
        >
          <span aria-hidden="true">👍</span>
          <span class="sr-only">
            {{ t('AI_ASSISTANT_PANEL.ACTIONS.FEEDBACK_GOOD') }}
          </span>
        </button>
        <button
          type="button"
          :aria-label="
            t('AI_ASSISTANT_PANEL.ACTIONS.FEEDBACK_BAD')
          "
          class="inline-flex items-center gap-1 rounded-md px-1.5 py-1 text-[11px] font-medium text-n-slate-11 transition-colors hover:bg-n-alpha-2 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-violet-8"
          @click="handleFeedback('down')"
        >
          <span aria-hidden="true">👎</span>
          <span class="sr-only">
            {{ t('AI_ASSISTANT_PANEL.ACTIONS.FEEDBACK_BAD') }}
          </span>
        </button>
      </div>
    </div>
  </div>
</template>
