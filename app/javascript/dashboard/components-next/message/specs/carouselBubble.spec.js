import { mount, shallowMount } from '@vue/test-utils';
import { ref, computed } from 'vue';
import { createStore } from 'vuex';

import MessageList from '../MessageList.vue';
import Message from '../Message.vue';
import CarouselBubble from '../bubbles/Carousel.vue';
import { provideMessageContext } from '../provider.js';
import { MESSAGE_VARIANTS, ORIENTATION } from '../constants';

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ getters: {}, dispatch: vi.fn() }),
  useMapGetter: () => computed(() => []),
}));
vi.mock('dashboard/composables', () => ({ useTrack: () => vi.fn() }));
vi.mock('vue-router', () => ({
  useRoute: () => ({
    name: 'inbox_conversation',
    params: { messageId: null, conversationId: 55, accountId: 1 },
    query: {},
  }),
}));

// NOTA: este arquivo NÃO mocka `useTransformKeys`. A camelização precisa ser a de verdade —
// é justamente ela que o stopPath do MessageList tem de conter.

const card = (index, { botoes = 'quick_reply' } = {}) => ({
  card_index: index,
  type: 'cta_url',
  header: {
    type: 'image',
    image: { link: `https://cdn.vistahost.com.br/toz19328/foto-${index}.jpg` },
  },
  body: { text: `Foto ${index + 1} de 3 — imóvel 9769` },
  action:
    botoes === 'cta_url'
      ? {
          name: 'cta_url',
          parameters: {
            display_text: 'Ver detalhes',
            url: 'https://site/imovel/9769',
          },
        }
      : {
          buttons: [
            {
              type: 'quick_reply',
              quick_reply: { id: 'interesse-9769', title: 'Tenho interesse' },
            },
            {
              type: 'quick_reply',
              quick_reply: { id: 'visita-9769', title: 'Agendar visita' },
            },
          ],
        },
});

const payload = (cards = [card(0), card(1), card(2)]) => ({
  type: 'carousel',
  body: { text: 'Fotos do imóvel 9769 — desliza pro lado pra ver todas' },
  action: { cards },
});

// ---------------------------------------------------------------------------
// 1. O caminho real: MessageList -> props da bolha
// ---------------------------------------------------------------------------
const MessageStub = {
  name: 'Message',
  props: { contentAttributes: { type: Object, default: () => ({}) } },
  template: '<div class="message-stub" />',
};

const buildStore = () =>
  createStore({
    getters: {
      getSelectedChat: () => ({ id: 55, inbox_id: 3 }),
      getCurrentUser: () => ({ id: 1, accounts: [{ id: 100, role: 'agent' }] }),
      getCurrentAccount: () => ({ id: 100 }),
      getConversationById: () => () => ({ id: 55, inbox_id: 3 }),
    },
    modules: {
      inboxes: {
        namespaced: true,
        getters: { getInbox: () => () => ({ agent_message_isolation: false }) },
      },
      teams: { namespaced: true, getters: { getSupervisedTeams: () => [] } },
    },
  });

describe('interactive_payload através do MessageList', () => {
  const montarLista = () =>
    shallowMount(MessageList, {
      props: {
        currentUserId: 1,
        messages: [
          {
            id: 7,
            created_at: 1750000000,
            message_type: 1,
            status: 'sent',
            private: false,
            sender_id: 1,
            attachments: [],
            content: '📷 Carrossel: 3 fotos do imóvel 9769',
            content_attributes: { interactive_payload: payload() },
          },
        ],
      },
      global: {
        plugins: [buildStore()],
        stubs: { Message: MessageStub, DateSeparator: true },
      },
    });

  it('mantém as chaves do payload da Meta CRUAS (stopPath)', () => {
    const recebido = montarLista()
      .findComponent(MessageStub)
      .props().contentAttributes;
    const primeiro = recebido.interactivePayload.action.cards[0];

    // o miolo é contrato da Meta: nada de cardIndex/quickReply
    expect(primeiro).toHaveProperty('card_index', 0);
    expect(primeiro).not.toHaveProperty('cardIndex');
    expect(primeiro.action.buttons[0]).toHaveProperty('quick_reply');
    expect(primeiro.action.buttons[0]).not.toHaveProperty('quickReply');
    expect(primeiro.header.image.link).toContain('cdn.vistahost.com.br');
  });

  it('ainda camelizza a CHAVE do topo — stopPath protege o conteúdo, não o nome', () => {
    const recebido = montarLista()
      .findComponent(MessageStub)
      .props().contentAttributes;

    expect(recebido).toHaveProperty('interactivePayload');
    expect(recebido).not.toHaveProperty('interactive_payload');
  });
});

// ---------------------------------------------------------------------------
// 2. A bolha
// ---------------------------------------------------------------------------
const montarBolha = (interactivePayload, { id = 7 } = {}) => {
  const Host = {
    components: { CarouselBubble },
    setup() {
      provideMessageContext({
        id: ref(id),
        variant: ref(MESSAGE_VARIANTS.BOT),
        orientation: ref(ORIENTATION.RIGHT),
        inReplyTo: ref(null),
        shouldGroupWithNext: ref(false),
        groupAuthor: ref(null),
        groupWithPrevious: ref(false),
        status: ref('read'),
        isPrivate: ref(false),
        createdAt: ref(1750000000),
        sourceId: ref(''),
        messageType: ref(1),
        contentAttributes: ref({ interactivePayload }),
        starred: ref(false),
        conversationId: ref(55),
      });
      return {};
    },
    template: '<CarouselBubble />',
  };

  return mount(Host, {
    global: { stubs: { MessageMeta: true, GalleryView: true } },
  });
};

