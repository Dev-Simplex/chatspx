<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useMediaQuery } from '@vueuse/core';
import { toast } from 'vue-sonner';
import { useTrack } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import Icon from 'next/icon/Icon.vue';

import AIQuickPromptCard from './AIQuickPromptCard.vue';
import AIMessageBubble from './AIMessageBubble.vue';
import AIErrorBanner from './AIErrorBanner.vue';
import AILoadingShimmer from './AILoadingShimmer.vue';
import AISmartBanner from './AISmartBanner.vue';
import { useAIErrorState } from './composables/useAIErrorState';
import { useSmartSuggestions } from './composables/useSmartSuggestions';
import {
  useCopilotStream,
  STREAM_STATUS,
  STREAM_ERROR_CODES,
} from './composables/useCopilotStream';
import { useCopilotThread } from './composables/useCopilotThread';
import { useCopilotAssistant } from './composables/useCopilotAssistant';
import { useComposerInsert } from './composables/useComposerInsert';
import { useCopilotShortcuts } from './composables/useCopilotShortcuts';

/**
 * Copilot panel — the chat the agent talks to.
 *
 * What this component owns (worker A4): the SSE client wiring, the thread /
 * history lifecycle, the controls that make a chat usable (stop, regenerate,
 * edit the question, use as reply), the composer, and the three shortcuts
 * (Ctrl/Cmd+J invokes, Tab accepts, Esc dismisses).
 *
 * What it does NOT own: how a message looks (`AIMessageBubble`), the quick
 * prompt card, the error banner, the strings (i18n keys are listed in the
 * A4 report for the i18n owner).
 *
 * Streaming is real, not a typewriter over a finished answer: tokens arrive
 * on an SSE connection (`useCopilotStream`) and the bubble text grows as they
 * land. Stopping aborts the fetch, which closes the socket and kills the job
 * server-side.
 *
 * ── Forma (correção C1) ────────────────────────────────────────────────────
 * O painel é uma COLUNA ao lado da conversa, não um modal. O agente pergunta
 * *sobre a conversa*: cobri-la no exato momento em que ele pede ajuda é o pior
 * arranjo possível. O mecanismo é o mesmo que o produto já usa nas duas outras
 * faixas da direita (`ConversationSidebar` e o `CopilotContainer` V1): um item
 * de flex dentro do `<main>` do Dashboard, `static` no desktop e gaveta
 * sobreposta só quando não cabe (< 1100px).
 *
 * Faixa da direita é de ocupação única: abrir o copiloto recolhe o painel de
 * contato e fechá-lo devolve — regra que o produto já aplicava em uma direção
 * (`CopilotLauncher`, `ReplyBox`, `useCopilotReply` e `SidepanelSwitch` todos
 * escrevem `is_contact_sidebar_open: false` ao abrir o copiloto). Aqui ela
 * fica simétrica.
 */

const props = defineProps({
  open: { type: Boolean, default: false },
  applyToComposer: { type: Function, default: null },
});

const emit = defineEmits(['close', 'apply']);

const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();

const currentChat = useMapGetter('getSelectedChat');
const currentUser = useMapGetter('getCurrentUser');

const errorState = useAIErrorState();
const { activeSuggestion, dismiss: dismissSuggestion } =
  useSmartSuggestions(currentChat);
const stream = useCopilotStream();
const thread = useCopilotThread();
const { activeAssistant, hasAssistant, fetchAssistants } =
  useCopilotAssistant();
const { insertIntoComposer } = useComposerInsert();

const agentName = computed(() => {
  const name = currentUser.value?.name || currentUser.value?.available_name;
  if (!name) return '';
  return String(name).split(' ')[0];
});

// === Forma: coluna ao lado da conversa, gaveta só quando não cabe ===
// Acima de 1100px sobra largura para a conversa E o copiloto lado a lado —
// medido nesta base: em 1280px a conversa fica com 468px, a mesma ordem de
// grandeza que ela já tem hoje com o painel de contato aberto (508px).
// Abaixo disso não cabem duas colunas e o painel vira gaveta.
const INLINE_BREAKPOINT = 1100;
const isInline = useMediaQuery(`(min-width: ${INLINE_BREAKPOINT}px)`);

const panelRef = ref(null);

// === Conversation context ===
const conversationId = computed(() => currentChat.value?.id);

/**
 * O copiloto responde *sobre uma conversa*. Sem conversa selecionada ele não
 * tem o que fazer — e, como agora ocupa espaço de layout, renderizar fora da
 * tela de conversa espremeria telas que nada têm a ver com ele.
 */
const isRenderable = computed(
  () => props.open && Boolean(conversationId.value)
);
const replyMode = useMapGetter('draftMessages/getReplyEditorMode');
const isPrivateMode = computed(() => replyMode.value === 'NOTE');
const messagesCount = computed(() =>
  Array.isArray(currentChat.value?.messages)
    ? currentChat.value.messages.length
    : 0
);

