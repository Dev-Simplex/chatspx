import { mount } from '@vue/test-utils';
import MessageThread from '../MessageThread.vue';

const item = (id, mine = false) => ({
  type: 'message',
  id,
  mine,
  content: `m${id}`,
  attachments: [],
  reactions: {},
});

const mountThread = items =>
  mount(MessageThread, {
    props: { items, currentUserId: 1 },
    global: { stubs: { MessageBubble: true } },
  });

// jsdom não calcula layout: simula a pessoa lá em cima da conversa.
const scrollUp = async wrapper => {
  const el = wrapper.find('.overflow-y-auto').element;
  Object.defineProperty(el, 'scrollHeight', {
    value: 2000,
    configurable: true,
  });
  Object.defineProperty(el, 'clientHeight', { value: 400, configurable: true });
  el.scrollTop = 200;
  el.scrollTo = () => {};
  await wrapper.find('.overflow-y-auto').trigger('scroll');
};

describe('MessageThread: ir para o fim', () => {
  it('aparece ao subir e conta as mensagens novas dos outros', async () => {
    const wrapper = mountThread([item(1), item(2)]);
    expect(wrapper.find('button[aria-label]').exists()).toBe(false);
    await scrollUp(wrapper);
    const button = () => wrapper.find('button.absolute');
    expect(button().exists()).toBe(true);
    await wrapper.setProps({ items: [item(1), item(2), item(3), item(4)] });
    expect(button().text()).toBe('2');
    await button().trigger('click');
    expect(button().text()).toBe('');
  });

  it('minha própria mensagem não entra na conta', async () => {
    const wrapper = mountThread([item(1)]);
    await scrollUp(wrapper);
    await wrapper.setProps({ items: [item(1), item(2, true)] });
    expect(wrapper.find('button.absolute').text()).toBe('');
  });
});
