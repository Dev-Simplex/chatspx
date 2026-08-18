/**
 * Mecanismo de aceite do bloco 1.06 — a11y mínima.
 *
 * ACEITE (§2.2): "1 `[role="log"]`; todo `<button>` com nome acessível **em
 * pt-BR**; `outline-color` não transparente".
 *
 * Este arquivo cobre as duas primeiras asserções, que são de MARCAÇÃO e de
 * TRADUÇÃO — jsdom basta para as duas, e o i18n aqui é o real: as mensagens vêm
 * de `pt_BR.json`, não de um dublê. Se alguém acrescentar um botão só-ícone sem
 * nome, ou deixar uma string em inglês, o teste vermelhece.
 *
 * A terceira asserção (`outline-color`) é de CASCADE e mora em
 * `specs/browser/focus-ring.check.mjs`: exige CSS compilado e
 * `getComputedStyle` de um Chromium real.
 */
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import ptBR from 'widget/i18n/locale/pt_BR.json';
import HeaderActions from '../HeaderActions.vue';
import ConversationWrap from '../ConversationWrap.vue';

const i18n = createI18n({
  legacy: true,
  locale: 'pt_BR',
  messages: { pt_BR: ptBR },
  // Silencia o aviso de fallback: aqui só existe pt_BR de propósito, porque o
  // que este teste verifica é justamente que a string usada é a de pt-BR.
  fallbackWarn: false,
  missingWarn: false,
});

global.chatwootWebChannel = {
  // `end_conversation` habilitado de propósito: é o que faz o TERCEIRO botão
  // só-ícone do cabeçalho renderizar. Sem ele o teste mediria dois botões e
  // passaria sem nunca olhar o terceiro.
  enabledFeatures: ['end_conversation'],
  allowMessagesAfterResolved: true,
};

const makeStore = ({ status = 'open' } = {}) =>
  createStore({
    modules: {
      conversationAttributes: {
        namespaced: true,
        getters: { getConversationParams: () => ({ status }) },
      },
      appConfig: {
        namespaced: true,
        getters: {
          getCanUserEndConversation: () => true,
          isWidgetStyleFlat: () => false,
        },
      },
      conversation: {
        namespaced: true,
        getters: {
          getEarliestMessage: () => ({}),
          getLastMessage: () => ({}),
          getAllMessagesLoaded: () => true,
          getIsFetchingList: () => false,
          getConversationSize: () => 0,
          getIsAgentTyping: () => false,
        },
      },
    },
  });

const mountWith = (component, store, props = {}) =>
  mount(component, {
    props,
    global: {
      plugins: [store, i18n],
      stubs: { FluentIcon: true, ChatMessage: true, DateSeparator: true },
      mocks: { $t: key => i18n.global.t(key) },
    },
  });

describe('1.06 — a11y mínima do widget', () => {
  describe('role="log" na região das mensagens', () => {
    it('existe EXATAMENTE um [role="log"], e ele tem nome acessível em pt-BR', () => {
      const wrapper = mountWith(ConversationWrap, makeStore(), {
        groupedMessages: [],
      });

      const logs = wrapper.findAll('[role="log"]');
      // Exatamente um: duas regiões `log` competindo fazem o leitor de tela
      // anunciar a mesma mensagem duas vezes, ou nenhuma.
      expect(logs).toHaveLength(1);
      expect(logs[0].attributes('aria-label')).toBe('Histórico da conversa');
    });

    it('não declara aria-live junto de role="log" (o papel já implica polite)', () => {
      const wrapper = mountWith(ConversationWrap, makeStore(), {
        groupedMessages: [],
      });
      expect(
        wrapper.find('[role="log"]').attributes('aria-live')
      ).toBeUndefined();
    });
  });

  describe('nome acessível dos botões do cabeçalho', () => {
    // O cabeçalho é onde vivem os três botões só-ícone do painel. Antes deste
    // bloco, dois deles (popout e fechar) não tinham nome nenhum: o leitor de
    // tela anunciava "botão".
    const montarCabecalho = () =>
      mountWith(HeaderActions, makeStore({ status: 'open' }), {
        showPopoutButton: true,
        showEndConversationButton: true,
      });

    it('todo <button> tem nome acessível não vazio', () => {
      const wrapper = montarCabecalho();
      const botoes = wrapper.findAll('button');

      // Três, não ">= 2": o cabeçalho tem encerrar, abrir-em-nova-janela e
      // fechar. Um piso deixaria o teste passar se um botão parasse de
      // renderizar — e era justamente um botão não observado que estava sem nome.
      expect(botoes).toHaveLength(3);
      botoes.forEach(botao => {
        const nome =
          botao.attributes('aria-label') || botao.attributes('title') || '';
        expect(nome.trim()).not.toBe('');
      });
    });

    it('os nomes são as strings de pt-BR, não inglês cravado', () => {
      const wrapper = montarCabecalho();
      const nomes = wrapper
        .findAll('button')
        .map(b => b.attributes('aria-label'));

      expect(nomes).toContain('Fechar o chat');
      expect(nomes).toContain('Abrir o chat em uma nova janela');
      expect(nomes).toContain(ptBR.END_CONVERSATION);
    });

    it('title e aria-label não divergem — a dica visual e a falada são a mesma', () => {
      const wrapper = montarCabecalho();
      wrapper.findAll('button').forEach(botao => {
        expect(botao.attributes('title')).toBe(botao.attributes('aria-label'));
      });
    });
  });

  describe('as chaves de a11y existem nos dois locales que o fork mantém', () => {
    // pt-BR é a prioridade do fork; `en` é o fallback do vue-i18n. Uma chave só
    // em pt-BR faria a conta em inglês cair no nome da chave — literalmente
    // "A11Y.CLOSE_WIDGET" anunciado pelo leitor de tela.
    it('pt_BR e en têm as 4 chaves de A11Y, e nenhuma está vazia', async () => {
      const en = (await import('widget/i18n/locale/en.json')).default;
      const chaves = [
        'CONVERSATION_LOG',
        'CLOSE_WIDGET',
        'OPEN_IN_NEW_WINDOW',
        'OPEN_WIDGET',
      ];

      chaves.forEach(chave => {
        expect(ptBR.A11Y?.[chave]?.trim()).toBeTruthy();
        expect(en.A11Y?.[chave]?.trim()).toBeTruthy();
        // e a tradução tem de ser diferente do inglês, senão não foi traduzida
        expect(ptBR.A11Y[chave]).not.toBe(en.A11Y[chave]);
      });
    });
  });
});