// === Quick prompts ===
// Each card sends a real question through the same streaming path the
// composer uses — no more "typed text becomes the label of a fixed action".
const quickPrompts = computed(() => [
  {
    id: 'summarize',
    icon: 'i-lucide-file-text',
    label: t('CONVERSATION.AI_ASSISTANT_PANEL.QUICK_PROMPTS.SUMMARIZE.LABEL'),
    description: t(
      'CONVERSATION.AI_ASSISTANT_PANEL.QUICK_PROMPTS.SUMMARIZE.HINT'
    ),
    prompt: t('CONVERSATION.AI_ASSISTANT_PANEL.QUICK_PROMPTS.SUMMARIZE.PROMPT'),
  },
  {
    id: 'next_step',
    icon: 'i-lucide-compass',
    label: t('CONVERSATION.AI_ASSISTANT_PANEL.QUICK_PROMPTS.NEXT_STEP.LABEL'),
    description: t(
      'CONVERSATION.AI_ASSISTANT_PANEL.QUICK_PROMPTS.NEXT_STEP.HINT'
    ),
    prompt: t('CONVERSATION.AI_ASSISTANT_PANEL.QUICK_PROMPTS.NEXT_STEP.PROMPT'),
  },
  {
    id: 'draft_reply',
    icon: 'i-lucide-pen-line',
    label: t('CONVERSATION.AI_ASSISTANT_PANEL.QUICK_PROMPTS.DRAFT_REPLY.LABEL'),
    description: t(
      'CONVERSATION.AI_ASSISTANT_PANEL.QUICK_PROMPTS.DRAFT_REPLY.HINT'
    ),
    prompt: t(
      'CONVERSATION.AI_ASSISTANT_PANEL.QUICK_PROMPTS.DRAFT_REPLY.PROMPT'
    ),
  },
  {
    id: 'policy',
    icon: 'i-lucide-book-open',
    label: t('CONVERSATION.AI_ASSISTANT_PANEL.QUICK_PROMPTS.POLICY.LABEL'),
    description: t('CONVERSATION.AI_ASSISTANT_PANEL.QUICK_PROMPTS.POLICY.HINT'),
    prompt: t('CONVERSATION.AI_ASSISTANT_PANEL.QUICK_PROMPTS.POLICY.PROMPT'),
  },
]);

// === Local message ids for anything not yet persisted ===
let localSeq = 0;
const nextLocalId = () => {
  localSeq += 1;
  return `local-${localSeq}`;
};

const messages = thread.messages;
const isLoadingThread = thread.isLoadingThread;
const isStreaming = stream.isStreaming;

const hasHistory = computed(() => messages.value.length > 0);
const showEmptyState = computed(
  () => !isLoadingThread.value && !hasHistory.value
);

const lastUserMessage = computed(() => {
  for (let i = messages.value.length - 1; i >= 0; i -= 1) {
    if (messages.value[i].type === 'user') return messages.value[i];
  }
  return null;
});

const lastAssistantMessage = computed(() => {
  for (let i = messages.value.length - 1; i >= 0; i -= 1) {
    if (messages.value[i].type === 'assistant') return messages.value[i];
  }
  return null;
});

/** Text the Tab shortcut / "use as reply" would push into the composer. */
const acceptableAnswer = computed(() => {
  if (isStreaming.value) return '';
  const last = lastAssistantMessage.value;
  return last && !last.failed ? last.text || '' : '';
});

// === Errors ===
// AIErrorBanner only knows these five. Anything else (notably `unauthorized`,
// the state an expired OpenAI key produces) gets the panel's own block so the
// agent is never left staring at nothing.
const BANNER_ERROR_TYPES = [
  'rate_limit',
  'captain_unstable',
  'timeout',
  'empty_response',
  'network',
];

const activeErrorCode = ref(null);
const bannerErrorType = computed(() =>
  BANNER_ERROR_TYPES.includes(activeErrorCode.value)
    ? activeErrorCode.value
    : null
);
const showFallbackError = computed(
  () => Boolean(activeErrorCode.value) && !bannerErrorType.value
);
/** No Captain assistant in the account — the copilot cannot open a thread. */
const NO_ASSISTANT = 'no_assistant';
const isUnauthorized = computed(
  () => activeErrorCode.value === STREAM_ERROR_CODES.UNAUTHORIZED
);
const isMissingAssistant = computed(
  () => activeErrorCode.value === NO_ASSISTANT
);
const fallbackErrorTitle = computed(() => {
  if (isUnauthorized.value) {
    return t('CONVERSATION.AI_ASSISTANT_PANEL.ERRORS.UNAUTHORIZED.TITLE');
  }
  if (isMissingAssistant.value) {
    return t('CONVERSATION.AI_ASSISTANT_PANEL.ERRORS.NO_ASSISTANT.TITLE');
  }
  return t('CONVERSATION.AI_ASSISTANT_PANEL.ERRORS.GENERIC.TITLE');
});
const fallbackErrorBody = computed(() => {
  if (isUnauthorized.value) {
    return t('CONVERSATION.AI_ASSISTANT_PANEL.ERRORS.UNAUTHORIZED.BODY');
  }
  if (isMissingAssistant.value) {
    return t('CONVERSATION.AI_ASSISTANT_PANEL.ERRORS.NO_ASSISTANT.BODY');
  }
  return t('CONVERSATION.AI_ASSISTANT_PANEL.ERRORS.GENERIC.BODY');
});
/** Retrying makes no sense when there is no assistant configured. */
const canRetryFallback = computed(() => !isMissingAssistant.value);

