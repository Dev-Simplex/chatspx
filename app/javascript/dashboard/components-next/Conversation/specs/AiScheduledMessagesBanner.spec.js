import { flushPromises, mount } from '@vue/test-utils';
import AiScheduledMessagesBanner from '../AiScheduledMessagesBanner.vue';
import ScheduledMessagesAPI from 'dashboard/api/scheduledMessages';

vi.mock('dashboard/api/scheduledMessages', () => ({
  default: { getAiPendingByConversation: vi.fn(), cancel: vi.fn() },
}));

const alert = vi.fn();
vi.mock('dashboard/composables', () => ({ useAlert: (...a) => alert(...a) }));

const daIa = {
  id: 7,
  message: 'Texto pronto da IA',
  scheduled_at: '2026-09-30T00:00:00Z',
  captain_assistant: { id: 3, name: 'Clara' },
};
const dePessoa = { ...daIa, id: 8, captain_assistant: null };

const montar = (props = { conversationDisplayId: 42, messagesCount: 1 }) =>
  mount(AiScheduledMessagesBanner, {
    props,
    global: {
      stubs: {
        Button: {
          props: ['label'],
          emits: ['click'],
          template: '<button @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });

describe('AiScheduledMessagesBanner', () => {
  it('mostra só a agendada da IA, com o texto e o nome do agente', async () => {
    ScheduledMessagesAPI.getAiPendingByConversation.mockResolvedValue({
      data: [daIa, dePessoa],
    });

    const wrapper = montar();
    await flushPromises();

    expect(
      ScheduledMessagesAPI.getAiPendingByConversation
    ).toHaveBeenCalledWith(42);
    const itens = wrapper.findAll('[data-testid="ai-scheduled-message"]');
    expect(itens).toHaveLength(1);
    expect(itens[0].text()).toContain('Texto pronto da IA');
    expect(itens[0].text()).toContain('Clara');
  });

  it('não renderiza nada sem agendada da IA', async () => {
    ScheduledMessagesAPI.getAiPendingByConversation.mockResolvedValue({
      data: [dePessoa],
    });

    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-testid="ai-scheduled-message"]').exists()).toBe(
      false
    );
  });

  it('cancela e recarrega a lista', async () => {
    ScheduledMessagesAPI.getAiPendingByConversation
      .mockResolvedValueOnce({ data: [daIa] })
      .mockResolvedValueOnce({ data: [] });
    ScheduledMessagesAPI.cancel.mockResolvedValue({});

    const wrapper = montar();
    await flushPromises();
    await wrapper.find('button').trigger('click');
    await flushPromises();

    expect(ScheduledMessagesAPI.cancel).toHaveBeenCalledWith(7);
    expect(wrapper.find('[data-testid="ai-scheduled-message"]').exists()).toBe(
      false
    );
  });

  it('recarrega quando chega mensagem nova', async () => {
    ScheduledMessagesAPI.getAiPendingByConversation.mockResolvedValue({
      data: [],
    });

    const wrapper = montar();
    await flushPromises();
    await wrapper.setProps({ messagesCount: 2 });
    await flushPromises();

    expect(
      ScheduledMessagesAPI.getAiPendingByConversation
    ).toHaveBeenCalledTimes(2);
  });
});
