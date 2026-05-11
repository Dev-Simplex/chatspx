<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  Dialog,
  DialogPanel,
  DialogTitle,
  TransitionRoot,
  TransitionChild,
} from '@headlessui/vue';
import { onKeyStroke, useMediaQuery } from '@vueuse/core';
import { toast } from 'vue-sonner';
import { useTrack } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useReducedMotion } from 'dashboard/composables/useReducedMotion';
import { useCaptain } from 'dashboard/composables/useCaptain';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { CAPTAIN_ERROR_TYPES } from 'dashboard/composables/captain/constants';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import Icon from 'next/icon/Icon.vue';

import AIQuickPromptCard from './AIQuickPromptCard.vue';
import AIMessageBubble from './AIMessageBubble.vue';
import AIErrorBanner from './AIErrorBanner.vue';
import AILoadingShimmer from './AILoadingShimmer.vue';
import AISmartBanner from './AISmartBanner.vue';
import { useAIErrorState } from './composables/useAIErrorState';
import { useAITour } from './composables/useAITour';
import { useSmartSuggestions } from './composables/useSmartSuggestions';

/**
 * AI Assistant panel — Phase 3 redesign.
 *
 * Slides in from the right as a Headless UI Dialog (focus trap + escape +
 * focus return are managed by the lib). On viewports < 375px we render a
 * full-screen modal instead of a slide-in. The body offers three quick
 * prompt sections (Understand / Rewrite / Create) wired to `useCaptain`,
 * a streaming chat history backed by `AIMessageBubble`, and a textarea
 * footer for free-form prompts.
 *
 * The panel is mounted by `Dashboard.vue` only when `aiAssistantFlag` is
 * true (mutex with the legacy `CopilotContainer`). Open/close state is
 * mirrored to `uiSettings.is_copilot_panel_open` so the existing 8 entry
 * points keep working unchanged.
 */

const props = defineProps({
  open: { type: Boolean, default: false },
  applyToComposer: { type: Function, default: null },
});

const emit = defineEmits(['close', 'apply']);

const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();
const { processEvent, currentChat } = useCaptain();
const { prefersReducedMotion } = useReducedMotion();
const errorState = useAIErrorState();
const aiTour = useAITour();
const { activeSuggestion, dismiss: dismissSuggestion } =
  useSmartSuggestions(currentChat);

const currentUser = useMapGetter('getCurrentUser');
const agentName = computed(() => {
  const name = currentUser.value?.name || currentUser.value?.available_name;
  if (!name) return '';
  return String(name).split(' ')[0];
});

// === Responsive: full-screen modal under 375px ===
const isVeryNarrow = useMediaQuery('(max-width: 374px)');

// === Quick prompt sections ===
const replyMode = useMapGetter('draftMessages/getReplyEditorMode');
const isPrivateMode = computed(() => replyMode.value === 'NOTE');
const messagesCount = computed(() => {
  return Array.isArray(currentChat.value?.messages)
    ? currentChat.value.messages.length
    : 0;
});
const hasMessages = computed(() => messagesCount.value > 0);

const sections = computed(() => [
  {
    id: 'understand',
    title: t('CONVERSATION.AI_ASSISTANT_PANEL.SECTIONS.UNDERSTAND'),
    items: [
      {
        id: 'sentiment',
        action: 'sentiment',
        icon: 'i-lucide-smile',
        label: t('CONVERSATION.AI_ASSISTANT_PANEL.PROMPTS.SENTIMENT.LABEL'),
        description: t(
          'CONVERSATION.AI_ASSISTANT_PANEL.PROMPTS.SENTIMENT.DESCRIPTION'
        ),
      },
      {
        id: 'summarize',
        action: 'summarize',
        icon: 'i-lucide-file-text',
        label: t('CONVERSATION.AI_ASSISTANT_PANEL.PROMPTS.SUMMARIZE.LABEL'),
        description: t(
          'CONVERSATION.AI_ASSISTANT_PANEL.PROMPTS.SUMMARIZE.DESCRIPTION'
        ),
      },
    ],
  },
  {
    id: 'create',
    title: t('CONVERSATION.AI_ASSISTANT_PANEL.SECTIONS.CREATE'),
    items: [
      {
        id: 'reply_suggestion',
        action: 'reply_suggestion',
        icon: 'i-lucide-lightbulb',
        label: t(
          'CONVERSATION.AI_ASSISTANT_PANEL.PROMPTS.REPLY_SUGGESTION.LABEL'
        ),
        description: t(
          'CONVERSATION.AI_ASSISTANT_PANEL.PROMPTS.REPLY_SUGGESTION.DESCRIPTION'
        ),
      },
    ],
  },
]);

