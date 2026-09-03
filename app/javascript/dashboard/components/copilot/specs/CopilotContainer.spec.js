/* eslint-disable vue/custom-event-name-casing */
import { ref } from 'vue';
import { createStore } from 'vuex';
import { flushPromises, shallowMount } from '@vue/test-utils';
import CopilotContainer from '../CopilotContainer.vue';

const {
  uiSettings,
  updateUISettings,
  useAlert,
  captainConfigStore,
  copilotMessagesGet,
} = vi.hoisted(() => ({
  uiSettings: {
    value: {
      is_contact_sidebar_open: false,
      is_copilot_panel_open: true,
      preferred_captain_assistant_id: null,
    },
  },
  updateUISettings: vi.fn(),
  useAlert: vi.fn(),
  captainConfigStore: {
    llmConnection: { configured: true },
    fetch: vi.fn().mockResolvedValue(),
  },
  copilotMessagesGet: vi.fn().mockResolvedValue({ data: { payload: [] } }),
}));

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings,
    updateUISettings,
  }),
}));

vi.mock('@vueuse/core', () => ({
  useWindowSize: () => ({
    width: ref(1280),
  }),
}));

vi.mock('@vueuse/components', () => ({
  vOnClickOutside: {},
}));

vi.mock('dashboard/composables', () => ({
  useAlert,
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({
    isAdmin: ref(true),
  }),
}));

vi.mock('dashboard/store/captain/preferences', () => ({
  useCaptainConfigStore: () => captainConfigStore,
}));

vi.mock('dashboard/api/captain/copilotMessages', () => ({
  default: {
    get: copilotMessagesGet,
  },
}));

// ChatSPX: o filho renderizado por CopilotContainer e `CopilotPanel`
// (components-next/copilot/CopilotPanel.vue), nao `Copilot`. Com o nome antigo o stub nunca
// era aplicado, o painel real nao montava e os exemplos seguintes caiam em
// "Cannot call vm on an empty VueWrapper" — falha em cascata a partir de UM nome errado.
// O rename ja esta em `origin/homologacao`; era o spec que tinha ficado para tras.
const CopilotStub = {
  name: 'CopilotPanel',
  props: [
    'isAwaitingResponse',
    'hasTimedOut',
    'timeoutMessage',
    'messages',
    'assistants',
    'activeAssistant',
  ],
  template:
    '<div data-testid="copilot-stub" :data-awaiting="String(isAwaitingResponse)" :data-timeout="String(hasTimedOut)" />',
};

const CaptainApiKeyMissingModalStub = {
  name: 'CaptainApiKeyMissingModal',
  template: '<div data-testid="api-key-modal" />',
  methods: {
    open() {},
    close() {},
  },
};

const buildStore = (captainEnabled = true) => {
  const copilotRecords = [];
  const store = createStore({
    getters: {
      getCurrentUser: () => ({ id: 1 }),
      'captainAssistants/getRecords': () => [{ id: 11, name: 'Assistant A' }],
      'captainAssistants/getUIFlags': () => ({ fetchingList: false }),
      getCopilotAssistant: () => null,
      getSelectedChat: () => ({ id: 99 }),
      getCurrentAccountId: () => 3,
      'accounts/isFeatureEnabledonAccount': () => () => captainEnabled,
      'copilotMessages/getMessagesByThreadId': () => threadId =>
        copilotRecords
          .filter(record => record.copilot_thread?.id === Number(threadId))
          .sort((a, b) => a.id - b.id),
    },
  });

  vi.spyOn(store, 'dispatch').mockImplementation(async (action, payload) => {
    if (action === 'copilotThreads/create') {
      return { id: 123 };
    }
    if (action === 'copilotMessages/create') {
      return { id: 456 };
    }
    if (action === 'copilotMessages/upsert') {
      const existingIndex = copilotRecords.findIndex(
        record => record.id === payload.id
      );
      if (existingIndex >= 0) {
        copilotRecords[existingIndex] = payload;
      } else {
        copilotRecords.push(payload);
      }
      return payload;
    }
    return {};
  });

  return store;
};

const mountComponent = (captainEnabled = true) => {
  const store = buildStore(captainEnabled);
  const wrapper = shallowMount(CopilotContainer, {
    global: {
      plugins: [store],
      stubs: {
        CopilotPanel: CopilotStub,
        CaptainApiKeyMissingModal: CaptainApiKeyMissingModalStub,
      },
    },
  });

  return { wrapper, store };
};

