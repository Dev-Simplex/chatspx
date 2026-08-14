import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { nextTick } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';

/**
 * Panel behaviour spec (worker A4).
 *
 * Child components are stubbed on purpose: this asserts what the panel does
 * (streams, stops, applies, errors) — not how a bubble looks, which belongs
 * to the component owner.
 */

const h = vi.hoisted(() => ({
  stream: {},
  thread: {},
  composer: { inserted: [] },
  uiSettings: {},
  media: { matches: true },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('@vueuse/core', async () => {
  const { computed } = await import('vue');
  // `isInline` do painel: true = coluna ao lado da conversa (>= 1100px),
  // false = gaveta sobreposta.
  return { useMediaQuery: () => computed(() => h.media.matches) };
});

vi.mock('vue-sonner', () => ({
  toast: Object.assign(() => {}, { error: () => {}, success: () => {} }),
}));

vi.mock('dashboard/composables', () => ({
  useTrack: () => {},
  useAlert: () => {},
}));

vi.mock('dashboard/composables/useReducedMotion', async () => {
  const { ref: r } = await import('vue');
  return { useReducedMotion: () => ({ prefersReducedMotion: r(true) }) };
});

vi.mock('dashboard/composables/useUISettings', async () => {
  const { ref: r } = await import('vue');
  const uiSettings = r({ is_copilot_panel_open: true });
  h.uiSettings.ref = uiSettings;
  h.uiSettings.updates = [];
  return {
    useUISettings: () => ({
      uiSettings,
      updateUISettings: payload => {
        h.uiSettings.updates.push(payload);
        uiSettings.value = { ...uiSettings.value, ...payload };
      },
    }),
  };
});

vi.mock('dashboard/composables/store', async () => {
  const { ref: r, computed } = await import('vue');
  const chat = r({ id: 681, messages: [{ id: 1 }], meta: { channel: '' } });
  const user = r({ name: 'Walisson Silva' });
  h.chat = chat;
  return {
    useMapGetter: name => {
      if (name === 'getSelectedChat') return chat;
      if (name === 'getCurrentUser') return user;
      if (name === 'draftMessages/getReplyEditorMode')
        return computed(() => '');
      return computed(() => null);
    },
    useStore: () => ({ dispatch: () => Promise.resolve() }),
    useFunctionGetter: () => computed(() => ''),
  };
});

// O painel deixou de ser um Dialog do Headless UI (correção C1): ele é uma
// coluna própria dentro do <main>, então não há mais nada de @headlessui/vue
// para stubar aqui.

vi.mock('../composables/useSmartSuggestions', async () => {
  const { computed } = await import('vue');
  return {
    useSmartSuggestions: () => ({
      activeSuggestion: computed(() => null),
      dismiss: () => {},
    }),
  };
});

vi.mock('../composables/useCopilotAssistant', async () => {
  const { computed } = await import('vue');
  return {
    useCopilotAssistant: () => ({
      activeAssistant: computed(() => ({ id: 7 })),
      hasAssistant: computed(() => true),
      fetchAssistants: () => Promise.resolve(),
    }),
  };
});

vi.mock('../composables/useComposerInsert', () => ({
  useComposerInsert: () => ({
    insertIntoComposer: text => {
      h.composer.inserted.push(text);
      return true;
    },
    usesRichEditor: { value: false },
  }),
}));

vi.mock('../composables/useCopilotStream', async () => {
  const { ref: r, computed } = await import('vue');
  const isStreaming = r(false);
  const streamedText = r('');
  const streamError = r(null);

  h.stream.isStreaming = isStreaming;
  h.stream.streamedText = streamedText;
  h.stream.stopCalls = [];

  const start = params => {
    isStreaming.value = true;
    streamedText.value = '';
    h.stream.onToken = params.onToken;
    h.stream.lastParams = params;
    return new Promise(resolve => {
      h.stream.settle = result => {
        isStreaming.value = false;
        resolve(result);
      };
    });
  };

  const stop = reason => {
    h.stream.stopCalls.push(reason);
  };

  return {
    useCopilotStream: () => ({
      isStreaming,
      streamedText,
      streamError,
      canStop: computed(() => isStreaming.value),
      start,
      stop,
    }),
    STREAM_STATUS: { DONE: 'done', CANCELLED: 'cancelled', ERROR: 'error' },
    STREAM_ERROR_CODES: {
      UNAUTHORIZED: 'unauthorized',
      RATE_LIMIT: 'rate_limit',
      CAPTAIN_UNSTABLE: 'captain_unstable',
      TIMEOUT: 'timeout',
      NETWORK: 'network',
      EMPTY_RESPONSE: 'empty_response',
      UNKNOWN: 'unknown',
    },
  };
});

vi.mock('../composables/useCopilotThread', async () => {
  const { ref: r, computed } = await import('vue');
  return {
    useCopilotThread: () => {
      const messages = r([]);
      const threadId = r(55);
      const isLoadingThread = r(false);
      h.thread.messages = messages;
      h.thread.isLoadingThread = isLoadingThread;
      h.thread.threadId = threadId;
      return {
        threadId,
        messages,
        isLoadingThread,
        isEmpty: computed(() => messages.value.length === 0),
        loadError: r(null),
        loadForConversation: () => Promise.resolve(),
        ensureThread: () => Promise.resolve(threadId.value),
        appendMessage: (_c, message) => {
          messages.value = [...messages.value, message];
        },
        updateMessage: (_c, id, patch) => {
          messages.value = messages.value.map(m =>
            m.id === id ? { ...m, ...patch } : m
          );
        },
        removeMessage: (_c, id) => {
          messages.value = messages.value.filter(m => m.id !== id);
        },
        truncateFrom: (_c, id) => {
          const index = messages.value.findIndex(m => m.id === id);
          if (index !== -1) messages.value = messages.value.slice(0, index);
        },
        reset: () => {
          messages.value = [];
        },
      };
    },
  };
});

import AIAssistantPanel from '../AIAssistantPanel.vue';

const BubbleStub = {
  name: 'AIMessageBubble',
  props: ['type', 'text', 'isStreaming'],
  emits: ['copy', 'apply', 'retry', 'feedback', 'cancel-streaming'],
  template:
    '<div class="bubble" :data-type="type" :data-streaming="String(isStreaming)">{{ text }}</div>',
};

const stubs = {
  AIMessageBubble: BubbleStub,
  AIQuickPromptCard: {
    name: 'AIQuickPromptCard',
    props: ['icon', 'label', 'description'],
    template: '<button class="quick-prompt" @click="$emit(\'click\')" />',
  },
  AIErrorBanner: {
    name: 'AIErrorBanner',
    props: ['errorType', 'retryAfterSeconds'],
    template: '<div class="error-banner" :data-type="errorType" />',
  },
  AILoadingShimmer: { template: '<div class="shimmer" />' },
  AISmartBanner: { template: '<div />' },
  Icon: { template: '<i />' },
};

// Os atalhos vivem num listener de `window` em fase de captura. Um painel que
// sobrevive ao teste anterior consome o Esc antes do painel atual — por isso
// todo wrapper é desmontado no fim de cada teste.
const mounted = [];

function mountPanel(props = {}) {
  const wrapper = mount(AIAssistantPanel, {
    props: { open: true, ...props },
    attachTo: document.body,
    global: { stubs },
  });
  mounted.push(wrapper);
  return wrapper;
}

/** Dispara o atalho como o painel escuta: keydown no window, fase de captura. */
function pressKey(key, init = {}) {
  const event = new window.KeyboardEvent('keydown', {
    key,
    bubbles: true,
    cancelable: true,
    ...init,
  });
  (init.target || document.activeElement || window).dispatchEvent(event);
  return event;
}

async function sendQuestion(wrapper, text = 'o que faço agora?') {
  const textarea = wrapper.find('textarea');
  await textarea.setValue(text);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
}

describe('AIAssistantPanel', () => {
  beforeEach(() => {
    h.composer.inserted = [];
    h.stream.stopCalls = [];
    h.uiSettings.updates = [];
    h.media.matches = true;
    h.uiSettings.ref.value = { is_copilot_panel_open: true };
    if (h.chat) {
      h.chat.value = { id: 681, messages: [{ id: 1 }], meta: { channel: '' } };
    }
    document.body.innerHTML = '';
  });

  afterEach(() => {
    while (mounted.length) mounted.pop().unmount();
    // The stream refs are shared across mounts (module-level in the mock) —
    // a test that leaves a stream pending must not leak into the next one.
    if (h.stream.isStreaming) h.stream.isStreaming.value = false;
    if (h.stream.streamedText) h.stream.streamedText.value = '';
    if (h.thread.messages) h.thread.messages.value = [];
    if (h.thread.isLoadingThread) h.thread.isLoadingThread.value = false;
  });

  it('renders the text progressively as tokens arrive', async () => {
    const wrapper = mountPanel();
    await sendQuestion(wrapper);

    const snapshots = [];
    const emit = delta => {
      h.stream.streamedText.value += delta;
      h.stream.onToken(delta);
    };

    emit('Olhando ');
    await nextTick();
    snapshots.push(wrapper.findAll('.bubble').at(-1).text());

    emit('o histórico ');
    await nextTick();
    snapshots.push(wrapper.findAll('.bubble').at(-1).text());

    emit('do pedido.');
    await nextTick();
    snapshots.push(wrapper.findAll('.bubble').at(-1).text());

    // Each render shows strictly more text than the previous one.
    expect(snapshots).toEqual([
      'Olhando',
      'Olhando o histórico',
      'Olhando o histórico do pedido.',
    ]);

    h.stream.settle({
      status: 'done',
      text: 'Olhando o histórico do pedido.',
      messageId: 900,
      error: null,
    });
    await flushPromises();
    expect(wrapper.findAll('.bubble').at(-1).attributes('data-streaming')).toBe(
      'false'
    );
  });

  it('has a single stop control — the one the bubble draws — and it cancels', async () => {
    // Regressão C1: o painel desenhava um "Parar" de 368x32 embaixo do que a
    // bolha já desenhava (74x30). Eram dois botões idênticos empilhados.
    const wrapper = mountPanel();
    await sendQuestion(wrapper);

    expect(wrapper.find('[data-testid="ai-stop-streaming"]').exists()).toBe(
      false
    );
    expect(h.stream.isStreaming.value).toBe(true);

    await wrapper
      .findAllComponents({ name: 'AIMessageBubble' })
      .at(-1)
      // eslint-disable-next-line vue/custom-event-name-casing -- kebab-case é o contrato real emitido pela bolha
      .vm.$emit('cancel-streaming');
    expect(h.stream.stopCalls).toContain('user');

    h.stream.settle({
      status: 'cancelled',
      text: 'parcial',
      messageId: null,
      error: null,
    });
    await flushPromises();
    expect(h.stream.isStreaming.value).toBe(false);
  });

  it('renders a visible error with a retry button when the key is rejected', async () => {
    const wrapper = mountPanel();
    await sendQuestion(wrapper);

    h.stream.settle({
      status: 'error',
      text: '',
      messageId: null,
      error: { code: 'unauthorized', message: '' },
    });
    await flushPromises();

    const fallback = wrapper.find('[data-testid="ai-fallback-error"]');
    expect(fallback.exists()).toBe(true);
    expect(fallback.text()).toContain('ERRORS.UNAUTHORIZED.TITLE');
    expect(wrapper.find('[data-testid="ai-error-retry"]').exists()).toBe(true);
    // No spinner left behind.
    expect(h.stream.isStreaming.value).toBe(false);
  });

  it('routes banner-known errors to AIErrorBanner instead', async () => {
    const wrapper = mountPanel();
    await sendQuestion(wrapper);

    h.stream.settle({
      status: 'error',
      text: '',
      messageId: null,
      error: { code: 'rate_limit' },
    });
    await flushPromises();

    expect(wrapper.find('.error-banner').attributes('data-type')).toBe(
      'rate_limit'
    );
    expect(wrapper.find('[data-testid="ai-fallback-error"]').exists()).toBe(
      false
    );
  });

  it('"use as reply" pushes the answer into the composer and emits apply', async () => {
    const wrapper = mountPanel();
    await sendQuestion(wrapper);
    h.stream.settle({
      status: 'done',
      text: 'Marina, localizei seu pedido.',
      messageId: 12,
      error: null,
    });
    await flushPromises();

    // "Usar como resposta" vive na bolha (AIMessageBubble), junto das outras
    // ações da mensagem. Aqui a bolha é stub, então o contrato testado é o
    // evento `apply` que ela emite — que é o que o painel de fato consome.
    const bubble = wrapper
      .findAllComponents({ name: 'AIMessageBubble' })
      .at(-1);
    await bubble.vm.$emit('apply', 'Marina, localizei seu pedido.');
    await flushPromises();

    expect(h.composer.inserted).toEqual(['Marina, localizei seu pedido.']);
    expect(wrapper.emitted('apply')[0]).toEqual([
      'Marina, localizei seu pedido.',
    ]);
    // Panel closes so the agent lands on the composer.
    expect(h.uiSettings.updates).toContainEqual({
      is_copilot_panel_open: false,
    });
  });

  it('regenerate replaces the last answer with a new stream', async () => {
    const wrapper = mountPanel();
    await sendQuestion(wrapper, 'resume isso');
    h.stream.settle({
      status: 'done',
      text: 'primeira versão',
      messageId: 1,
      error: null,
    });
    await flushPromises();
    expect(h.thread.messages.value).toHaveLength(2);

    // Refazer também é ação da mensagem: a bolha emite `retry`.
    await wrapper
      .findAllComponents({ name: 'AIMessageBubble' })
      .at(-1)
      .vm.$emit('retry');
    await flushPromises();

    // Same question re-asked, old answer dropped.
    expect(h.stream.lastParams.message).toBe('resume isso');
    expect(h.thread.messages.value.filter(m => m.type === 'user')).toHaveLength(
      1
    );
  });

  it('editing the question puts it back in the composer', async () => {
    const wrapper = mountPanel();
    await sendQuestion(wrapper, 'pergunta errada');
    h.stream.settle({
      status: 'done',
      text: 'resposta',
      messageId: 2,
      error: null,
    });
    await flushPromises();

    await wrapper
      .findAll('button')
      .find(b => b.text().includes('EDIT_QUESTION'))
      .trigger('click');
    await nextTick();

    expect(wrapper.find('textarea').element.value).toBe('pergunta errada');

    await wrapper.find('textarea').setValue('pergunta certa');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(h.stream.lastParams.message).toBe('pergunta certa');
    const questions = h.thread.messages.value.filter(m => m.type === 'user');
    expect(questions).toHaveLength(1);
    expect(questions[0].text).toBe('pergunta certa');
  });

  it('the send button is disabled while the composer is empty', async () => {
    const wrapper = mountPanel();
    const button = wrapper.find('button[type="submit"]');
    expect(button.attributes('disabled')).toBeDefined();

    await wrapper.find('textarea').setValue('oi');
    expect(
      wrapper.find('button[type="submit"]').attributes('disabled')
    ).toBeUndefined();
  });

  it('loading a thread is a different screen from the empty state', async () => {
    const wrapper = mountPanel();
    expect(wrapper.find('.quick-prompt').exists()).toBe(true);
    expect(wrapper.find('.shimmer').exists()).toBe(false);

    h.thread.isLoadingThread.value = true;
    await nextTick();

    expect(wrapper.find('.shimmer').exists()).toBe(true);
    expect(wrapper.find('.quick-prompt').exists()).toBe(false);
  });

  it('a quick prompt sends a real question through the stream', async () => {
    const wrapper = mountPanel();
    await wrapper.find('.quick-prompt').trigger('click');
    await flushPromises();

    expect(h.stream.lastParams.message).toBe(
      'CONVERSATION.AI_ASSISTANT_PANEL.QUICK_PROMPTS.SUMMARIZE.PROMPT'
    );
  });

  // ── Forma: coluna, não modal (correção C1) ────────────────────────────────

  it('is a column beside the conversation, not an overlay, on desktop', () => {
    h.media.matches = true;
    const wrapper = mountPanel();
    const panel = wrapper.find('[data-ai-panel]');

    expect(panel.exists()).toBe(true);
    expect(panel.element.tagName).toBe('ASIDE');
    expect(panel.classes()).toContain('static');
    expect(panel.classes()).toContain('w-[360px]');
    // Nada de véu nem de posicionamento sobre a conversa.
    expect(panel.classes()).not.toContain('fixed');
    expect(wrapper.html()).not.toContain('bg-black/30');
  });

  it('falls back to an overlay drawer only when there is no room', () => {
    h.media.matches = false;
    const wrapper = mountPanel();
    const panel = wrapper.find('[data-ai-panel]');

    expect(panel.classes()).toContain('fixed');
    expect(panel.classes()).not.toContain('static');
    h.media.matches = true;
  });

  it('does not render without a conversation — it would squeeze other screens', () => {
    const chat = h.chat;
    chat.value = { id: null, messages: [], meta: { channel: '' } };
    const wrapper = mountPanel();
    expect(wrapper.find('[data-ai-panel]').exists()).toBe(false);
    chat.value = { id: 681, messages: [{ id: 1 }], meta: { channel: '' } };
  });

  it('takes the right rail from the contact panel and gives it back on close', async () => {
    h.uiSettings.ref.value = {
      is_copilot_panel_open: false,
      is_contact_sidebar_open: true,
    };
    const wrapper = mountPanel({ open: false });
    h.uiSettings.updates = [];

    await wrapper.setProps({ open: true });
    // Uma escrita só, com as duas chaves: duas chamadas seguidas competem e o
    // painel de contato ressuscita (visto em 1920 na validação com Playwright).
    expect(h.uiSettings.updates).toContainEqual({
      is_copilot_panel_open: true,
      is_contact_sidebar_open: false,
    });

    await wrapper.setProps({ open: false });
    expect(h.uiSettings.updates).toContainEqual({
      is_contact_sidebar_open: true,
    });
  });

  it('Esc closes the panel once there is nothing left to dismiss', async () => {
    const wrapper = mountPanel();
    h.uiSettings.updates = [];

    // Com rascunho no composer, o primeiro Esc limpa o rascunho.
    await wrapper.find('textarea').setValue('metade de uma pergunta');
    pressKey('Escape');
    await nextTick();
    expect(wrapper.find('textarea').element.value).toBe('');
    expect(h.uiSettings.updates).not.toContainEqual({
      is_copilot_panel_open: false,
    });

    // Sem nada para descartar, o Esc cumpre o que o rodapé promete: fecha.
    pressKey('Escape');
    await nextTick();
    expect(h.uiSettings.updates).toContainEqual({
      is_copilot_panel_open: false,
    });
    expect(wrapper.emitted('close').at(-1)).toEqual(['escape']);
  });

  it('gives focus back to whatever opened it', async () => {
    const trigger = document.createElement('button');
    trigger.setAttribute('data-testid', 'copilot-launcher');
    document.body.appendChild(trigger);
    trigger.focus();

    const wrapper = mountPanel({ open: false });
    await wrapper.setProps({ open: true });
    // O painel toma o foco para o composer.
    await nextTick();
    expect(document.activeElement).not.toBe(trigger);

    await wrapper.setProps({ open: false });
    await nextTick();
    await nextTick();
    expect(document.activeElement).toBe(trigger);

    trigger.remove();
  });

  it('never launches the onboarding tour when the agent accepts an answer', async () => {
    const wrapper = mountPanel();
    await sendQuestion(wrapper);
    h.stream.settle({
      status: 'done',
      text: 'Marina, localizei seu pedido.',
      messageId: 12,
      error: null,
    });
    await flushPromises();

    await wrapper
      .findAllComponents({ name: 'AIMessageBubble' })
      .at(-1)
      .vm.$emit('apply', 'Marina, localizei seu pedido.');
    await flushPromises();

    // Shepherd monta `.shepherd-modal-overlay-container` no body ao iniciar.
    expect(document.querySelector('.shepherd-modal-overlay-container')).toBe(
      null
    );
    expect(document.querySelector('.shepherd-element')).toBe(null);
  });
});