// === Chat history (panel-local) ===
const history = ref([]); // { id, type: 'user'|'assistant'|'thinking', text, isStreaming }
const isLoading = ref(false);
let abortController = null;
let nextId = 1;

function pushMessage(message) {
  const id = nextId;
  nextId += 1;
  history.value = [...history.value, { id, ...message }];
}

function removeThinking() {
  history.value = history.value.filter(m => m.type !== 'thinking');
}

function scrollToBottom() {
  nextTick(() => {
    const el = document.querySelector('[data-ai-panel-scroll]');
    if (el) el.scrollTop = el.scrollHeight;
  });
}

// === Captain dispatch ===
async function runAction({ action, label }) {
  if (isLoading.value) return;
  if (isPrivateMode.value) {
    // Defense-in-depth — useCaptain also guards this
    toast.error(
      t('CONVERSATION.AI_ASSISTANT_PANEL.TOAST.PRIVATE_MODE_BLOCKED'),
      {
        important: true,
      }
    );
    return;
  }
  errorState.clear();
  abortController?.abort();
  abortController = new AbortController();

  pushMessage({ type: 'user', text: label, isStreaming: false });
  pushMessage({ type: 'thinking', text: '', isStreaming: false });
  isLoading.value = true;

  useTrack('ai.action.triggered', {
    action,
    surface: 'panel',
    conversation_id: currentChat.value?.id,
  });

  try {
    const { message, errorType } = await processEvent(action, '', {
      signal: abortController.signal,
    });
    removeThinking();

    if (errorType === CAPTAIN_ERROR_TYPES.PRIVATE_MODE_BLOCKED) {
      isLoading.value = false;
      return;
    }
    if (errorType === CAPTAIN_ERROR_TYPES.ABORTED) {
      isLoading.value = false;
      return;
    }
    if (errorType === CAPTAIN_ERROR_TYPES.EMPTY_RESPONSE) {
      errorState.setEmpty();
      isLoading.value = false;
      return;
    }
    if (errorType === CAPTAIN_ERROR_TYPES.RATE_LIMIT) {
      errorState.errorType.value = 'rate_limit';
      isLoading.value = false;
      return;
    }
    if (errorType === CAPTAIN_ERROR_TYPES.TIMEOUT) {
      errorState.errorType.value = 'timeout';
      isLoading.value = false;
      return;
    }
    if (errorType === CAPTAIN_ERROR_TYPES.CAPTAIN_UNSTABLE) {
      errorState.errorType.value = 'captain_unstable';
      isLoading.value = false;
      return;
    }
    if (errorType === CAPTAIN_ERROR_TYPES.NETWORK) {
      errorState.errorType.value = 'network';
      isLoading.value = false;
      return;
    }
    if (errorType) {
      // Unknown error: surface generic captain_unstable banner
      errorState.errorType.value = 'captain_unstable';
      isLoading.value = false;
      return;
    }

    pushMessage({ type: 'assistant', text: message, isStreaming: true });
  } catch {
    removeThinking();
    errorState.errorType.value = 'captain_unstable';
  } finally {
    isLoading.value = false;
    scrollToBottom();
  }
}

const lastAction = ref(null);
async function runQuickPrompt(item) {
  lastAction.value = item;
  await runAction({ action: item.action, label: item.label });
}

// === Smart banner handlers (Phase 5) ===
const bannerShownAt = ref(null);

function suggestionToLabel(suggestion) {
  if (!suggestion) return '';
  return t(suggestion.textKey, suggestion.textParams || {});
}

function handleSuggestionAction(suggestion) {
  if (!suggestion) return;
  const elapsed = bannerShownAt.value ? Date.now() - bannerShownAt.value : 0;
  useTrack('ai.banner.clicked', {
    banner_type: suggestion.id,
    time_to_click_ms: elapsed,
    conversation_id: currentChat.value?.id,
  });
  const label = suggestionToLabel(suggestion);
  // Dispatch the same action surface as a quick prompt so the response flows
  // through the chat history + apply-to-composer pipeline.
  runAction({ action: suggestion.action, label });
  lastAction.value = { action: suggestion.action, label };
}

function handleSuggestionDismiss(suggestion) {
  if (!suggestion) return;
  dismissSuggestion(suggestion.id);
  useTrack('ai.banner.dismissed', {
    banner_type: suggestion.id,
    conversation_id: currentChat.value?.id,
  });
  toast(t('CONVERSATION.AI_ASSISTANT_PANEL.SMART_BANNER.DISMISSED_TOAST'));
}