function clearError() {
  activeErrorCode.value = null;
  errorState.clear();
}

function setError(code) {
  activeErrorCode.value = code || STREAM_ERROR_CODES.UNKNOWN;
  errorState.errorType.value = BANNER_ERROR_TYPES.includes(
    activeErrorCode.value
  )
    ? activeErrorCode.value
    : null;
}

// === Scroll ===
const scrollRef = ref(null);
function scrollToBottom() {
  nextTick(() => {
    const el = scrollRef.value;
    if (el) el.scrollTop = el.scrollHeight;
  });
}

// === Sending ===
const draftPrompt = ref('');
const textareaRef = ref(null);
const editingMessageId = ref(null);
const isEditing = computed(() => Boolean(editingMessageId.value));

/** Teto do composer — o mesmo do mockup (`max-height:110px`). */
const COMPOSER_MAX_HEIGHT = 110;

function adjustTextareaHeight() {
  const el = textareaRef.value;
  if (!el) return;
  el.style.height = 'auto';
  el.style.height = `${Math.min(el.scrollHeight, COMPOSER_MAX_HEIGHT)}px`;
}

const canSend = computed(
  () => Boolean(draftPrompt.value.trim()) && !isStreaming.value
);

/**
 * Sends a question and streams the answer into a fresh assistant bubble.
 * @param {string} rawText
 */
async function sendMessage(rawText) {
  const text = (rawText || '').trim();
  if (!text || isStreaming.value) return;

  if (!hasAssistant.value) {
    setError(NO_ASSISTANT);
    return;
  }

  clearError();
  const convId = conversationId.value;

  thread.appendMessage(convId, {
    id: nextLocalId(),
    type: 'user',
    text,
  });
  const assistantId = nextLocalId();
  thread.appendMessage(convId, {
    id: assistantId,
    type: 'assistant',
    text: '',
    isStreaming: true,
  });
  scrollToBottom();

  useTrack('ai.stream.started', {
    conversation_id: convId,
    surface: 'panel',
  });

  let threadId = thread.threadId.value;
  try {
    if (!threadId) {
      threadId = await thread.ensureThread({
        conversationId: convId,
        assistantId: activeAssistant.value?.id,
        message: text,
      });
    }
  } catch (error) {
    thread.removeMessage(convId, assistantId);
    setError(
      error?.response?.status === 401 || error?.response?.status === 403
        ? STREAM_ERROR_CODES.UNAUTHORIZED
        : STREAM_ERROR_CODES.CAPTAIN_UNSTABLE
    );
    return;
  }

  if (!threadId) {
    thread.removeMessage(convId, assistantId);
    setError(STREAM_ERROR_CODES.CAPTAIN_UNSTABLE);
    return;
  }

  const result = await stream.start({
    threadId,
    message: text,
    conversationId: convId,
    onToken: () => {
      thread.updateMessage(convId, assistantId, {
        text: stream.streamedText.value,
      });
      scrollToBottom();
    },
  });

  if (result.status === STREAM_STATUS.DONE) {
    thread.updateMessage(convId, assistantId, {
      text: result.text,
      isStreaming: false,
      id: result.messageId || assistantId,
    });
    if (!result.text) setError(STREAM_ERROR_CODES.EMPTY_RESPONSE);
    useTrack('ai.stream.completed', {
      conversation_id: convId,
      chars: result.text.length,
    });
  } else if (result.status === STREAM_STATUS.CANCELLED) {
    if (result.text) {
      thread.updateMessage(convId, assistantId, {
        text: result.text,
        isStreaming: false,
        cancelled: true,
      });
    } else {
      thread.removeMessage(convId, assistantId);
    }
    useTrack('ai.stream.cancelled', {
      conversation_id: convId,
      reason: 'user',
    });
  } else {
    // Error: drop an empty bubble, keep a partial one flagged as failed.
    if (result.text) {
      thread.updateMessage(convId, assistantId, {
        text: result.text,
        isStreaming: false,
        failed: true,
      });
    } else {
      thread.removeMessage(convId, assistantId);
    }
    setError(result.error?.code);
    useTrack('ai.stream.error', {
      conversation_id: convId,
      code: result.error?.code,
    });
  }
  scrollToBottom();
}

async function handleSubmit() {
  const text = draftPrompt.value.trim();
  if (!text || isStreaming.value) return;

  if (isEditing.value) {
    // Editing a past question replaces it: everything from it onwards goes.
    thread.truncateFrom(conversationId.value, editingMessageId.value);
    editingMessageId.value = null;
  }

  draftPrompt.value = '';
  await nextTick();
  adjustTextareaHeight();
  await sendMessage(text);
}

