import { shallowMount } from '@vue/test-utils';
import MessageList from '../MessageList.vue';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';

vi.mock('dashboard/composables/useTransformKeys', () => ({
  useCamelCase: vi.fn(message => message),
}));

// O componente lê o chat selecionado para saber se é conversa de grupo; sem store o
// setup quebra antes de renderizar.
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
    id: {
      type: Number,
      default: null,
    },
    inReplyTo: {
      type: Object,
      default: null,
    },
    groupWithNext: {
      type: Boolean,
      default: false,
    },
    groupWithPrevious: {
      type: Boolean,
      default: false,
    },
    isGroupConversation: {
      type: Boolean,
      default: false,
    },
  },
  template:
    '<div class="message-stub" :data-id="id" :data-in-reply-to="inReplyTo?.id || null" :data-group-with-next="String(groupWithNext)" :data-group-with-previous="String(groupWithPrevious)" :data-is-group="String(isGroupConversation)" />',
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

// Em grupo o senderId é sempre o contato-grupo: quem diferencia as pessoas é o
// group_sender gravado na ingestão.
const buildGroupMessage = ({ id, createdAt, lid, content = 'message' }) =>
  buildMessage({
    id,
    createdAt,
    content,
    contentAttributes: {
      groupSender: { name: `Pessoa ${lid}`, lid, phone: null },
    },
  });

const GROUP_CHAT = {
  id: 12,
  meta: { sender: { identifier: '120363040285567246@g.us' } },
};

const mountComponent = props =>
  shallowMount(MessageList, {
    props: {
      currentUserId: 1,
      messages: [],
      ...props,
    },
    global: {
      stubs: {
        Message: MessageStub,
        DateSeparator: DateSeparatorStub,
      },
    },
  });

const groupingFlags = wrapper =>
  wrapper.findAll('.message-stub').map(stub => ({
    withNext: stub.attributes()['data-group-with-next'],
    withPrevious: stub.attributes()['data-group-with-previous'],
  }));

describe('MessageList', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    storeState.selectedChat = {};
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

  describe('grouping in a 1:1 conversation', () => {
    it('keeps grouping consecutive messages from the same sender', () => {
      const wrapper = mountComponent({
        messages: [
          buildMessage({ id: 1, createdAt: 120 }),
          buildMessage({ id: 2, createdAt: 130 }),
        ],
      });

      expect(
        wrapper.findAll('.message-stub')[0].attributes()['data-is-group']
      ).toBe('false');
      expect(groupingFlags(wrapper)).toEqual([
        { withNext: 'true', withPrevious: 'false' },
        { withNext: 'false', withPrevious: 'true' },
      ]);
    });
  });

  describe('grouping in a group conversation', () => {
    beforeEach(() => {
      storeState.selectedChat = GROUP_CHAT;
    });

    it('detects the group conversation from the contact JID', () => {
      const wrapper = mountComponent({
        messages: [buildGroupMessage({ id: 1, createdAt: 120, lid: '111' })],
      });

      expect(wrapper.find('.message-stub').attributes()['data-is-group']).toBe(
        'true'
      );
    });

    it('groups consecutive messages from the same participant', () => {
      const wrapper = mountComponent({
        messages: [
          buildGroupMessage({ id: 1, createdAt: 120, lid: '111' }),
          buildGroupMessage({ id: 2, createdAt: 130, lid: '111' }),
        ],
      });

      expect(groupingFlags(wrapper)).toEqual([
        { withNext: 'true', withPrevious: 'false' },
        { withNext: 'false', withPrevious: 'true' },
      ]);
    });

    it('never merges different participants into the same visual block', () => {
      const wrapper = mountComponent({
        messages: [
          buildGroupMessage({ id: 1, createdAt: 120, lid: '111' }),
          buildGroupMessage({ id: 2, createdAt: 130, lid: '222' }),
        ],
      });

      expect(groupingFlags(wrapper)).toEqual([
        { withNext: 'false', withPrevious: 'false' },
        { withNext: 'false', withPrevious: 'false' },
      ]);
    });

    it('leaves legacy messages grouping exactly as they do today', () => {
      // Sem group_sender em nenhuma das duas o autor ainda está dentro do texto, em
      // cada bolha. Mudar o agrupamento aqui só mexeria no histórico sem ganho — e o
      // chat interno compartilha esta mesma lista.
      const wrapper = mountComponent({
        messages: [
          buildMessage({ id: 1, createdAt: 120, content: '👥 *A*\n\noi' }),
          buildMessage({
            id: 2,
            createdAt: 130,
            content: '👥 *B*\n\ntudo bem',
          }),
        ],
      });

      expect(groupingFlags(wrapper)).toEqual([
        { withNext: 'true', withPrevious: 'false' },
        { withNext: 'false', withPrevious: 'true' },
      ]);
    });

    it('does not group a legacy message with a message that has an author', () => {
      const wrapper = mountComponent({
        messages: [
          buildMessage({ id: 1, createdAt: 120, content: '👥 *A*\n\noi' }),
          buildGroupMessage({ id: 2, createdAt: 130, lid: '111' }),
        ],
      });

      expect(groupingFlags(wrapper)).toEqual([
        { withNext: 'false', withPrevious: 'false' },
        { withNext: 'false', withPrevious: 'false' },
      ]);
    });
  });
});