describe('CopilotContainer.vue', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
    uiSettings.value = {
      is_contact_sidebar_open: false,
      is_copilot_panel_open: true,
      preferred_captain_assistant_id: null,
    };
    captainConfigStore.llmConnection = { configured: true };
    captainConfigStore.fetch = vi.fn().mockResolvedValue();
    copilotMessagesGet.mockResolvedValue({ data: { payload: [] } });
  });

  afterEach(() => {
    vi.clearAllTimers();
    vi.useRealTimers();
  });

  it('loads assistants and renders Copilot panel when Captain is enabled', () => {
    const { wrapper, store } = mountComponent(true);

    expect(store.dispatch).toHaveBeenCalledWith('captainAssistants/get');
    expect(wrapper.find('[data-testid="copilot-stub"]').exists()).toBe(true);
  });

  it('does not fetch assistants when Captain feature is disabled', () => {
    const { store } = mountComponent(false);

    expect(store.dispatch).not.toHaveBeenCalledWith('captainAssistants/get');
  });

  it('opens API key modal and blocks message when account has no key', async () => {
    captainConfigStore.llmConnection = { configured: false };
    const { wrapper, store } = mountComponent(true);

    await wrapper.findComponent(CopilotStub).vm.$emit('send-message', 'hello');
    await flushPromises();

    expect(captainConfigStore.fetch).toHaveBeenCalledWith({
      accountId: 3,
      force: false,
    });
    expect(store.dispatch).not.toHaveBeenCalledWith(
      'copilotThreads/create',
      expect.anything()
    );
    expect(wrapper.find('[data-testid="api-key-modal"]').exists()).toBe(true);
  });

  it('sends message when API key is configured', async () => {
    captainConfigStore.llmConnection = { configured: true };
    const { wrapper, store } = mountComponent(true);

    await wrapper.findComponent(CopilotStub).vm.$emit('send-message', 'hello');
    await flushPromises();

    expect(store.dispatch).toHaveBeenCalledWith('copilotThreads/create', {
      assistant_id: 11,
      conversation_id: 99,
      message: 'hello',
    });
    expect(copilotMessagesGet).toHaveBeenCalledWith(123);
  });

  it('starts polling and stops awaiting when assistant response arrives', async () => {
    copilotMessagesGet.mockResolvedValue({
      data: {
        payload: [
          {
            id: 90,
            message_type: 'assistant',
            message: { content: 'Done' },
            copilot_thread: { id: 123 },
          },
        ],
      },
    });

    const { wrapper } = mountComponent(true);

    await wrapper.findComponent(CopilotStub).vm.$emit('send-message', 'hello');
    await flushPromises();

    expect(copilotMessagesGet).toHaveBeenCalledWith(123);
    expect(wrapper.findComponent(CopilotStub).props('isAwaitingResponse')).toBe(
      false
    );
    expect(wrapper.findComponent(CopilotStub).props('hasTimedOut')).toBe(false);
  });

  it('marks timeout after 30 seconds without assistant response', async () => {
    copilotMessagesGet.mockResolvedValue({
      data: {
        payload: [
          {
            id: 50,
            message_type: 'assistant_thinking',
            message: { content: 'thinking' },
            copilot_thread: { id: 123 },
          },
        ],
      },
    });

    const { wrapper } = mountComponent(true);

    await wrapper.findComponent(CopilotStub).vm.$emit('send-message', 'hello');
    await flushPromises();

    expect(wrapper.findComponent(CopilotStub).props('isAwaitingResponse')).toBe(
      true
    );

    vi.advanceTimersByTime(30_000);
    await flushPromises();

    expect(wrapper.findComponent(CopilotStub).props('hasTimedOut')).toBe(true);
    expect(wrapper.findComponent(CopilotStub).props('isAwaitingResponse')).toBe(
      false
    );
  });

  it('retries last message manually after timeout', async () => {
    copilotMessagesGet.mockResolvedValue({
      data: {
        payload: [
          {
            id: 51,
            message_type: 'assistant_thinking',
            message: { content: 'thinking' },
            copilot_thread: { id: 123 },
          },
        ],
      },
    });

    const { wrapper, store } = mountComponent(true);

    await wrapper.findComponent(CopilotStub).vm.$emit('send-message', 'hello');
    await flushPromises();
    vi.advanceTimersByTime(30_000);
    await flushPromises();

    await wrapper.findComponent(CopilotStub).vm.$emit('retry');
    await flushPromises();

    expect(store.dispatch).toHaveBeenCalledWith('copilotMessages/create', {
      assistant_id: 11,
      conversation_id: 99,
      threadId: 123,
      message: 'hello',
    });
  });

  it('opens API key modal on captain_api_key_missing backend error', async () => {
    captainConfigStore.llmConnection = { configured: true };
    const { wrapper, store } = mountComponent(true);

    store.dispatch.mockImplementation(async action => {
      if (action === 'copilotThreads/create') {
        const error = new Error('Missing key');
        error.code = 'captain_api_key_missing';
        throw error;
      }

      return {};
    });

    await wrapper.findComponent(CopilotStub).vm.$emit('send-message', 'hello');
    await flushPromises();

    expect(wrapper.find('[data-testid="api-key-modal"]').exists()).toBe(true);
  });
});