function handleQuickPrompt(item) {
  sendMessage(item.prompt);
}

/** Stop generating — aborts the connection, which aborts the job. */
function stopGeneration() {
  if (!isStreaming.value) return;
  stream.stop('user');
}

/** Regenerate the answer to the last question. */
async function regenerate() {
  const question = lastUserMessage.value;
  if (!question || isStreaming.value) return;
  clearError();
  useTrack('ai.stream.regenerated', { conversation_id: conversationId.value });
  thread.truncateFrom(conversationId.value, question.id);
  await sendMessage(question.text);
}

/** Puts a previous question back in the composer for editing. */
function startEdit(message) {
  if (!message || message.type !== 'user' || isStreaming.value) return;
  editingMessageId.value = message.id;
  draftPrompt.value = message.text;
  nextTick(() => {
    adjustTextareaHeight();
    textareaRef.value?.focus();
  });
}

function cancelEdit() {
  editingMessageId.value = null;
  draftPrompt.value = '';
  nextTick(adjustTextareaHeight);
}

function editLastQuestion() {
  startEdit(lastUserMessage.value);
}

// === Open / close lifecycle ===
/**
 * Elemento que abriu o painel. O foco volta para ele ao fechar — sem isso o
 * usuário de teclado é despejado no `body` e perde o lugar.
 */
let triggerElement = null;
/** Estado do painel de contato antes de o copiloto tomar a faixa da direita. */
let contactSidebarWasOpen = false;

// Todos os outros gatilhos do copiloto (✨ do composer, ReplyBox, launcher)
// escrevem `is_contact_sidebar_open: false` junto com a abertura. Ler o valor
// depois que o painel abriu daria sempre "estava fechado" e a faixa nunca
// voltaria. Por isso acompanhamos a posição do painel de contato ENQUANTO o
// copiloto está fechado. Este watcher precisa ser criado antes do watcher de
// `props.open` para ver o estado anterior à mudança.
watch(
  () => Boolean(uiSettings.value?.is_contact_sidebar_open),
  isContactOpen => {
    if (!props.open) contactSidebarWasOpen = isContactOpen;
  },
  { immediate: true }
);

const FOCUSABLE_SELECTOR = [
  'a[href]',
  'button:not([disabled])',
  'textarea:not([disabled])',
  'input:not([disabled])',
  'select:not([disabled])',
  '[tabindex]:not([tabindex="-1"])',
].join(',');

function rememberTrigger() {
  const active =
    typeof document !== 'undefined' ? document.activeElement : null;
  triggerElement =
    active && active !== document.body && typeof active.focus === 'function'
      ? active
      : null;
}

function restoreFocusToTrigger() {
  const target = triggerElement;
  triggerElement = null;
  nextTick(() => {
    if (typeof document === 'undefined') return;
    if (target && document.contains(target)) {
      target.focus();
      return;
    }
    // O gatilho pode ter saído do DOM (troca de conversa, dropdown fechado).
    // Cai para o botão que abre o copiloto em vez de largar o foco no body.
    const fallback =
      document.querySelector('[data-ai-tour="sparkles-button"]') ||
      document.querySelector('[data-testid="copilot-launcher"]');
    fallback?.focus();
  });
}

/**
 * Garante que a faixa da direita fique só com o copiloto.
 *
 * Escreve as DUAS chaves de uma vez: `updateUISettings` faz spread do estado
 * atual e despacha, então duas chamadas em sequência competem — a resposta da
 * primeira chega depois da segunda e ressuscita o painel de contato (visto em
 * 1920 na validação). Uma escrita só, sem corrida.
 */
function claimRightRail() {
  if (!uiSettings.value?.is_contact_sidebar_open) return;
  updateUISettings({
    is_copilot_panel_open: true,
    is_contact_sidebar_open: false,
  });
}

function releaseRightRail() {
  if (!contactSidebarWasOpen) return;
  updateUISettings({ is_contact_sidebar_open: true });
}

function close(reason = 'user') {
  stream.stop('close');
  emit('close', reason);
  useTrack('ai.panel.closed', { reason });
}

function closeFromUISettings(reason = 'user') {
  updateUISettings({ is_copilot_panel_open: false });
  close(reason);
}

// === Use as reply ===
/**
 * The highest-value action: drops the answer into the conversation composer
 * so the agent reads, approves and sends. Reuses the legacy bus events, so
 * both the plain textarea and the rich editor keep working.
 * @param {string} text
 * @returns {boolean}
 */
