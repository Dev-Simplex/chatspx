<script setup>
import { computed, nextTick, onMounted, ref, toRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { toast } from 'vue-sonner';
import Icon from 'next/icon/Icon.vue';
import { useMarkdown } from './composables/useMarkdown';
import { useTypewriter } from './composables/useTypewriter';

/**
 * Uma mensagem do fio do copiloto, na linguagem visual da OpenAI
 * (public/mockups/copiloto-v2.html — tokens `--oa-*`).
 *
 * ⚠️ DECISÃO ESTRUTURAL: **a resposta da IA não tem bolha.** É texto solto na
 * coluna, largura total, sem avatar e sem etiqueta "Copiloto". Só a fala do
 * usuário tem bolha — cinza neutra, à direita, `border-radius:18px`, ~75% de
 * largura. Nenhuma cor de destaque: preto, branco e cinza.
 *
 * Três papéis:
 *   - `user`       — a pergunta do agente; a única bolha da tela.
 *   - `assistant`  — resposta em markdown rico (parágrafos, listas, negrito,
 *                    bloco de código e tabela, cada um com rolagem própria e
 *                    o código com botão de copiar), chip de fonte citada e a
 *                    régua de ações abaixo.
 *   - `thinking`   — três pontinhos monocromáticos (nunca um spinner).
 *
 * O nome do arquivo é herança da versão anterior (quando a IA tinha bolha) e
 * ficou incorreto para este desenho. Mantido de propósito: `AIAssistantPanel`
 * (worker A4) e a suíte E2E importam por este caminho, e renomear durante a
 * execução paralela quebraria o painel. Renomear depois que as duas frentes
 * pousarem.
 *
 * a11y: durante o streaming a saída fica `aria-live="off"` para não inundar o
 * leitor de tela token a token; ao terminar, uma região `role="status"`
 * anuncia só "Resposta gerada".
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
  /**
   * Fontes citadas. Aceita string ("Política Comercial · seção 4.2") ou
   * objeto `{ id?, label, url? }`. É o elemento que gera confiança — a
   * pesquisa (NN/g) mostra que citar a fonte funciona e "mostrar raciocínio"
   * não.
   */
  sources: { type: Array, default: () => [] },
});

