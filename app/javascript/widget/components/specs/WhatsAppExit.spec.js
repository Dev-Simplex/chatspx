import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import WhatsAppExit from '../WhatsAppExit.vue';

/**
 * Bloco 4.08 (W3.6): **o link leva o contexto; `primaryExit: 'none'` esconde.**
 *
 * O terceiro caso — perfil de captura COM saida ligada mas SEM numero — nao
 * esta no texto do aceite e e o que mais machuca: um botao que abre `wa.me/`
 * sem destino leva o visitante para uma tela de erro do WhatsApp, que e pior
 * que nao ter botao nenhum.
 */
/* O componente le a config do canal de `window.chatwootWebChannel` (pelo
   configMixin) e as mensagens do store. O Vue 3 removeu o override de
   `computed` no mount, entao o teste monta o mundo de verdade: a variavel
   global e um store Vuex pequeno. */
const build = ({
  primaryExit = 'whatsapp',
  whatsAppExitNumber = '5565999998888',
  messages = {},
  websiteName = 'Loja da Simplex',
} = {}) => {
  window.chatwootWebChannel = {
    whatsAppExitNumber,
    websiteName,
    enabledFeatures: [],
    profileConfig: { primaryExit },
  };

  const store = createStore({
    modules: {
      conversation: {
        namespaced: true,
        getters: { getMessages: () => messages },
      },
    },
  });

  return shallowMount(WhatsAppExit, {
    global: {
      plugins: [store],
      mocks: {
        $t: (chave, valores) =>
          ({
            'WHATSAPP_EXIT.BUTTON': 'Continuar no WhatsApp',
            'WHATSAPP_EXIT.CONTEXT_PREFIX': `Olá! Vim pelo chat do site ${valores?.site}.`,
            'WHATSAPP_EXIT.CONTEXT_SUBJECT': `Eu perguntei: ${valores?.subject}`,
          })[chave] ?? chave,
      },
    },
  });
};

const mensagens = {
  1: { id: 1, message_type: 1, content: 'Olá, como posso ajudar?' },
  2: { id: 2, message_type: 0, content: 'Quero saber o preço do plano Pro' },
  3: { id: 3, message_type: 0, content: 'E se eu quiser 20 usuários?' },
};

describe('a saída para o WhatsApp', () => {
  it('aparece no perfil de captura, com número configurado', () => {
    const wrapper = build();

    expect(wrapper.find('[data-testid="whatsapp-exit"]').exists()).toBe(true);
  });

  it("`primaryExit: 'none'` esconde — suporte não empurra para outro canal", () => {
    const wrapper = build({ primaryExit: 'none' });

    expect(wrapper.find('[data-testid="whatsapp-exit"]').exists()).toBe(false);
  });

  it('sem número configurado, NÃO renderiza — link vazio é pior que nada', () => {
    expect(
      build({ whatsAppExitNumber: '' })
        .find('[data-testid="whatsapp-exit"]')
        .exists()
    ).toBe(false);
    expect(
      build({ whatsAppExitNumber: null })
        .find('[data-testid="whatsapp-exit"]')
        .exists()
    ).toBe(false);
  });

  it('o link leva o CONTEXTO: o site e a primeira pergunta do visitante', () => {
    const wrapper = build({ messages: mensagens });
    const href = wrapper
      .find('[data-testid="whatsapp-exit"]')
      .attributes('href');
    const texto = decodeURIComponent(href.split('?text=')[1]);

    expect(href).toContain('https://wa.me/5565999998888');
    expect(texto).toContain('Loja da Simplex');
    expect(texto).toContain('Quero saber o preço do plano Pro');
    // e NÃO leva o que o agente disse, nem a segunda pergunta: a URL fica
    // visível na barra do WhatsApp e em qualquer proxy do caminho
    expect(texto).not.toContain('como posso ajudar');
    expect(texto).not.toContain('20 usuários');
  });

  it('conversa sem mensagem do visitante ainda leva o site', () => {
    const wrapper = build({
      messages: { 1: { id: 1, message_type: 1, content: 'Oi!' } },
    });
    const href = wrapper
      .find('[data-testid="whatsapp-exit"]')
      .attributes('href');

    expect(decodeURIComponent(href)).toContain('Loja da Simplex');
    expect(decodeURIComponent(href)).not.toContain('Eu perguntei');
  });

  it('número com máscara vira só dígitos — wa.me recusa o resto', () => {
    const wrapper = build({ whatsAppExitNumber: '+55 (65) 99999-8888' });

    expect(
      wrapper.find('[data-testid="whatsapp-exit"]').attributes('href')
    ).toContain('https://wa.me/5565999998888');
  });

  it('abre em nova aba sem dar acesso à janela do site', () => {
    const link = build().find('[data-testid="whatsapp-exit"]');

    expect(link.attributes('target')).toBe('_blank');
    expect(link.attributes('rel')).toBe('noopener noreferrer');
  });
});