function applyAnswer(text) {
  const content = (text || '').trim();
  if (!content) return false;

  let inserted;
  if (typeof props.applyToComposer === 'function') {
    props.applyToComposer(content);
    inserted = true;
  } else {
    inserted = insertIntoComposer(content);
  }

  if (!inserted) return false;

  emit('apply', content);
  useTrack('ai.response.applied', { conversation_id: conversationId.value });
  toast(t('CONVERSATION.AI_ASSISTANT_PANEL.APPLIED_TOAST'));

  // Fecha para o agente cair no composer com o texto já lá — e a conversa
  // recupera a largura da faixa para ele reler antes de enviar.
  closeFromUISettings('apply');

  // Aqui NÃO se dispara tour nenhum. Aceitar a resposta é o instante em que o
  // agente vai falar com o cliente; sequestrar a tela com onboarding nesse
  // momento é o oposto do que o produto promete (princípio 1: o agente está
  // com um cliente esperando). O `useAITour` continua existindo para um
  // momento ocioso — só não é este.
  return true;
}

function handleApply(text) {
  applyAnswer(text || lastAssistantMessage.value?.text || '');
}

function handleCopy() {
  useTrack('ai.response.copied', { conversation_id: conversationId.value });
}

function handleFeedback(kind) {
  useTrack('ai.response.feedback', {
    kind,
    conversation_id: conversationId.value,
  });
}

function retryAfterError() {
  clearError();
  if (lastUserMessage.value) {
    regenerate();
  }
}

// === Smart banner (kept from phase 5) ===
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
    conversation_id: conversationId.value,
  });
  sendMessage(suggestionToLabel(suggestion));
}

function handleSuggestionDismiss(suggestion) {
  if (!suggestion) return;
  dismissSuggestion(suggestion.id);
  useTrack('ai.banner.dismissed', {
    banner_type: suggestion.id,
    conversation_id: conversationId.value,
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
        conversation_id: conversationId.value,
        msg_count: messagesCount.value,
      });
    } else if (!next) {
      bannerShownAt.value = null;
    }
  },
  { immediate: true }
);

function startNewThread() {
  stream.stop('new_thread');
  clearError();
  editingMessageId.value = null;
  draftPrompt.value = '';
  thread.reset(conversationId.value);
  useTrack('ai.thread.new', { conversation_id: conversationId.value });
  nextTick(() => textareaRef.value?.focus());
}

watch(
  conversationId,
  (newId, oldId) => {
    if (newId === oldId) return;
    // An answer must never land in the wrong conversation.
    stream.stop('context_switch');
    editingMessageId.value = null;
    draftPrompt.value = '';
    clearError();
    if (newId) thread.loadForConversation(newId);
  },
  { immediate: true }
);

watch(
  () => props.open,
  (isOpen, wasOpen) => {
    if (isOpen) {
      rememberTrigger();
      claimRightRail();
      useTrack('ai.panel.opened', { conversation_id: conversationId.value });
      fetchAssistants();
      if (conversationId.value && !thread.messages.value.length) {
        thread.loadForConversation(conversationId.value);
      }
      nextTick(() => {
        textareaRef.value?.focus();
        scrollToBottom();
      });
      return;
    }
    if (!wasOpen) return;
    // Fechar por qualquer caminho (Esc, X, Ctrl+J, aplicar, outra tela que
    // zerou a flag) precisa parar o stream, devolver a faixa e devolver o foco.
    stream.stop('close');
    releaseRightRail();
    restoreFocusToTrigger();
  }
);

// === Shortcuts: Ctrl/Cmd+J invokes, Tab accepts, Esc dismisses ===
useCopilotShortcuts({
  isOpen: () => props.open,
  onToggle: () => {
    const willOpen = !uiSettings.value?.is_copilot_panel_open;
    // Abrir toma a faixa da direita na MESMA escrita — igual ao que o
    // CopilotLauncher e o ReplyBox já fazem. Duas escritas seguidas competem.
    updateUISettings(
      willOpen
        ? { is_copilot_panel_open: true, is_contact_sidebar_open: false }
        : { is_copilot_panel_open: false }
    );
  },
  onAccept: () => {
    if (!acceptableAnswer.value) return false;
    useTrack('ai.shortcut.accept', { conversation_id: conversationId.value });
    return applyAnswer(acceptableAnswer.value);
  },
  onDismiss: () => {
    // Escalating dismiss — the panel only closes when there is nothing left.
    if (isStreaming.value) {
      stopGeneration();
      return true;
    }
    if (activeErrorCode.value) {
      clearError();
      return true;
    }
    if (isEditing.value) {
      cancelEdit();
      return true;
    }
    if (draftPrompt.value) {
      draftPrompt.value = '';
      nextTick(adjustTextareaHeight);
      return true;
    }
    // Nada mais para descartar: o rodapé promete "Esc fecha" e agora fecha.
    // Antes isto devolvia `false` contando com o Dialog do Headless UI, que
    // saiu junto com o modal — a promessa ficava na tela sem cumprir-se.
    closeFromUISettings('escape');
    return true;
  },
});

function handleComposerKeydown(event) {
  if (event.isComposing) return;
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault();
    handleSubmit();
  }
}

/**
 * O painel não é modal, mas o Tab não pode vazar para a conversa: dentro dele
 * Tab tem significado próprio ("aceita a resposta") e, sem contenção, o agente
 * de teclado sai do painel sem saber. Cicla entre o primeiro e o último foco
 * do painel; a saída é o Esc, que fecha e devolve o foco ao gatilho.
 */