describe('bolha do carrossel', () => {
  it('desenha um card por foto, com legenda e botões', () => {
    const wrapper = montarBolha(payload());

    expect(wrapper.findAll('li')).toHaveLength(3);
    expect(wrapper.findAll('img')).toHaveLength(3);
    expect(wrapper.text()).toContain('Foto 1 de 3 — imóvel 9769');
    expect(wrapper.text()).toContain('Tenho interesse');
    expect(wrapper.text()).toContain('Agendar visita');
  });

  it('mostra o texto que a Meta desenha acima dos cards', () => {
    const wrapper = montarBolha(payload());
    expect(wrapper.text()).toContain(
      'Fotos do imóvel 9769 — desliza pro lado pra ver todas'
    );
  });

  it('aponta o src para o CDN, sem baixar nem anexar nada', () => {
    const wrapper = montarBolha(payload());
    const fontes = wrapper.findAll('img').map(img => img.attributes('src'));

    expect(fontes).toEqual([
      'https://cdn.vistahost.com.br/toz19328/foto-0.jpg',
      'https://cdn.vistahost.com.br/toz19328/foto-1.jpg',
      'https://cdn.vistahost.com.br/toz19328/foto-2.jpg',
    ]);
  });

  it('respeita card_index quando o array vem fora de ordem', () => {
    const wrapper = montarBolha(payload([card(2), card(0), card(1)]));
    const legendas = wrapper.findAll('p').map(p => p.text());

    expect(legendas).toContain('Foto 1 de 3 — imóvel 9769');
    expect(legendas.indexOf('Foto 1 de 3 — imóvel 9769')).toBeLessThan(
      legendas.indexOf('Foto 3 de 3 — imóvel 9769')
    );
  });

  it('desenha o botão do modo ver_detalhes (cta_url)', () => {
    const wrapper = montarBolha(payload([card(0, { botoes: 'cta_url' })]));

    expect(wrapper.text()).toContain('Ver detalhes');
    expect(wrapper.text()).not.toContain('Tenho interesse');
  });

  it('não deixa o atendente disparar o botão do cliente', () => {
    const wrapper = montarBolha(payload());

    // o rótulo é retrato: nada de <button> clicável para os botões do card
    const clicaveis = wrapper.findAll('button');
    clicaveis.forEach(botao => {
      expect(botao.text()).not.toContain('Tenho interesse');
      expect(botao.text()).not.toContain('Agendar visita');
    });
  });

  it('troca a foto que falhou por um aviso, sem derrubar o resto', async () => {
    const wrapper = montarBolha(payload());
    await wrapper.findAll('img')[1].trigger('error');

    expect(wrapper.findAll('img')).toHaveLength(2);
    expect(wrapper.text()).toContain('Photo unavailable');
    expect(wrapper.findAll('li')).toHaveLength(3);
  });

  it('não estoura com payload incompleto', () => {
    expect(() => montarBolha({ type: 'carousel' })).not.toThrow();
    expect(() => montarBolha({})).not.toThrow();
  });
});

// ---------------------------------------------------------------------------
// 3. O roteador de bolha
// ---------------------------------------------------------------------------
describe('escolha da bolha no Message.vue', () => {
  const montarMensagem = contentAttributes =>
    shallowMount(Message, {
      props: {
        id: 7,
        messageType: 1,
        status: 'read',
        conversationId: 55,
        createdAt: 1750000000,
        currentUserId: 1,
        content: '📷 Carrossel: 3 fotos do imóvel 9769',
        attachments: [],
        contentAttributes,
      },
      global: { stubs: { ContextMenu: true, Avatar: true, Icon: true } },
    });

  it('usa a bolha de carrossel quando o payload traz cards', () => {
    const wrapper = montarMensagem({ interactivePayload: payload() });
    expect(wrapper.findComponent(CarouselBubble).exists()).toBe(true);
  });

  it('não sequestra os outros tipos interativos — cta_url segue no texto', () => {
    const wrapper = montarMensagem({
      interactivePayload: {
        type: 'cta_url',
        body: { text: 'Veja o imóvel' },
        action: { name: 'cta_url', parameters: { url: 'https://site' } },
      },
    });
    expect(wrapper.findComponent(CarouselBubble).exists()).toBe(false);
  });

  it('cai no texto de hoje quando o carrossel vem sem card', () => {
    const wrapper = montarMensagem({
      interactivePayload: { type: 'carousel', action: { cards: [] } },
    });
    expect(wrapper.findComponent(CarouselBubble).exists()).toBe(false);
  });

  it('não muda nada em mensagem comum, sem payload', () => {
    const wrapper = montarMensagem({});
    expect(wrapper.findComponent(CarouselBubble).exists()).toBe(false);
  });
});
