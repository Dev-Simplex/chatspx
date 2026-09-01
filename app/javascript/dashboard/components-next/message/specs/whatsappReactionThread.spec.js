import { shallowMount, mount } from '@vue/test-utils';
import MessageList from '../MessageList.vue';
import MessageReactions from '../MessageReactions.vue';

vi.mock('dashboard/composables/useTransformKeys', () => ({
  useCamelCase: vi.fn(message => message),
}));

const storeState = vi.hoisted(() => ({ selectedChat: {} }));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    getters: {
      get getSelectedChat() {
        return storeState.selectedChat;
      },
      getCurrentUser: {},
      getCurrentAccount: {},
      'inboxes/getInbox': () => ({}),
    },
  }),
  useMapGetter: () => ({ value: [] }),
}));

const MessageStub = {
  name: 'Message',
  props: {
    id: { type: Number, default: null },
    whatsappReactions: { type: Array, default: () => [] },
  },
  template:
    '<div class="message-stub" :data-id="id" :data-reactions="JSON.stringify(whatsappReactions)" />',
};

const ReactionsStub = {
  name: 'MessageReactions',
  props: {
    chips: { type: Array, default: () => [] },
    readonly: { type: Boolean, default: false },
  },
  template:
    '<div class="reactions-stub" :data-readonly="String(readonly)" :data-chips="JSON.stringify(chips)" />',
};

const DateSeparatorStub = {
  name: 'DateSeparator',
  template: '<div class="date-separator-stub" />',
};

const buildMessage = ({
  id,
  createdAt = 100,
  content = 'message',
  contentAttributes = {},
  messageType = 0,
}) => ({
  id,
  createdAt,
  messageType,
  status: 'sent',
  private: false,
  senderId: 1,
  attachments: [],
  content,
  contentAttributes,
});

const mountList = messages =>
  shallowMount(MessageList, {
    props: { currentUserId: 1, messages },
    global: {
      stubs: {
        Message: MessageStub,
        MessageReactions: ReactionsStub,
        DateSeparator: DateSeparatorStub,
      },
    },
  });

const renderedIds = wrapper =>
  wrapper
    .findAll('.message-stub')
    .map(stub => Number(stub.attributes()['data-id']));

const reactionsOf = (wrapper, id) => {
  const stub = wrapper
    .findAll('.message-stub')
    .find(node => Number(node.attributes()['data-id']) === id);
  return JSON.parse(stub.attributes()['data-reactions']);
};

describe('reação de WhatsApp no fio', () => {
  beforeEach(() => {
    storeState.selectedChat = {};
  });

  it('não renderiza a reação como mensagem e a ancora na bolha reagida', () => {
    const wrapper = mountList([
      buildMessage({ id: 10, createdAt: 100, content: 'Resolvido' }),
      buildMessage({
        id: 11,
        createdAt: 160,
        content: '👥 *Angela Tozi (229480102662169@lid)*\n\n*Reagiu com* 👍',
        contentAttributes: { inReplyTo: 10 },
      }),
    ]);

    expect(renderedIds(wrapper)).toEqual([10]);
    expect(reactionsOf(wrapper, 10)).toEqual([
      { emoji: '👍', count: 1, title: 'Angela Tozi' },
    ]);
  });

  it('nunca expõe o identificador técnico no tooltip do chip', () => {
    const wrapper = mountList([
      buildMessage({ id: 10, createdAt: 100, content: 'Aviso' }),
      buildMessage({
        id: 11,
        createdAt: 160,
        content:
          '👥 *‎Rogerio José Da Silva (229480102662169@lid)*\n\n*Reagiu com* 👎🏽',
        contentAttributes: { inReplyTo: 10 },
      }),
    ]);

    expect(wrapper.html()).not.toContain('@lid');
    expect(reactionsOf(wrapper, 10)[0].title).toBe('Rogerio José Da Silva');
  });

  it('reação órfã vira chip solto, nunca bolha de texto', () => {
    const wrapper = mountList([
      buildMessage({ id: 10, createdAt: 100, content: 'Mensagem' }),
      buildMessage({
        id: 11,
        createdAt: 160,
        content: '*Reagiu com* 🚀',
        contentAttributes: {},
      }),
    ]);

    expect(renderedIds(wrapper)).toEqual([10]);

    // O ambiente de teste roda em `en`; a chave existe nos dois locales.
    const chipHost = wrapper.find('.reactions-stub');
    expect(chipHost.exists()).toBe(true);
    expect(chipHost.attributes()['data-readonly']).toBe('true');
    expect(JSON.parse(chipHost.attributes()['data-chips'])).toEqual([
      { emoji: '🚀', count: 1, title: 'Reaction received from WhatsApp' },
    ]);
  });

  it('conversa sem reação nenhuma continua idêntica', () => {
    const wrapper = mountList([
      buildMessage({ id: 10, createdAt: 100, content: 'Oi' }),
      buildMessage({ id: 11, createdAt: 160, content: 'Tudo bem?' }),
    ]);

    expect(renderedIds(wrapper)).toEqual([10, 11]);
    expect(reactionsOf(wrapper, 10)).toEqual([]);
    expect(reactionsOf(wrapper, 11)).toEqual([]);
    expect(wrapper.find('.reactions-stub').exists()).toBe(false);
  });

  it('não some com a reação no modo encaminhar', () => {
    const wrapper = shallowMount(MessageList, {
      props: {
        currentUserId: 1,
        isForwardMode: true,
        messages: [
          buildMessage({ id: 10, createdAt: 100, content: 'Resolvido' }),
          buildMessage({
            id: 11,
            createdAt: 160,
            content: '*Reagiu com* 👍',
            contentAttributes: { inReplyTo: 10 },
          }),
        ],
      },
      global: {
        stubs: {
          Message: MessageStub,
          MessageReactions: ReactionsStub,
          DateSeparator: DateSeparatorStub,
        },
      },
    });

    // A reação não é conteúdo encaminhável: some da seleção junto com o fio.
    expect(renderedIds(wrapper)).toEqual([10]);
  });
});

describe('MessageReactions em modo readonly', () => {
  const mountChips = chips =>
    mount(MessageReactions, {
      props: { mode: 'chips', readonly: true, chips },
    });

  it('desenha chip por emoji com a contagem e sem botão clicável', () => {
    const wrapper = mountChips([
      { emoji: '👍', count: 2, title: 'Ana, Carla' },
      { emoji: '🎉', count: 1, title: 'Bruno' },
    ]);

    const chips = wrapper.findAll('.reaction-chip');
    expect(chips).toHaveLength(2);
    expect(chips[0].text().replace(/\s+/g, '')).toBe('👍2');
    expect(chips[0].element.tagName).toBe('SPAN');
    expect(wrapper.find('button').exists()).toBe(false);
  });

  it('não renderiza nada quando não há reação', () => {
    expect(mountChips([]).find('.reaction-chip').exists()).toBe(false);
  });

  it('usa o rótulo dos autores como aria-label, sem identificador técnico', () => {
    const wrapper = mountChips([
      { emoji: '👍', count: 1, title: 'Rogerio José Da Silva' },
    ]);

    expect(wrapper.find('.reaction-chip').attributes('aria-label')).toBe(
      'Rogerio José Da Silva'
    );
    expect(wrapper.html()).not.toContain('@lid');
  });
});