watch(
  activeSuggestion,
  (next, prev) => {
    if (next && next?.id !== prev?.id) {
      bannerShownAt.value = Date.now();
      useTrack('ai.banner.shown', {
        banner_type: next.id,
        conversation_id: currentChat.value?.id,
        msg_count: Array.isArray(currentChat.value?.messages)
          ? currentChat.value.messages.length
          : 0,
      });
    } else if (!next) {
      bannerShownAt.value = null;
    }
  },
  { immediate: true }
);

function retryLastAction() {
  if (!lastAction.value) return;
  errorState.clear();
  runAction({
    action: lastAction.value.action,
    label: lastAction.value.label,
  });
}

// === Free-form prompt textarea ===
const draftPrompt = ref('');
const textareaRef = ref(null);

function adjustTextareaHeight() {
  if (!textareaRef.value) return;
  textareaRef.value.style.height = 'auto';
  textareaRef.value.style.height = `${Math.min(
    textareaRef.value.scrollHeight,
    160
  )}px`;
}

async function sendPrompt() {
  const value = draftPrompt.value.trim();
  if (!value || isLoading.value) return;
  if (isPrivateMode.value) {
    toast.error(
      t('CONVERSATION.AI_ASSISTANT_PANEL.TOAST.PRIVATE_MODE_BLOCKED'),
      {
        important: true,
      }
    );
    return;
  }
  draftPrompt.value = '';
  await nextTick();
  adjustTextareaHeight();
  await runAction({ action: 'reply_suggestion', label: value });
  // Persist as last action so retry from error banner works
  lastAction.value = { action: 'reply_suggestion', label: value };
}

function handleKeydown(event) {
  if (event.isComposing) return;
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault();
    sendPrompt();
  }
}

// === Action handlers from bubbles ===
function handleApply(text) {
  if (typeof props.applyToComposer === 'function') {
    props.applyToComposer(text);
  }
  emit('apply', text);
  useTrack('ai.response.applied', {
    conversation_id: currentChat.value?.id,
  });
  // First-time guided tour fires only after the agent applies an AI
  // response — never on first login. Resume disabled here so the agent
  // always sees step 1 the first time.
  if (!aiTour.isCompleted()) {
    nextTick(() => aiTour.startTour({ resume: false }));
  }
}

function handleCopy() {
  useTrack('ai.response.copied', {
    conversation_id: currentChat.value?.id,
  });
}

function handleRetry() {
  retryLastAction();
}

function handleFeedback(kind) {
  useTrack('ai.response.feedback', {
    kind,
    conversation_id: currentChat.value?.id,
  });
}

function handleCancelStreaming() {
  abortController?.abort();
  abortController = null;
}

// === Open / close lifecycle ===
function close(reason = 'user') {
  abortController?.abort();
  abortController = null;
  errorState.clear();
  removeThinking();
  emit('close', reason);
  useTrack('ai.panel.closed', { reason });
}

function closeFromUISettings() {
  // Mirrors the legacy CopilotContainer: clears the global flag.
  updateUISettings({
    is_copilot_panel_open: false,
  });
  close('user');
}

watch(
  () => currentChat.value?.id,
  (newId, oldId) => {
    if (newId !== oldId) {
      // New conversation — abort and clear local panel state.
      abortController?.abort();
      abortController = null;
      history.value = [];
      errorState.clear();
      lastAction.value = null;
    }
  }
);

watch(
  () => props.open,
  isOpen => {
    if (isOpen) {
      useTrack('ai.panel.opened', {
        conversation_id: currentChat.value?.id,
      });
      // If a tour was paused mid-flow (Esc/X without Skip), resume it on
      // the next panel open so the agent doesn't lose the walkthrough.
      if (!aiTour.isCompleted() && aiTour.isActive.value === false) {
        try {
          const stepRaw = window?.localStorage?.getItem('chatspx_ai_tour_step');
          const step = parseInt(stepRaw, 10);
          if (Number.isInteger(step) && step >= 1) {
            nextTick(() => aiTour.startTour({ resume: true }));
          }
        } catch {
          /* ignore */
        }
      }
    }
  }
);