function handlePanelKeydown(event) {
  if (event.key !== 'Tab' || event.defaultPrevented) return;
  const root = panelRef.value;
  if (!root) return;

  const focusables = Array.from(
    root.querySelectorAll(FOCUSABLE_SELECTOR)
  ).filter(el => el.offsetParent !== null || el === document.activeElement);
  if (!focusables.length) return;

  const first = focusables[0];
  const last = focusables[focusables.length - 1];
  const active = document.activeElement;

  if (event.shiftKey && (active === first || !root.contains(active))) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && active === last) {
    event.preventDefault();
    first.focus();
  }
}

onMounted(() => {
  if (!props.open) return;
  // Recarregar a página com a flag já ligada não passa pelo watcher: a faixa
  // da direita precisa ser reivindicada aqui também, senão o painel de contato
  // e o copiloto aparecem juntos e espremem a conversa.
  claimRightRail();
  fetchAssistants();
  nextTick(() => textareaRef.value?.focus());
});

onBeforeUnmount(() => {
  stream.stop('unmount');
});

const placeholderText = computed(() =>
  t('CONVERSATION.AI_ASSISTANT_PANEL.TEXTAREA.PLACEHOLDER')
);

// === Edge cases (kept) ===
const showEdgeCaseEmpty = computed(() => messagesCount.value === 0);
const showEdgeCasePrivate = computed(() => isPrivateMode.value);
const showEdgeCaseLong = computed(() => messagesCount.value >= 1000);
const showEdgeCaseWhatsappExpired = computed(() => {
  const channelType =
    currentChat.value?.meta?.channel ||
    currentChat.value?.inbox?.channel_type ||
    '';
  if (channelType !== INBOX_TYPES.WHATSAPP) return false;
  return currentChat.value?.can_reply === false;
});

defineExpose({ sendMessage, applyAnswer, stopGeneration, regenerate });
</script>

