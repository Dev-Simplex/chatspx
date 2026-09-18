import { flushPromises, shallowMount } from '@vue/test-utils';
import PreChatForm from './PreChatForm.vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { createStore } from 'vuex';

vi.mock('vue-router', () => ({ useRouter: () => ({ replace: vi.fn() }) }));

it('shows the widget alert after a failed pre-chat submission', async () => {
  window.chatwootWebChannel = { preChatFormOptions: {} };
  const store = createStore({
    modules: {
      conversation: {
        namespaced: true,
        actions: { clearConversations: () => {} },
      },
      conversationAttributes: {
        namespaced: true,
        actions: { clearConversationAttributes: () => {} },
      },
    },
  });
  const dispatch = vi
    .spyOn(store, 'dispatch')
    .mockImplementation(type =>
      type === 'conversation/createConversation'
        ? Promise.reject(new Error('API failed'))
        : Promise.resolve()
    );
  const wrapper = shallowMount(PreChatForm, {
    global: {
      plugins: [store],
      mocks: {
        $t: key => key,
      },
    },
  });
  const alert = vi.fn();
  emitter.on(BUS_EVENTS.SHOW_ALERT, alert);

  wrapper.vm.onSubmit({
    fullName: 'Visitor',
    emailAddress: 'visitor@example.com',
    message: 'Hello',
    contactCustomAttributes: {},
    conversationCustomAttributes: {},
  });
  await flushPromises();

  expect(dispatch).toHaveBeenCalledWith(
    'conversation/createConversation',
    expect.any(Object)
  );
  expect(alert).toHaveBeenCalledWith({ message: 'PRE_CHAT_FORM.CREATE_ERROR' });
  emitter.off(BUS_EVENTS.SHOW_ALERT, alert);
  wrapper.unmount();
});