// === Global shortcut: Ctrl+J toggles the panel ===
// Ctrl+/ was the original choice but `$mod+Slash` is already taken by the
// sidebar's keyboard-shortcut help modal (`useSidebarKeyboardShortcuts`).
// Ctrl+J is unused at the global level (only `Alt+KeyJ` exists, in
// `useChatListKeyboardEvents`) so it's a safe canonical binding for "open
// AI Assistant".
onKeyStroke(
  e => (e.ctrlKey || e.metaKey) && (e.key === 'j' || e.key === 'J'),
  e => {
    e.preventDefault();
    const isOpenNow = uiSettings.value?.is_copilot_panel_open;
    updateUISettings({ is_copilot_panel_open: !isOpenNow });
  }
);

onBeforeUnmount(() => {
  abortController?.abort();
  abortController = null;
});

const placeholderText = computed(() =>
  t('CONVERSATION.AI_ASSISTANT_PANEL.TEXTAREA.PLACEHOLDER')
);

const showEdgeCaseEmpty = computed(
  () => !hasMessages.value && messagesCount.value === 0
);
const showEdgeCasePrivate = computed(() => isPrivateMode.value);
const showEdgeCaseLong = computed(() => messagesCount.value >= 1000);

// WhatsApp 24h messaging window expirou — sinaliza visualmente que algumas
// acoes ficam indisponiveis ate o agente reconectar a sessao. Usa o mesmo
// sinal que o ReplyBox (`can_reply === false` em inbox WhatsApp) para
// manter coerencia entre composer e painel.
const showEdgeCaseWhatsappExpired = computed(() => {
  const inbox = currentChat.value?.meta?.channel
    ? currentChat.value.meta
    : currentChat.value?.inbox;
  const channelType =
    inbox?.channel_type ||
    currentChat.value?.inbox?.channel_type ||
    currentChat.value?.meta?.channel;
  const isWhatsApp = channelType === INBOX_TYPES.WHATSAPP;
  if (!isWhatsApp) return false;
  // can_reply === false (em conversation OU inbox) indica janela expirada.
  const canReply =
    currentChat.value?.can_reply !== undefined
      ? currentChat.value.can_reply
      : true;
  return canReply === false;
});
</script>

