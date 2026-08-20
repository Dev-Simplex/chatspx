import { createStore } from 'vuex';
import { shallowMount } from '@vue/test-utils';
import MessageList from '../MessageList.vue';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';

vi.mock('dashboard/composables/useTransformKeys', () => ({
  useCamelCase: vi.fn(message => message),
}));

const MessageStub = {
  name: 'Message',
  props: {
    id: {
      type: Number,
      default: null,
    },
    inReplyTo: {
      type: Object,
      default: null,
    },
  },
  template:
    '<div class="message-stub" :data-id="id" :data-in-reply-to="inReplyTo?.id || null" />',
};

const DateSeparatorStub = {
  name: 'DateSeparator',
  template: '<div class="date-separator-stub" />',
};

const buildMessage = ({
  id,
  createdAt,
  content = 'message',
  contentAttributes = {},
}) => ({
  id,
  createdAt,
  messageType: 0,
  status: 'sent',
  private: false,
  senderId: 1,
  attachments: [],
  content,
  contentAttributes,
});

// MessageList lê o store (conversa/caixa selecionadas) para decidir o isolamento por
// agente do mapa de reply/quote — sem um $store instalado os computeds estouram.
const buildStore = ({
  chat = { id: 55, inbox_id: 3 },
  agentIsolation = false,
  supervisedTeams = [],
} = {}) =>
  createStore({
    getters: {
      getSelectedChat: () => chat,
      getCurrentUser: () => ({
        id: 1,
        accounts: [{ id: 100, role: 'agent' }],
      }),
      getCurrentAccount: () => ({ id: 100 }),
      getConversationById: () => () => chat,
    },
    modules: {
      inboxes: {
        namespaced: true,
        getters: {
          getInbox: () => () => ({ agent_message_isolation: agentIsolation }),
        },
      },
      teams: {
        namespaced: true,
        getters: { getSupervisedTeams: () => supervisedTeams },
      },
    },
  });

const mountComponent = (props, storeOptions) =>
  shallowMount(MessageList, {
    props: {
      currentUserId: 1,
      messages: [],
      ...props,
    },
    global: {
      plugins: [buildStore(storeOptions)],
      stubs: {
        Message: MessageStub,
        DateSeparator: DateSeparatorStub,
      },
    },
  });

describe('MessageList', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('reuses cached camelCase conversion for existing messages', async () => {
    const firstMessage = buildMessage({ id: 1, createdAt: 120 });
    const secondMessage = buildMessage({ id: 2, createdAt: 240 });
    const wrapper = mountComponent({
      messages: [firstMessage, secondMessage],
    });

    expect(useCamelCase).toHaveBeenCalledTimes(2);

    await wrapper.setProps({
      messages: [firstMessage, secondMessage],
    });
    expect(useCamelCase).toHaveBeenCalledTimes(2);

    await wrapper.setProps({
      messages: [
        firstMessage,
        secondMessage,
        buildMessage({ id: 3, createdAt: 360 }),
      ],
    });
    expect(useCamelCase).toHaveBeenCalledTimes(3);
  });

  it('resolves inReplyTo message via id lookup map', () => {
    const firstMessage = buildMessage({ id: 1, createdAt: 120 });
    const secondMessage = buildMessage({
      id: 2,
      createdAt: 240,
      contentAttributes: { inReplyTo: 1 },
    });

    const wrapper = mountComponent({
      messages: [firstMessage, secondMessage],
    });

    const renderedMessages = wrapper.findAll('.message-stub');
    expect(renderedMessages).toHaveLength(2);
    expect(renderedMessages[1].attributes()['data-in-reply-to']).toBe('1');
  });

  // Isolamento por agente x supervisão: a mensagem citada é de OUTRO agente. O agente
  // comum não pode ver o quote; o supervisor do time da conversa pode (o backend já
  // devolve a bolha inteira para ele).
  describe('quote/reply sob agent_message_isolation', () => {
    const quotedFromAnotherAgent = () => [
      { ...buildMessage({ id: 1, createdAt: 120 }), agentId: 2 },
      buildMessage({
        id: 2,
        createdAt: 240,
        contentAttributes: { inReplyTo: 1 },
      }),
    ];

    it('esconde o quote do agente comum', () => {
      const wrapper = mountComponent(
        { messages: quotedFromAnotherAgent() },
        { agentIsolation: true }
      );

      // sem quote o stub nem renderiza o atributo (inReplyTo === null)
      const renderedMessages = wrapper.findAll('.message-stub');
      expect(
        renderedMessages[1].attributes()['data-in-reply-to']
      ).toBeUndefined();
    });

    it('mostra o quote para o supervisor do time da conversa', () => {
      const wrapper = mountComponent(
        { messages: quotedFromAnotherAgent() },
        {
          chat: { id: 55, inbox_id: 3, meta: { team: { id: 7 } } },
          agentIsolation: true,
          supervisedTeams: [{ id: 7 }],
        }
      );

      const renderedMessages = wrapper.findAll('.message-stub');
      expect(renderedMessages[1].attributes()['data-in-reply-to']).toBe('1');
    });
  });
});