<template>
  <!-- Coluna ao lado da conversa (>= 1100px) · gaveta sobreposta abaixo disso.
       Mesmo mecanismo do ConversationSidebar e do CopilotContainer V1: item de
       flex dentro do <main> do Dashboard. -->
  <aside
    v-if="isRenderable"
    ref="panelRef"
    data-ai-panel
    aria-labelledby="ai-panel-title"
    class="flex h-full min-h-0 flex-col bg-[var(--oa-bg)] ltr:border-l rtl:border-r border-[var(--oa-line)]"
    :class="
      isInline
        ? 'static w-[360px] min-w-[360px] shrink-0 2xl:w-[400px] 2xl:min-w-[400px]'
        : 'fixed top-0 z-40 w-full max-w-sm shadow-2xl ltr:right-0 rtl:left-0'
    "
    @keydown="handlePanelKeydown"
  >
    <!-- Header -->
    <header
      class="flex h-14 shrink-0 items-center justify-between gap-3 border-b border-[var(--oa-line)] bg-[var(--oa-bg)] px-4"
    >
      <h2
        id="ai-panel-title"
        class="truncate text-sm font-semibold text-[var(--oa-ink)]"
      >
        {{ t('CONVERSATION.AI_ASSISTANT_PANEL.TITLE') }}
      </h2>
      <div class="flex items-center gap-1">
        <button
          type="button"
          :aria-label="t('CONVERSATION.AI_ASSISTANT_PANEL.NEW_THREAD')"
          :title="t('CONVERSATION.AI_ASSISTANT_PANEL.NEW_THREAD')"
          class="inline-flex size-8 items-center justify-center rounded-md text-[var(--oa-ink-2)] transition-colors hover:bg-[var(--oa-hover)] focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--oa-focus)]"
          @click="startNewThread"
        >
          <Icon icon="i-lucide-square-pen" class="size-4" aria-hidden="true" />
        </button>
        <button
          type="button"
          data-testid="ai-panel-close"
          :aria-label="t('CONVERSATION.AI_ASSISTANT_PANEL.CLOSE')"
          class="inline-flex size-8 items-center justify-center rounded-md text-[var(--oa-ink-2)] transition-colors hover:bg-[var(--oa-hover)] focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--oa-focus)]"
          @click="closeFromUISettings('user')"
        >
          <Icon icon="i-lucide-x" class="size-4" aria-hidden="true" />
        </button>
      </div>
    </header>

    <!-- Body (scrollable) -->
    <div
      ref="scrollRef"
      data-ai-panel-scroll
      class="flex flex-1 flex-col gap-4 overflow-y-auto bg-[var(--oa-bg)] px-4 py-4"
    >
      <!-- Loading the thread — a different screen from "empty" -->
      <section
        v-if="isLoadingThread"
        class="flex flex-col gap-3"
        :aria-label="t('CONVERSATION.AI_ASSISTANT_PANEL.LOADING_THREAD')"
        aria-busy="true"
      >
        <AILoadingShimmer />
        <p class="text-xs text-[var(--oa-ink-2)]">
          {{ t('CONVERSATION.AI_ASSISTANT_PANEL.LOADING_THREAD') }}
        </p>
      </section>

      <!-- Empty / first-time state.
           `mt-auto` encosta a saudação e os atalhos no composer: o vazio sobra
           em cima, onde o fio de conversa vai crescer, e não como um buraco
           entre o último atalho e a caixa de texto. -->
      <section
        v-else-if="showEmptyState"
        class="mt-auto flex flex-col gap-4"
        aria-labelledby="ai-panel-empty-title"
      >
        <div class="flex flex-col items-start gap-1">
          <h2
            id="ai-panel-empty-title"
            class="text-base font-semibold text-[var(--oa-ink)]"
          >
            {{
              agentName
                ? t('CONVERSATION.AI_ASSISTANT_PANEL.EMPTY.GREETING_NAMED', {
                    name: agentName,
                  })
                : t('CONVERSATION.AI_ASSISTANT_PANEL.EMPTY.GREETING_GENERIC')
            }}
          </h2>
          <p class="text-xs text-[var(--oa-ink-2)]">
            {{ t('CONVERSATION.AI_ASSISTANT_PANEL.EMPTY.SUBTITLE') }}
          </p>
        </div>

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
          class="rounded-lg border border-[var(--oa-line)] bg-[var(--oa-side)] p-3 text-xs text-[var(--oa-ink-2)]"
        >
          <p class="font-semibold text-[var(--oa-ink)]">
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
          class="rounded-lg border border-[var(--oa-line)] bg-[var(--oa-side)] p-3 text-xs text-[var(--oa-ink-2)]"
        >
          <p class="font-semibold text-[var(--oa-ink)]">
            {{
              t('CONVERSATION.AI_ASSISTANT_PANEL.EDGE_CASES.PRIVATE_MODE_TITLE')
            }}
          </p>
          <p class="mt-0.5">
            {{
              t('CONVERSATION.AI_ASSISTANT_PANEL.EDGE_CASES.PRIVATE_MODE_BODY')
            }}
          </p>
        </div>

        <div
          v-if="showEdgeCaseWhatsappExpired"
          class="rounded-lg border border-[var(--oa-line)] bg-[var(--oa-side)] p-3 text-xs text-[var(--oa-ink-2)]"
        >
          <p class="font-semibold text-[var(--oa-ink)]">
            {{
              t(
                'CONVERSATION.AI_ASSISTANT_PANEL.EDGE_CASES.WHATSAPP_EXPIRED_TITLE'
              )
            }}
          </p>
          <p class="mt-0.5">
            {{
              t(
                'CONVERSATION.AI_ASSISTANT_PANEL.EDGE_CASES.WHATSAPP_EXPIRED_BODY'
              )
            }}
          </p>
        </div>

        <div
          v-if="showEdgeCaseLong"
          class="rounded-lg border border-[var(--oa-line)] bg-[var(--oa-side)] p-2 text-[11px] text-[var(--oa-ink-2)]"
        >
          {{
            t(
              'CONVERSATION.AI_ASSISTANT_PANEL.EDGE_CASES.LONG_CONVERSATION_HINT'
            )
          }}
        </div>

        <!-- Quick prompts -->
        <div class="flex flex-col gap-2">
          <AIQuickPromptCard
            v-for="item in quickPrompts"
            :key="item.id"
            :icon="item.icon"
            :label="item.label"
            :description="item.description"
            @click="handleQuickPrompt(item)"
          />
        </div>
      </section>

      <!-- Chat history -->
      <section
        v-else
        class="flex flex-col gap-4"
        :aria-label="t('CONVERSATION.AI_ASSISTANT_PANEL.HISTORY_LABEL')"
      >
        <template v-for="msg in messages" :key="msg.id">
          <AIMessageBubble
            :type="msg.type"
            :text="msg.text"
            :is-streaming="Boolean(msg.isStreaming)"
            @copy="handleCopy"
            @apply="handleApply"
            @retry="regenerate"
            @feedback="handleFeedback"
            @cancel-streaming="stopGeneration"
          />
          <p
            v-if="msg.cancelled"
            class="-mt-2 text-[11px] text-[var(--oa-ink-2)]"
          >
            {{ t('CONVERSATION.AI_ASSISTANT_PANEL.CANCELLED_NOTICE') }}
          </p>
        </template>

        <!-- Ação de nível de painel. "Usar como resposta", copiar, refazer,
             feedback e PARAR pertencem à MENSAGEM e são desenhados pela bolha
             (AIMessageBubble) junto do texto — repeti-los aqui punha dois
             botões idênticos na tela (o "Parar" saiu daqui por isso: eram dois,
             74x30 na bolha e 368x32 no painel). Editar a pergunta é a única
             ação que age sobre a conversa, não sobre uma resposta. -->
        <div
          v-if="!isStreaming && lastUserMessage"
          class="flex flex-wrap items-center gap-2"
        >
          <button
            type="button"
            class="inline-flex h-7 items-center gap-1.5 rounded-full border border-[var(--oa-line)] px-3 text-xs text-[var(--oa-ink-2)] transition-colors hover:bg-[var(--oa-hover)] focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--oa-focus)]"
            @click="editLastQuestion"
          >
            <Icon icon="i-lucide-pencil" class="size-3.5" aria-hidden="true" />
            {{ t('CONVERSATION.AI_ASSISTANT_PANEL.EDIT_QUESTION') }}
          </button>
        </div>
      </section>

      <!-- Errors the banner knows how to draw -->
      <AIErrorBanner
        v-if="bannerErrorType"
        :error-type="bannerErrorType"
        :retry-after-seconds="errorState.retryAfterSeconds.value"
        @retry="retryAfterError"
        @dismiss="clearError"
        @cancel="stopGeneration"
      />

      <!-- Errors it does not (401 above all) — never a silent panel -->
      <div
        v-if="showFallbackError"
        data-testid="ai-fallback-error"
        role="alert"
        class="flex items-start gap-2 rounded-lg border border-[var(--oa-line)] bg-[var(--oa-side)] p-3 text-xs text-[var(--oa-ink-2)]"
      >
        <Icon
          icon="i-lucide-triangle-alert"
          class="mt-0.5 size-4 shrink-0 text-[var(--oa-ink-2)]"
          aria-hidden="true"
        />
        <div class="flex min-w-0 flex-1 flex-col gap-1">
          <p class="font-semibold text-[var(--oa-ink)]">
            {{ fallbackErrorTitle }}
          </p>
          <p>{{ fallbackErrorBody }}</p>
          <div class="mt-1 flex items-center gap-2">
            <button
              v-if="canRetryFallback"
              type="button"
              data-testid="ai-error-retry"
              class="inline-flex h-7 items-center rounded-full bg-[var(--oa-send)] px-3 text-[11px] font-medium text-[var(--oa-send-ink)] transition-opacity hover:opacity-90"
              @click="retryAfterError"
            >
              {{ t('CONVERSATION.AI_ASSISTANT_PANEL.ERRORS.RETRY') }}
            </button>
            <button
              type="button"
              class="inline-flex h-7 items-center rounded-full border border-[var(--oa-line)] px-3 text-[11px] text-[var(--oa-ink-2)] transition-colors hover:bg-[var(--oa-hover)]"
              @click="clearError"
            >
              {{ t('CONVERSATION.AI_ASSISTANT_PANEL.ERRORS.DISMISS') }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Footer: composer em pill, na medida do mockup (52px em repouso,
         crescendo até 110px conforme o texto). -->
    <footer
      class="shrink-0 border-t border-[var(--oa-line)] bg-[var(--oa-bg)] px-4 pb-4 pt-3"
    >
      <div
        v-if="isEditing"
        class="mb-2 flex items-center justify-between gap-2 text-[11px] text-[var(--oa-ink-2)]"
      >
        <span>{{ t('CONVERSATION.AI_ASSISTANT_PANEL.EDITING_NOTICE') }}</span>
        <button
          type="button"
          class="underline underline-offset-2 hover:text-[var(--oa-ink)]"
          @click="cancelEdit"
        >
          {{ t('CONVERSATION.AI_ASSISTANT_PANEL.EDIT_CANCEL') }}
        </button>
      </div>

      <form
        class="flex items-end gap-2 rounded-[26px] border border-[var(--oa-line)] bg-[var(--oa-bg)] py-[9px] focus-within:border-[var(--oa-ink-3)] ltr:pl-4 ltr:pr-[9px] rtl:pr-4 rtl:pl-[9px]"
        @submit.prevent="handleSubmit"
      >
        <textarea
          ref="textareaRef"
          v-model="draftPrompt"
          rows="1"
          maxlength="4000"
          :placeholder="placeholderText"
          :aria-label="placeholderText"
          class="reset-base m-0 block h-auto max-h-[110px] w-full resize-none overflow-y-auto border-0 bg-transparent px-0 py-[3px] text-[14.5px] leading-[1.5] text-[var(--oa-ink)] outline-none placeholder:text-[var(--oa-ink-3)] focus:outline-none focus:ring-0"
          @input="adjustTextareaHeight"
          @keydown="handleComposerKeydown"
        />
        <button
          type="submit"
          :disabled="!canSend"
          :aria-label="t('CONVERSATION.AI_ASSISTANT_PANEL.SEND')"
          class="inline-flex size-8 shrink-0 items-center justify-center rounded-full bg-[var(--oa-send)] text-[var(--oa-send-ink)] transition-opacity hover:opacity-90 focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--oa-focus)] disabled:cursor-not-allowed disabled:opacity-30"
        >
          <Icon icon="i-lucide-arrow-up" class="size-4" aria-hidden="true" />
        </button>
      </form>
      <p class="mt-[9px] text-center text-[11.5px] text-[var(--oa-ink-2)]">
        {{ t('CONVERSATION.AI_ASSISTANT_PANEL.SHORTCUTS_HINT') }}
      </p>
    </footer>
  </aside>
  <template v-else />
</template>