<template>
  <TransitionRoot :show="open" appear as="template">
    <Dialog
      :static="false"
      class="relative z-[60]"
      lang="pt-BR"
      @close="closeFromUISettings"
    >
      <!-- Backdrop -->
      <TransitionChild
        as="template"
        :enter="
          prefersReducedMotion
            ? 'transition-opacity duration-[120ms] ease-linear'
            : 'transition-opacity duration-[200ms] ease-out'
        "
        enter-from="opacity-0"
        enter-to="opacity-100"
        :leave="
          prefersReducedMotion
            ? 'transition-opacity duration-[120ms] ease-linear'
            : 'transition-opacity duration-[160ms] ease-in'
        "
        leave-from="opacity-100"
        leave-to="opacity-0"
      >
        <div
          class="fixed inset-0 bg-black/30 backdrop-blur-[1px] dark:bg-black/50"
          aria-hidden="true"
        />
      </TransitionChild>

      <!-- Panel container -->
      <div
        class="fixed inset-0 flex items-stretch"
        :class="isVeryNarrow ? 'justify-center' : 'justify-end'"
      >
        <TransitionChild
          as="template"
          :enter="
            prefersReducedMotion
              ? 'transition-opacity duration-[120ms] ease-linear'
              : 'transition-transform duration-[280ms] ease-[cubic-bezier(0.16,1,0.3,1)]'
          "
          :enter-from="
            prefersReducedMotion
              ? 'opacity-0'
              : isVeryNarrow
                ? 'opacity-0'
                : 'translate-x-full'
          "
          :enter-to="
            prefersReducedMotion ? 'opacity-100' : 'translate-x-0 opacity-100'
          "
          :leave="
            prefersReducedMotion
              ? 'transition-opacity duration-[120ms] ease-linear'
              : 'transition-transform duration-[220ms] ease-in'
          "
          :leave-from="
            prefersReducedMotion ? 'opacity-100' : 'translate-x-0 opacity-100'
          "
          :leave-to="
            prefersReducedMotion ? 'opacity-0' : 'translate-x-full opacity-0'
          "
        >
          <DialogPanel
            class="flex h-full flex-col bg-n-solid-1 shadow-2xl ltr:border-l rtl:border-r border-n-weak"
            :class="
              isVeryNarrow
                ? 'w-screen'
                : 'w-full max-w-[360px] sm:max-w-[400px]'
            "
          >
            <!-- Header -->
            <header
              class="flex h-14 shrink-0 items-center justify-between gap-3 border-b border-n-weak bg-n-solid-1 px-4"
            >
              <div class="flex items-center gap-2 min-w-0">
                <Icon
                  icon="i-lucide-sparkles"
                  class="size-5 text-purple-600 dark:text-purple-300"
                  aria-hidden="true"
                />
                <DialogTitle
                  class="truncate text-sm font-semibold text-n-slate-12"
                >
                  {{ t('CONVERSATION.AI_ASSISTANT_PANEL.TITLE') }}
                </DialogTitle>
              </div>
              <button
                type="button"
                :aria-label="t('CONVERSATION.AI_ASSISTANT_PANEL.CLOSE')"
                class="inline-flex size-8 items-center justify-center rounded-md text-n-slate-11 transition-colors hover:bg-n-alpha-2 focus:outline-none focus-visible:ring-2 focus-visible:ring-purple-400"
                @click="closeFromUISettings"
              >
                <Icon icon="i-lucide-x" class="size-4" aria-hidden="true" />
              </button>
            </header>

            <!-- Body (scrollable) -->
            <div
              data-ai-panel-scroll
              class="flex flex-1 flex-col gap-4 overflow-y-auto bg-n-slate-2/60 px-4 py-4 dark:bg-n-solid-2"
            >
              <!-- Empty / first-time state -->
              <section
                v-if="!history.length"
                class="flex flex-col gap-4"
                aria-labelledby="ai-panel-empty-title"
              >
                <div class="flex flex-col items-start gap-1">
                  <h2
                    id="ai-panel-empty-title"
                    class="text-base font-semibold text-n-slate-12"
                  >
                    <span aria-hidden="true">{{
                      t('CONVERSATION.AI_ASSISTANT_PANEL.EMPTY.GREETING_EMOJI')
                    }}</span>
                    {{
                      agentName
                        ? t(
                            'CONVERSATION.AI_ASSISTANT_PANEL.EMPTY.GREETING_NAMED',
                            { name: agentName }
                          )
                        : t(
                            'CONVERSATION.AI_ASSISTANT_PANEL.EMPTY.GREETING_GENERIC'
                          )
                    }}
                  </h2>
                  <p class="text-xs text-n-slate-10">
                    {{ t('CONVERSATION.AI_ASSISTANT_PANEL.EMPTY.SUBTITLE') }}
                  </p>
                </div>

                <!-- Smart banner — Phase 5 (long thread / sentiment / waiting) -->
                <AISmartBanner
                  v-if="activeSuggestion"
                  :suggestion="activeSuggestion"
                  @action="handleSuggestionAction"
                  @dismiss="handleSuggestionDismiss"
                />
                <slot name="smartBanner" />

                <!-- Edge cases -->
                <div
                  v-if="showEdgeCaseEmpty"
                  class="rounded-lg border border-n-weak bg-n-alpha-2 p-3 text-xs text-n-slate-11"
                >
                  <p class="font-semibold text-n-slate-12">
                    {{
                      t(
                        'CONVERSATION.AI_ASSISTANT_PANEL.EDGE_CASES.EMPTY_CONVERSATION_TITLE'
                      )
                    }}
                  </p>
                  <p class="mt-0.5">
                    {{
                      t(
                        'CONVERSATION.AI_ASSISTANT_PANEL.EDGE_CASES.EMPTY_CONVERSATION_BODY'
                      )
                    }}
                  </p>
                </div>

                <div
                  v-if="showEdgeCasePrivate"
                  class="rounded-lg border border-amber-300 bg-amber-50 p-3 text-xs text-amber-900 dark:border-amber-800/40 dark:bg-amber-950/30 dark:text-amber-100"
                >
                  <p class="font-semibold">
                    {{
                      t(
                        'CONVERSATION.AI_ASSISTANT_PANEL.EDGE_CASES.PRIVATE_MODE_TITLE'
                      )
                    }}
                  </p>
                  <p class="mt-0.5">
                    {{
                      t(
                        'CONVERSATION.AI_ASSISTANT_PANEL.EDGE_CASES.PRIVATE_MODE_BODY'
                      )
                    }}
                  </p>
                </div>

                <div
                  v-if="showEdgeCaseWhatsappExpired"
                  class="flex items-start gap-2 rounded-lg border border-amber-300 bg-amber-50 p-3 text-xs text-amber-900 dark:border-amber-800/40 dark:bg-amber-950/30 dark:text-amber-100"
                >
                  <Icon
                    icon="i-lucide-wifi-off"
                    class="mt-0.5 size-4 shrink-0 text-amber-600 dark:text-amber-300"
                    aria-hidden="true"
                  />
                  <div class="flex min-w-0 flex-1 flex-col gap-0.5">
                    <p class="font-semibold">
                      {{
                        t(
                          'CONVERSATION.AI_ASSISTANT_PANEL.EDGE_CASES.WHATSAPP_EXPIRED_TITLE'
                        )
                      }}
                    </p>
                    <p>
                      {{
                        t(
                          'CONVERSATION.AI_ASSISTANT_PANEL.EDGE_CASES.WHATSAPP_EXPIRED_BODY'
                        )
                      }}
                    </p>
                  </div>
                </div>

                <div
                  v-if="showEdgeCaseLong"
                  class="rounded-lg border border-n-weak bg-n-alpha-2 p-2 text-[11px] text-n-slate-10"
                >
                  {{
                    t(
                      'CONVERSATION.AI_ASSISTANT_PANEL.EDGE_CASES.LONG_CONVERSATION_HINT'
                    )
                  }}
                </div>

                <!-- Quick prompt sections -->
                <div
                  v-for="section in sections"
                  :key="section.id"
                  class="flex flex-col gap-2"
                >
                  <h3
                    class="text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
                  >
                    {{ section.title }}
                  </h3>
                  <AIQuickPromptCard
                    v-for="item in section.items"
                    :key="item.id"
                    :icon="item.icon"
                    :label="item.label"
                    :description="item.description"
                    :disabled="isPrivateMode"
                    :disabled-reason="
                      isPrivateMode
                        ? t(
                            'CONVERSATION.AI_ASSISTANT_PANEL.EDGE_CASES.PRIVATE_MODE_BODY'
                          )
                        : ''
                    "
                    @click="runQuickPrompt(item)"
                  />
                </div>
              </section>

              <!-- Chat history -->
              <section
                v-if="history.length"
                class="flex flex-col gap-3"
                :aria-label="t('CONVERSATION.AI_ASSISTANT_PANEL.HISTORY_LABEL')"
              >
                <template v-for="msg in history" :key="msg.id">
                  <AILoadingShimmer v-if="msg.type === 'thinking'" />
                  <AIMessageBubble
                    v-else
                    :type="msg.type"
                    :text="msg.text"
                    :is-streaming="msg.isStreaming"
                    @copy="handleCopy"
                    @apply="handleApply"
                    @retry="handleRetry"
                    @feedback="handleFeedback"
                    @cancel-streaming="handleCancelStreaming"
                  />
                </template>
              </section>

              <!-- Error banner -->
              <AIErrorBanner
                v-if="errorState.errorType.value"
                :error-type="errorState.errorType.value"
                :retry-after-seconds="errorState.retryAfterSeconds.value"
                @retry="retryLastAction"
                @dismiss="errorState.clear()"
                @cancel="handleCancelStreaming"
              />
            </div>

            <!-- Footer -->
            <footer
              class="shrink-0 border-t border-n-weak bg-n-solid-1 px-3 py-3"
            >
              <form class="flex items-end gap-2" @submit.prevent="sendPrompt">
                <textarea
                  ref="textareaRef"
                  v-model="draftPrompt"
                  rows="1"
                  maxlength="4000"
                  :placeholder="placeholderText"
                  :aria-label="placeholderText"
                  class="reset-base block w-full resize-none rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:border-purple-400 focus:outline-none focus:ring-1 focus:ring-purple-400/40 max-h-[160px] overflow-y-auto"
                  @input="adjustTextareaHeight"
                  @keydown="handleKeydown"
                />
                <button
                  type="submit"
                  :disabled="!draftPrompt.trim() || isLoading"
                  :aria-label="t('CONVERSATION.AI_ASSISTANT_PANEL.SEND')"
                  class="inline-flex size-9 shrink-0 items-center justify-center rounded-full bg-purple-600 text-white transition-colors hover:bg-purple-700 focus:outline-none focus-visible:ring-2 focus-visible:ring-purple-400 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  <Icon
                    icon="i-lucide-send-horizontal"
                    class="size-4"
                    aria-hidden="true"
                  />
                </button>
              </form>
              <p class="mt-1.5 text-[11px] text-n-slate-9">
                {{ t('CONVERSATION.AI_ASSISTANT_PANEL.TEXTAREA.HINT') }}
              </p>
            </footer>
          </DialogPanel>
        </TransitionChild>
      </div>
    </Dialog>
  </TransitionRoot>
</template>
