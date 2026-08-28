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
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import ptBR from 'widget/i18n/locale/pt_BR.json';
import HeaderActions from '../HeaderActions.vue';
import ConversationWrap from '../ConversationWrap.vue';
import ChatAttachment from '../ChatAttachment.vue';
import FooterReplyTo from '../FooterReplyTo.vue';
import MessageReplyButton from '../MessageReplyButton.vue';
import EmailInput from '../template/EmailInput.vue';

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
          // `ChatAttachment` lê estes dois por `useAttachments`. Ficam com o
          // valor que FAZ o botão de anexo renderizar — um getter que o
          // escondesse deixaria a asserção medindo um botão que não existe.
          getShouldShowFilePicker: () => true,
          getShouldShowEmojiPicker: () => true,
        },
      },
      globalConfig: {
        namespaced: true,
        getters: { get: () => ({ maximumFileUploadSize: 40 }) },
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
    it('pt_BR e en têm TODAS as chaves de A11Y, e nenhuma está vazia', async () => {
      const en = (await import('widget/i18n/locale/en.json')).default;
      // Derivada do arquivo, não escrita à mão: uma lista fixa cobre as chaves
      // que existiam no dia em que foi escrita e ignora em silêncio toda chave
      // nova — que é justamente o caso deste bloco, que acrescentou quatro.
      const chaves = Object.keys(ptBR.A11Y ?? {});
      expect(chaves.length).toBeGreaterThanOrEqual(14);

      chaves.forEach(chave => {
        expect(ptBR.A11Y?.[chave]?.trim()).toBeTruthy();
        expect(en.A11Y?.[chave]?.trim()).toBeTruthy();
        // e a tradução tem de ser diferente do inglês, senão não foi traduzida
        expect(ptBR.A11Y[chave]).not.toBe(en.A11Y[chave]);
      });
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // O ACEITE diz "TODO `<button>`", e até aqui o arquivo media três — os do
  // cabeçalho. Três botões observados não são "todos": os que estavam sem nome
  // eram justamente os que ninguém montava. Esta varredura fecha a diferença
  // entre o que o aceite pede e o que o teste olha.
  // ───────────────────────────────────────────────────────────────────────────
  describe('todo <button> do widget tem nome acessível', () => {
    const RAIZ = 'app/javascript/widget';

    const vuesDoWidget = (dir = RAIZ, achados = []) => {
      readdirSync(dir).forEach(entrada => {
        const caminho = join(dir, entrada);
        if (statSync(caminho).isDirectory()) {
          // `specs/` fica de fora: fixture de teste não vai ao ar.
          if (entrada !== 'specs') vuesDoWidget(caminho, achados);
        } else if (entrada.endsWith('.vue')) {
          achados.push(caminho);
        }
      });
      return achados;
    };

    // Um `<button>` tem nome ou por atributo que nomeia, ou por conteúdo que
    // vira texto. As duas fontes de conteúdo são distintas e as duas são
    // reais — a segunda já me deu um falso positivo ao escrever isto:
    // `UnreadMessage.vue` enche a bolha com `v-dompurify-html`, que não deixa
    // texto literal no template mas RENDERIZA texto. Um verificador que
    // acusasse esse botão viraria ruído, e ruído é o que faz um verificador
    // ser desligado.
    const NOMEIA_POR_ATRIBUTO =
      /(^|[\s:@])(aria-label|aria-labelledby|title)\s*=/;
    const NOMEIA_POR_DIRETIVA = /v-(dompurify-)?html\s*=/;

    const botoesDe = arquivo => {
      const fonte = readFileSync(arquivo, 'utf8');
      const template = /<template>([\s\S]*)<\/template>/.exec(fonte)?.[1];
      if (!template) return [];

      const linhaDoTemplate = fonte
        .slice(0, fonte.indexOf('<template>'))
        .split('\n').length;

      const achados = [];
      let i = template.indexOf('<button');
      while (i !== -1) {
        const fimDaAbertura = template.indexOf('>', i);
        const atributos = template.slice(i + '<button'.length, fimDaAbertura);
        const fechamento = template.indexOf('</button>', fimDaAbertura);
        const conteudo =
          fechamento === -1
            ? ''
            : template.slice(fimDaAbertura + 1, fechamento);

        achados.push({
          onde: `${arquivo}:${
            linhaDoTemplate + template.slice(0, i).split('\n').length - 1
          }`,
          temNome:
            NOMEIA_POR_ATRIBUTO.test(atributos) ||
            // texto literal ou interpolação sobrando depois de tirar as tags
            conteudo.replace(/<[^>]*>/g, '').trim().length > 0 ||
            // `<slot />`: quem consome o primitivo é que dá o nome
            /<slot\b/.test(conteudo) ||
            NOMEIA_POR_DIRETIVA.test(conteudo),
        });
        i = template.indexOf('<button', fimDaAbertura);
      }
      return achados;
    };

    it('nenhum <button> fica sem nome acessível', () => {
      const arquivos = vuesDoWidget();
      const botoes = arquivos.flatMap(botoesDe);

      // Piso antes da asserção de ausência. Sem ele esta varredura ficaria
      // verde no vácuo: bastaria a raiz mudar de lugar e `readdirSync` devolver
      // zero arquivo para "nenhum botão sem nome" passar sem ter olhado nada.
      expect(arquivos.length).toBeGreaterThanOrEqual(60);
      expect(botoes.length).toBeGreaterThanOrEqual(20);

      expect(botoes.filter(b => !b.temNome).map(b => b.onde)).toEqual([]);
    });
  });

  describe('os botões só-ícone que faltavam, montados de verdade', () => {
    // A varredura acima é textual; esta parte monta os componentes e lê o nome
    // do DOM, em pt-BR. As duas medem coisas diferentes de propósito: a
    // varredura pega um botão novo que ninguém montou, a montagem pega um
    // `aria-label` que existe no arquivo mas não chega ao elemento.
    const casos = [
      ['ChatAttachment', ChatAttachment, {}, 'Anexar arquivo'],
      [
        'FooterReplyTo',
        FooterReplyTo,
        { inReplyTo: { content: 'olá' } },
        'Cancelar resposta',
      ],
      ['MessageReplyButton', MessageReplyButton, {}, 'Responder à mensagem'],
      ['EmailInput', EmailInput, { messageId: 1 }, 'Confirmar e-mail'],
    ];

    it.each(casos)(
      '%s: o botão só-ícone tem nome acessível em pt-BR',
      (_nome, componente, props, esperado) => {
        const wrapper = mountWith(componente, makeStore(), props);
        const botoes = wrapper.findAll('button');

        // Um piso outra vez: `forEach` sobre lista vazia passa calado.
        expect(botoes.length).toBeGreaterThanOrEqual(1);
        expect(botoes.map(b => b.attributes('aria-label'))).toContain(esperado);
      }
    );
  });
});
