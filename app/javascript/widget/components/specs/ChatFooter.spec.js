import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import ChatFooter from '../ChatFooter.vue';

/**
 * Bloco 4.08 — O PONTO DE MONTAGEM da saída para o WhatsApp.
 *
 * O componente `WhatsAppExit` já estava correto no que fazia, e ainda assim o
 * botão era inalcançável: o único lugar que o montava era o ramo `v-else` deste
 * arquivo, que só existe com a conversa RESOLVIDA **e** com
 * `allow_messages_after_resolved` desligado — e o default dessa coluna é `true`.
 * Ou seja: na conversa comum, que é onde o plano pede a saída ("CTA de saída no
 * rodapé e no fim do fluxo", 22-plano §B.4), ela nunca aparecia.
 *
 * Por isso o teste é do RODAPÉ e não do componente: o spec do `WhatsAppExit`
 * monta o componente direto e passa mesmo quando ninguém o monta em lugar
 * nenhum. É a forma da asserção que passa porque o sujeito nunca existiu.
 *
 * O `WhatsAppExit` NÃO é dublado aqui de propósito: quem decide se a saída
 * aparece é ele, lendo `window.chatwootWebChannel`. Com ele stubado, este teste
 * afirmaria que existe uma tag no template — e não que o visitante vê um botão.
 */
const flushRouter = { replace: vi.fn(), push: vi.fn() };

vi.mock('vue-router', () => ({
  useRouter: () => flushRouter,
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: chave => chave }),
}));

const traducoes = {
  'WHATSAPP_EXIT.BUTTON': 'Continuar no WhatsApp',
  'WHATSAPP_EXIT.CONTEXT_PREFIX': 'Olá! Vim pelo chat do site {site}.',
  'WHATSAPP_EXIT.CONTEXT_SUBJECT': 'Eu perguntei: {subject}',
  START_NEW_CONVERSATION: 'Iniciar nova conversa',
  'EMAIL_TRANSCRIPT.BUTTON_TEXT': 'Receber transcrição',
};

const build = ({
  status = 'open',
  allowMessagesAfterResolved = true,
  primaryExit = 'whatsapp',
  whatsAppExitNumber = '5565999998888',
  messages = { 1: { id: 1, message_type: 0, content: 'Quanto custa o Pro?' } },
} = {}) => {
  window.chatwootWebChannel = {
    allowMessagesAfterResolved,
    whatsAppExitNumber,
    websiteName: 'Loja da Simplex',
    enabledFeatures: [],
    profileConfig: { primaryExit },
  };

  const store = createStore({
    modules: {
      conversation: {
        namespaced: true,
        getters: {
          getMessages: () => messages,
          getConversationSize: () => Object.keys(messages).length,
        },
      },
      conversationAttributes: {
        namespaced: true,
        getters: { getConversationParams: () => ({ status }) },
      },
      contacts: {
        namespaced: true,
        getters: { getCurrentUser: () => ({ has_email: false }) },
      },
      appConfig: {
        namespaced: true,
        getters: { isWidgetStyleFlat: () => false },
      },
    },
  });

  return mount(ChatFooter, {
    global: {
      plugins: [store],
      // Só o que é pesado e alheio ao ponto: o composer e a citação. A saída
      // para o WhatsApp renderiza de verdade.
      stubs: {
        ChatInputWrap: { template: '<div data-testid="composer" />' },
        FooterReplyTo: true,
      },
      mocks: {
        $t: (chave, valores) =>
          (traducoes[chave] ?? chave).replace(
            /\{(\w+)\}/g,
            (_, nome) => valores?.[nome] ?? ''
          ),
      },
    },
  });
};

describe('o rodapé da conversa', () => {
  it('monta a saída para o WhatsApp na CONVERSA COMUM, com a caixa de resposta aberta', () => {
    const wrapper = build();

    // A âncora do teste: o composer está lá, ou seja este é o ramo normal e não
    // o `v-else` da conversa resolvida. Sem esta linha, um `hideReplyBox` que
    // virasse `true` por acidente faria o teste passar medindo o outro ramo.
    expect(wrapper.find('[data-testid="composer"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="whatsapp-exit"]').exists()).toBe(true);
  });

  it('o link montado no rodapé leva o contexto da conversa', () => {
    const href = build()
      .find('[data-testid="whatsapp-exit"]')
      .attributes('href');

    expect(href).toContain('https://wa.me/5565999998888');
    expect(decodeURIComponent(href)).toContain('Loja da Simplex');
    expect(decodeURIComponent(href)).toContain('Quanto custa o Pro?');
  });

  it("no perfil de suporte (`primaryExit: 'none'`) o rodapé comum não oferece saída", () => {
    const wrapper = build({ primaryExit: 'none' });

    expect(wrapper.find('[data-testid="composer"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="whatsapp-exit"]').exists()).toBe(false);
  });

  it('sem número publicado pelo servidor, o rodapé comum não oferece saída', () => {
    // O estado de TODA inbox que ainda não configurou o número: o servidor
    // publica string vazia, e um `wa.me/` sem destino é pior que botão nenhum.
    const wrapper = build({ whatsAppExitNumber: '' });

    expect(wrapper.find('[data-testid="composer"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="whatsapp-exit"]').exists()).toBe(false);
  });

  it('continua montando a saída no fim do fluxo — conversa resolvida e sem caixa', () => {
    const wrapper = build({
      status: 'resolved',
      allowMessagesAfterResolved: false,
    });

    expect(wrapper.find('[data-testid="composer"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="whatsapp-exit"]').exists()).toBe(true);
  });
});
