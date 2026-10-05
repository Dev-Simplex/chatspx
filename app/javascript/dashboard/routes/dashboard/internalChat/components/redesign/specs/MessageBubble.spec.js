import { createStore } from 'vuex';
import { mount } from '@vue/test-utils';
import MessageBubble from '../MessageBubble.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const msg = (over = {}) => ({
  id: 1,
  content: 'oi',
  mine: true,
  deleted: false,
  attachments: [],
  reactions: {},
  time: '11:29',
  ...over,
});

const mountBubble = (over, extraProps = {}) =>
  mount(MessageBubble, {
    props: { message: msg(over), currentUserId: 1, ...extraProps },
    global: {
      // O ContextMenu teleporta via TeleportWithDirection, que lê accounts/isRTL.
      plugins: [
        createStore({
          modules: {
            accounts: { namespaced: true, getters: { isRTL: () => false } },
          },
          getters: { getCurrentAccountId: () => 7 },
        }),
      ],
      stubs: {
        Avatar: true,
        RouterLink: {
          props: ['to'],
          template: '<a :data-to="to"><slot /></a>',
        },
      },
    },
  });

describe('MessageBubble do chat interno', () => {
  it('mostra o gatilho ⌄ no lugar do antigo ⋯', () => {
    const html = mountBubble().html();
    expect(html).toContain('i-lucide-chevron-down');
    expect(html).not.toContain('i-lucide-ellipsis');
  });

  it('abre o menu com rótulos ao clicar no chevron', async () => {
    const wrapper = mountBubble();
    await wrapper.find('[aria-label="Message actions"]').trigger('click');
    const text = document.body.textContent;
    // responder saiu da faixa e virou o 1o item do menu
    expect(text).toContain('Reply to message');
    expect(text).toContain('Edit message');
    expect(text).toContain('Delete');
    expect(text).toContain('Copy');
  });

  it('sem gatilho em mensagem apagada', () => {
    expect(mountBubble({ deleted: true }).html()).not.toContain(
      'i-lucide-chevron-down'
    );
  });

  it('link, #123 e @menção viram clicáveis/destacados', () => {
    const wrapper = mountBubble(
      { content: 'veja #42 em https://x.com/a com @Ana Paula' },
      { mentionNames: ['Ana Paula'] }
    );
    expect(wrapper.find('a[href="https://x.com/a"]').exists()).toBe(true);
    expect(
      wrapper.find('[data-to="/app/accounts/7/conversations/42"]').text()
    ).toBe('#42');
    expect(wrapper.find('span.font-semibold.rounded').text()).toBe(
      '@Ana Paula'
    );
  });

  it('conversa compartilhada vira card com link', () => {
    const wrapper = mountBubble({
      sharedConversation: {
        display_id: 123,
        contact_name: 'Maria',
        inbox_name: 'WhatsApp',
      },
    });
    const card = wrapper.find('[data-to="/app/accounts/7/conversations/123"]');
    expect(card.text()).toContain('#123 – Maria');
    expect(card.text()).toContain('WhatsApp');
  });

  it('✓✓ só quando lida; ✓ quando só enviada', () => {
    expect(mountBubble({ delivery: 'read' }).html()).toContain(
      'i-lucide-check-check'
    );
    const sent = mountBubble({ delivery: 'sent' }).html();
    expect(sent).toContain('i-lucide-check');
    expect(sent).not.toContain('i-lucide-check-check');
  });
});
