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

const mountBubble = over =>
  mount(MessageBubble, {
    props: { message: msg(over), currentUserId: 1 },
    global: {
      // O ContextMenu teleporta via TeleportWithDirection, que lê accounts/isRTL.
      plugins: [
        createStore({
          modules: {
            accounts: { namespaced: true, getters: { isRTL: () => false } },
          },
        }),
      ],
      stubs: { Avatar: true },
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
    await wrapper.find('[title="Ações da mensagem"]').trigger('click');
    const text = document.body.textContent;
    // responder saiu da faixa e virou o 1o item do menu
    expect(text).toContain('Responder mensagem');
    expect(text).toContain('Editar mensagem');
    expect(text).toContain('Excluir');
    expect(text).toContain('Copiar');
  });

  it('sem gatilho em mensagem apagada', () => {
    expect(mountBubble({ deleted: true }).html()).not.toContain(
      'i-lucide-chevron-down'
    );
  });
});
