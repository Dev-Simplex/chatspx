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
});
