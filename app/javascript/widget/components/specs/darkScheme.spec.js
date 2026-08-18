/**
 * Mecanismo de aceite do bloco 2.10 — a `div` da conversa.
 *
 * ACEITE (§2.2): «Sem `darkMode` configurado e SO escuro, o widget abre
 * escuro».
 *
 * `ConversationWrap.vue` decidia o esquema de cor lendo `darkMode` CRU:
 *
 *     colorSchemeClass() {
 *       return `${this.darkMode === 'dark' ? 'dark-scheme' : 'light-scheme'}`;
 *     }
 *
 * Com o default virando `auto`, essa comparação passa a ser SEMPRE falsa no
 * caso mais comum — o painel inteiro escurece (o `App.vue` usa o valor
 * resolvido) e só a área das mensagens fica com `color-scheme: light`, ou seja,
 * com a barra de rolagem e o `caret` claros dentro de um chat escuro. É o mesmo
 * defeito de sempre: duas decisões sobre a mesma coisa saindo de fontes
 * diferentes.
 */
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import ptBR from 'widget/i18n/locale/pt_BR.json';
import ConversationWrap from '../ConversationWrap.vue';

const i18n = createI18n({
  legacy: true,
  locale: 'pt_BR',
  messages: { pt_BR: ptBR },
  fallbackWarn: false,
  missingWarn: false,
});

const criarStore = darkMode =>
  createStore({
    modules: {
      appConfig: {
        namespaced: true,
        getters: { darkMode: () => darkMode },
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
      conversationAttributes: {
        namespaced: true,
        getters: { getConversationParams: () => ({ status: 'open' }) },
      },
    },
  });

// Cada `montar()` instala o plugin i18n num app novo, e o vue-i18n avisa
// ("Component i18n-t has already been registered in target app"). O aviso é
// esperado e inofensivo — a instância é compartilhada de propósito, para que
// todos os casos leiam o MESMO `pt_BR.json` real. Fica registrado em vez de
// silenciado: silenciar esconderia um aviso futuro que importe.
const montar = darkMode =>
  mount(ConversationWrap, {
    global: {
      plugins: [criarStore(darkMode), i18n],
      stubs: { ChatMessage: true, DateSeparator: true, Spinner: true },
      mocks: { $t: chave => i18n.global.t(chave) },
    },
  });

const classesDaRaiz = wrapper =>
  wrapper.find('.conversation--container').classes();

describe('2.10 — esquema de cor da conversa segue o valor RESOLVIDO', () => {
  const comSistemaEscuro = escuro =>
    vi.spyOn(window, 'matchMedia').mockReturnValue({
      matches: escuro,
      media: '(prefers-color-scheme: dark)',
      addEventListener: () => {},
      removeEventListener: () => {},
    });

  afterEach(() => vi.restoreAllMocks());

  it('"auto" com sistema escuro → dark-scheme', () => {
    comSistemaEscuro(true);

    const classes = classesDaRaiz(montar('auto'));
    expect(classes).toContain('dark-scheme');
    expect(classes).not.toContain('light-scheme');
    // A segunda classe do mesmo elemento sai de `prefersDarkMode` desde antes;
    // as duas precisam concordar, ou o fundo é escuro com esquema claro.
    expect(classes).toContain('conversation-container-dark');
  });

  it('"auto" com sistema claro → light-scheme', () => {
    comSistemaEscuro(false);

    const classes = classesDaRaiz(montar('auto'));
    expect(classes).toContain('light-scheme');
    expect(classes).toContain('conversation-container-light');
  });

  it('"dark" explícito ignora o sistema claro', () => {
    comSistemaEscuro(false);

    expect(classesDaRaiz(montar('dark'))).toContain('dark-scheme');
  });

  it('"light" explícito ignora o sistema escuro', () => {
    comSistemaEscuro(true);

    expect(classesDaRaiz(montar('light'))).toContain('light-scheme');
  });

  it('as duas classes do elemento nunca se contradizem', () => {
    // A contradição é o sintoma que o usuário enxerga: fundo escuro com barra
    // de rolagem clara. Assertar as duas juntas é o que impede uma delas de ser
    // "corrigida" isoladamente no futuro.
    comSistemaEscuro(true);

    ['auto', 'dark', 'light'].forEach(modo => {
      const classes = classesDaRaiz(montar(modo));
      const esquemaEscuro = classes.includes('dark-scheme');
      const fundoEscuro = classes.includes('conversation-container-dark');
      expect(esquemaEscuro).toBe(fundoEscuro);
    });
  });
});