const emit = defineEmits([
  'copy',
  'apply',
  'retry',
  'feedback',
  'cancel-streaming',
  'source-click',
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

// === Fonte citada ===
const normalizedSources = computed(() =>
  (props.sources || [])
    .map((source, index) => {
      if (!source) return null;
      if (typeof source === 'string') {
        return { key: `src-${index}`, label: source, url: '', raw: source };
      }
      const label = source.label || source.title || source.name || '';
      if (!label) return null;
      return {
        key: String(source.id ?? `src-${index}`),
        label,
        url: source.url || '',
        raw: source,
      };
    })
    .filter(Boolean)
);

function handleSourceClick(source) {
  // eslint-disable-next-line vue/custom-event-name-casing -- alinhado ao kebab-case já usado por cancel-streaming
  emit('source-click', source.raw);
}

// === Blocos largos: botão de copiar no código, rolagem própria na tabela ===
// O markdown vem do `useMarkdown` (composable do worker A4) já sanitizado e
// sem os nossos ganchos, então a decoração é injetada no DOM depois da render.
// Em ambos os casos o wrapper fica FORA do elemento que rola — assim o botão
// não desliza junto quando o agente arrasta um trecho largo para o lado.
const bodyRef = ref(null);
const copyCodeLabel = computed(() =>
  t('CONVERSATION.AI_ASSISTANT_PANEL.CODE.COPY')
);

function wrap(element, className) {
  const wrapper = document.createElement('div');
  wrapper.className = className;
  element.parentNode.insertBefore(wrapper, element);
  wrapper.appendChild(element);
  return wrapper;
}

function decorateRichBlocks() {
  const root = bodyRef.value;
  if (!root || typeof root.querySelectorAll !== 'function') return;

  root.querySelectorAll('pre').forEach(pre => {
    if (pre.parentElement?.classList?.contains('oa-codeblock')) return;
    const wrapper = wrap(pre, 'oa-codeblock');

    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'oa-codeblock__copy';
    button.setAttribute('data-oa-copy', 'true');
    button.setAttribute('data-testid', 'ai-code-copy');
    button.textContent = copyCodeLabel.value;
    wrapper.appendChild(button);
  });

  // Comparativo em tabela é o que os modelos mais produzem depois de lista.
  // O painel tem ~400px: sem esta caixa, três colunas empurram a conversa.
  root.querySelectorAll('table').forEach(table => {
    if (table.parentElement?.classList?.contains('oa-tablewrap')) return;
    wrap(table, 'oa-tablewrap');
  });
}

async function handleBodyClick(event) {
  const button = event.target?.closest?.('[data-oa-copy]');
  if (!button) return;
  const code = button.parentElement?.querySelector('pre')?.textContent ?? '';
  try {
    if (navigator?.clipboard?.writeText) {
      await navigator.clipboard.writeText(code);
    }
    button.textContent = t('CONVERSATION.AI_ASSISTANT_PANEL.CODE.COPIED');
    setTimeout(() => {
      button.textContent = copyCodeLabel.value;
    }, 1600);
  } catch {
    toast.error(t('CONVERSATION.AI_ASSISTANT_PANEL.TOAST.COPY_FAILED'), {
      important: true,
    });
  }
}

// Redecorar a cada render do markdown. Enquanto o streaming corre o `v-html`
// é reescrito a cada token — decorar aí seria caro e o bloco ainda está
// incompleto; o botão aparece quando a resposta fecha.
watch(
  [html, () => props.isStreaming],
  () => {
    if (props.isStreaming) return;
    nextTick(decorateRichBlocks);
  },
  { immediate: true }
);

onMounted(() => {
  if (!props.isStreaming) nextTick(decorateRichBlocks);
});

// === Action handlers (assistant only) ===
const lastFeedbackAt = ref(0);

async function handleCopy() {
  try {
    if (navigator?.clipboard?.writeText) {
      await navigator.clipboard.writeText(props.text || '');
    }
    toast.success(t('CONVERSATION.AI_ASSISTANT_PANEL.TOAST.COPIED'));
    emit('copy');
  } catch {
    toast.error(t('CONVERSATION.AI_ASSISTANT_PANEL.TOAST.COPY_FAILED'), {
      important: true,
    });
  }
}

function handleApply() {
  emit('apply', props.text);
  toast.success(t('CONVERSATION.AI_ASSISTANT_PANEL.TOAST.APPLIED'));
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
  toast.success(t('CONVERSATION.AI_ASSISTANT_PANEL.TOAST.FEEDBACK_SAVED'));
}

function handleCancelStreaming() {
  cancel();
  // eslint-disable-next-line vue/custom-event-name-casing -- kebab-case preservado: o AIAssistantPanel (A4) escuta @cancel-streaming
  emit('cancel-streaming');
}

const showActions = computed(
  () => props.type === 'assistant' && !props.isStreaming && !!props.text
);
const showCancel = computed(
  () => props.type === 'assistant' && props.isStreaming
);
const showCursor = computed(
  () => props.type === 'assistant' && props.isStreaming && !isDone.value
);

// Ícone discreto e monocromático — o vocabulário do ChatGPT. O mockup desenha
// 30×30 com 2px de respiro; aqui são 36×36 com `gap-2` (8px) porque 36+8 = 44,
// o passo exato para as áreas de toque de `oa-hit-44` encostarem sem se
// sobrepor. Menos que isso e o dedo aciona o polegar-para-baixo achando que
// clicou em copiar.
const ICON_BUTTON_CLASS =
  'oa-hit-44 inline-grid size-9 place-items-center rounded-lg border-0 bg-transparent text-[var(--oa-ink-2)] transition-colors hover:bg-[var(--oa-hover)] hover:text-[var(--oa-ink)] focus:outline-none focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-[var(--oa-focus)]';
</script>

<template>
  <!-- USUÁRIO — a única bolha do fio: cinza neutra, à direita -->
  <div v-if="type === 'user'" class="flex w-full justify-end">
    <div
      data-testid="ai-message-bubble-user"
      class="max-w-[75%] rounded-[18px] bg-[var(--oa-user-bub)] px-[15px] py-2.5 text-[14.5px] leading-normal text-[var(--oa-ink)]"
    >
      <p class="whitespace-pre-wrap break-words">{{ text }}</p>
    </div>
  </div>

  <!-- PENSANDO — três pontinhos, nunca um spinner -->
  <div
    v-else-if="type === 'thinking'"
    role="status"
    :aria-label="t('CONVERSATION.AI_ASSISTANT_PANEL.LOADING')"
    data-testid="ai-message-bubble-thinking"
    class="flex w-full items-center gap-2 text-[13.5px] text-[var(--oa-ink-2)]"
  >
    <span class="flex gap-1" aria-hidden="true">
      <i class="oa-dot" />
      <i class="oa-dot oa-dot--2" />
      <i class="oa-dot oa-dot--3" />
    </span>
    <span>{{ t('CONVERSATION.AI_ASSISTANT_PANEL.LOADING') }}</span>
  </div>

  <!-- ASSISTENTE — SEM bolha: texto solto na coluna, largura total -->
  <div v-else data-testid="ai-message-bubble-assistant" class="w-full">
    <div
      ref="bodyRef"
      :aria-live="isStreaming ? 'off' : undefined"
      data-testid="ai-message-body"
      class="oa-prose max-w-full"
      @click="handleBodyClick"
      v-html="html"
    />

    <span v-if="showCursor" class="oa-cursor" aria-hidden="true" />

    <!-- "Resposta gerada" announcement once streaming finishes -->
    <span
      v-if="isStreaming && isDone"
      role="status"
      aria-live="polite"
      class="sr-only"
    >
      {{ t('CONVERSATION.AI_ASSISTANT_PANEL.STREAM_COMPLETE') }}
    </span>

    <!-- Fonte citada — chip discreto, monocromático -->
    <div
      v-if="normalizedSources.length"
      class="mt-3 flex flex-wrap gap-x-2 gap-y-3"
    >
      <button
        v-for="source in normalizedSources"
        :key="source.key"
        type="button"
        data-testid="ai-message-source"
        :title="source.label"
        :aria-label="
          t('CONVERSATION.AI_ASSISTANT_PANEL.SOURCE.ARIA', {
            source: source.label,
          })
        "
        class="oa-hit-44 inline-flex h-8 max-w-full items-center gap-1.5 rounded-lg border border-solid border-[var(--oa-line)] bg-[var(--oa-bg)] px-2.5 text-xs text-[var(--oa-ink-2)] transition-colors hover:bg-[var(--oa-hover)] hover:text-[var(--oa-ink)] focus:outline-none focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-[var(--oa-focus)]"
        @click="handleSourceClick(source)"
      >
        <Icon
          icon="i-lucide-file-text"
          class="size-3.5 shrink-0"
          aria-hidden="true"
        />
        <span class="truncate">{{ source.label }}</span>
      </button>
    </div>

    <!-- Parar, durante o streaming -->
    <div v-if="showCancel" class="mt-3 flex flex-wrap items-center gap-2">
      <button
        type="button"
        data-testid="ai-message-stop"
        class="oa-hit-44 inline-flex h-9 items-center gap-1.5 rounded-lg border border-solid border-[var(--oa-line)] bg-transparent px-3 text-[12.5px] font-medium text-[var(--oa-ink-2)] transition-colors hover:bg-[var(--oa-hover)] hover:text-[var(--oa-ink)] focus:outline-none focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-[var(--oa-focus)]"
        @click="handleCancelStreaming"
      >
        <Icon icon="i-lucide-square" class="size-3" aria-hidden="true" />
        {{ t('CONVERSATION.AI_ASSISTANT_PANEL.ACTIONS.STOP') }}
      </button>
    </div>

    <!-- Ações abaixo da resposta -->
    <div v-if="showActions" class="mt-3 flex flex-wrap items-center gap-2">
      <button
        type="button"
        data-testid="ai-message-apply"
        class="oa-hit-44 inline-flex h-9 items-center gap-1.5 rounded-lg bg-[var(--oa-send)] px-3.5 text-[12.5px] font-medium text-[var(--oa-send-ink)] transition-opacity hover:opacity-85 focus:outline-none focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-[var(--oa-focus)]"
        @click="handleApply"
      >
        {{ t('CONVERSATION.AI_ASSISTANT_PANEL.ACTIONS.USE_AS_REPLY') }}
      </button>
      <button
        type="button"
        data-testid="ai-message-copy"
        :title="t('CONVERSATION.AI_ASSISTANT_PANEL.ACTIONS.COPY')"
        :aria-label="t('CONVERSATION.AI_ASSISTANT_PANEL.ACTIONS.COPY')"
        :class="ICON_BUTTON_CLASS"
        @click="handleCopy"
      >
        <Icon icon="i-lucide-copy" class="size-4" aria-hidden="true" />
      </button>
      <button
        type="button"
        data-testid="ai-message-retry"
        :title="t('CONVERSATION.AI_ASSISTANT_PANEL.ACTIONS.RETRY')"
        :aria-label="t('CONVERSATION.AI_ASSISTANT_PANEL.ACTIONS.RETRY')"
        :class="ICON_BUTTON_CLASS"
        @click="handleRetry"
      >
        <Icon icon="i-lucide-refresh-ccw" class="size-4" aria-hidden="true" />
      </button>
      <button
        type="button"
        data-testid="ai-message-feedback-up"
        :title="t('CONVERSATION.AI_ASSISTANT_PANEL.ACTIONS.FEEDBACK_GOOD')"
        :aria-label="t('CONVERSATION.AI_ASSISTANT_PANEL.ACTIONS.FEEDBACK_GOOD')"
        :class="ICON_BUTTON_CLASS"
        @click="handleFeedback('up')"
      >
        <Icon icon="i-lucide-thumbs-up" class="size-4" aria-hidden="true" />
      </button>
      <button
        type="button"
        data-testid="ai-message-feedback-down"
        :title="t('CONVERSATION.AI_ASSISTANT_PANEL.ACTIONS.FEEDBACK_BAD')"
        :aria-label="t('CONVERSATION.AI_ASSISTANT_PANEL.ACTIONS.FEEDBACK_BAD')"
        :class="ICON_BUTTON_CLASS"
        @click="handleFeedback('down')"
      >
        <Icon icon="i-lucide-thumbs-down" class="size-4" aria-hidden="true" />
      </button>
    </div>
  </div>
</template>
