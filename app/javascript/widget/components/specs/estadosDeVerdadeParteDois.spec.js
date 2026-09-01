/**
 * Mecanismo do bloco 2.07 — A SEGUNDA METADE: banner legado, erro e vazio.
 *
 * `estadosDeVerdade.spec.js` cobre a metade de REDE (faixa de reconexão e
 * esqueleto), que já estava ligada. Este arquivo cobre as três entregas que o
 * diagnóstico mediu como ausentes:
 *
 *   1. `Banner.vue` — o único dos 4 arquivos do bloco que nunca foi tocado,
 *      com `text-white` literal na linha 37. É o ACEITE 4 da §C.15, textual.
 *   2. O estado de ERRO DE ENVIO: a §C.15 pede «ícone + texto + "Tentar de
 *      novo", `role="alert"`» dentro do balão. Havia só um ícone vermelho mudo,
 *      e `COMPONENTS.MESSAGE_BUBBLE.ERROR_MESSAGE` era chave declarada em 56
 *      locales com ZERO leitores.
 *   3. O estado VAZIO da conversa, que não existia.
 *
 * Como em `estadosDeVerdade.spec.js`, nada aqui é medido por "a função foi
 * chamada" nem por identidade de módulo: toda asserção é sobre a árvore
 * renderizada ou sobre o BYTE do arquivo, que é o que o aceite 4 pede.
 */
import { readFileSync } from 'node:fs';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import ptBR from 'widget/i18n/locale/pt_BR.json';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import Banner from 'widget/components/Banner.vue';
import MessageRow from 'widget/components/MessageRow.vue';
import ConversationWrap from 'widget/components/ConversationWrap.vue';

const CAMINHO_BANNER = 'app/javascript/widget/components/Banner.vue';

const i18n = createI18n({
  legacy: true,
  locale: 'pt_BR',
  messages: { pt_BR: ptBR },
  fallbackWarn: false,
  missingWarn: false,
});

const globalDeMontagem = extras => ({
  plugins: [i18n],
  mocks: { $t: chave => i18n.global.t(chave) },
  ...extras,
});

describe('2.07 — o Banner legado, migrado para o primitivo', () => {
  const montar = () => mount(Banner, { global: globalDeMontagem() });

  /**
   * O CÓDIGO do arquivo, sem comentário — mesma régua e mesma razão de
   * `widget/ui/specs/primitivosLint.spec.js`, que é o lint do 2.01: o aceite é
   * sobre a cor que o Tailwind COMPILA, e um scanner que lê comentário reprova
   * quem explica por que a cor saiu. Aqui isso importaria de verdade, porque o
   * cabeçalho deste componente cita as três dívidas pelo nome.
   */
  const codigoDoBanner = () => {
    const bruto = readFileSync(CAMINHO_BANNER, 'utf8');
    const codigo = bruto
      .replace(/<!--[\s\S]*?-->/g, '')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/^\s*\/\/.*$/gm, '');
    // Guarda anti-vácuo: um regex de remoção que come o arquivo inteiro faria
    // as duas asserções abaixo passarem sem medir nada. Se o `<style>` sumiu,
    // não há o que afirmar sobre a cor dele.
    expect(codigo).toMatch(/<style/);
    expect(codigo).toMatch(/w-alert-banner/);
    return codigo;
  };

  it('o Banner delega ao primitivo em vez de desenhar a própria faixa', () => {
    // A migração é o título do bloco. Sem esta asserção, apagar a folha de
    // estilo antiga e não pôr nada no lugar passaria nas duas de baixo.
    expect(readFileSync(CAMINHO_BANNER, 'utf8')).toMatch(
      /import WBanner from 'widget\/ui\/WBanner\.vue'/
    );
  });

  it('aceite 4 da §C.15: o arquivo não USA `text-white` literal', () => {
    expect(codigoDoBanner()).not.toMatch(/text-white/);
  });

  it('não sobrou nenhuma cor de tema escrita à mão no arquivo', () => {
    // A régua dos primitivos (2.01) vale para quem os consome: `bg-n-ruby-9` e
    // `bg-n-teal-9` cravados aqui eram a mesma dívida que `text-white`, só que
    // com outro nome.
    expect(codigoDoBanner()).not.toMatch(/bg-n-(ruby|teal)-9/);
  });

  it('erro interrompe o leitor de tela: `role="alert"`', async () => {
    const w = montar();
    emitter.emit(BUS_EVENTS.SHOW_ALERT, { message: 'Falhou', type: 'error' });
    await w.vm.$nextTick();

    const faixa = w.find('.w-banner');
    expect(faixa.exists()).toBe(true);
    expect(faixa.text()).toBe('Falhou');
    expect(faixa.attributes('role')).toBe('alert');
  });

  it('sucesso NÃO interrompe: `role="status"`', async () => {
    // Forçando a condição contrária, que é onde `role="alert"` cravado passaria
    // despercebido: "arquivo enviado" não pode cortar a fala do leitor.
    const w = montar();
    emitter.emit(BUS_EVENTS.SHOW_ALERT, { message: 'Pronto', type: 'success' });
    await w.vm.$nextTick();

    const faixa = w.find('.w-banner');
    expect(faixa.exists()).toBe(true);
    expect(faixa.attributes('role')).toBe('status');
  });

  it('sem alerta nenhum, a faixa não existe no DOM', () => {
    expect(montar().find('.w-banner').exists()).toBe(false);
  });

  it('a faixa EMPURRA o conteúdo, nunca cobre o composer', () => {
    // ── O aceite que reprova sem parecer ──────────────────────────────────────
    //
    // O bloco pede «composer utilizável» com a rede caída, e a forma mais fácil
    // de reprovar nisso é ancorar a faixa por cima do rodapé: ela aparece, o
    // teste de "a faixa existe" fica verde, e o campo de texto fica embaixo de
    // um retângulo. Como a migração fez `Banner.vue` passar a renderizar
    // `.w-banner` — a MESMA classe da faixa de conexão —, as duas superfícies
    // precisam da mesma garantia.
    //
    // São duas metades, e nenhuma sozinha basta:
    //   · nem o primitivo nem esta casca podem se posicionar fora do fluxo;
    //   · em `ViewWithHeader.vue` a faixa vem ANTES do `<main>`, que é onde a
    //     `router-view` monta a conversa e o rodapé.
    const semPosicionamento = caminho => {
      const estilo = readFileSync(caminho, 'utf8').split('<style')[1] || '';
      expect(estilo.length).toBeGreaterThan(0);
      expect(estilo).not.toMatch(/position:\s*(absolute|fixed|sticky)/);
      expect(estilo).not.toMatch(/@apply[^;]*\b(absolute|fixed|sticky)\b/);
    };
    semPosicionamento(CAMINHO_BANNER);
    semPosicionamento('app/javascript/widget/ui/WBanner.vue');

    const layout = readFileSync(
      'app/javascript/widget/components/layouts/ViewWithHeader.vue',
      'utf8'
    );
    const posFaixa = layout.indexOf('<Banner');
    const posMain = layout.indexOf('<main');
    expect(posFaixa).toBeGreaterThan(-1);
    expect(posMain).toBeGreaterThan(-1);
    expect(posFaixa).toBeLessThan(posMain);
  });
});

describe('2.07 — o estado de erro de envio, dentro do balão', () => {
  const criarStore = () =>
    createStore({
      modules: {
        conversation: {
          namespaced: true,
          actions: { sendMessageWithData: () => {} },
        },
      },
    });

  const montarLinha = status =>
    mount(MessageRow, {
      props: { variant: 'user', message: { id: 1, content: 'oi', status } },
      global: globalDeMontagem({
        plugins: [criarStore(), i18n],
        stubs: {
          Avatar: true,
          AgentMessageBubble: true,
          UserMessageBubble: true,
          MessageReplyButton: true,
          ReplyToChip: true,
          DragWrapper: { template: '<div><slot /></div>' },
        },
        directives: { 'dompurify-html': {} },
      }),
    });

  beforeEach(() => {
    window.chatwootWebChannel = {
      enabledFeatures: [],
      avatarUrl: '',
      preChatFormOptions: {},
    };
  });

  it('a falha é ANUNCIADA: `role="alert"` com o texto visível', () => {
    const w = montarLinha('failed');
    const alerta = w.find('[role="alert"]');

    expect(alerta.exists()).toBe(true);
    // O texto tem de estar NA TELA, não só num `title` ou `aria-label`: um
    // ícone vermelho mudo é o que havia antes, e ele não diz o que houve para
    // quem enxerga.
    expect(alerta.text()).toContain(
      ptBR.COMPONENTS.MESSAGE_BUBBLE.ERROR_MESSAGE
    );
  });

  it('a chave ERROR_MESSAGE finalmente tem um leitor', () => {
    // A chave existe nos 56 locales desde sempre e nenhum componente a lia.
    // Isto é a asserção de que ela saiu do papel — pelo texto, não pelo grep.
    const w = montarLinha('failed');
    expect(w.text()).toContain(ptBR.COMPONENTS.MESSAGE_BUBBLE.ERROR_MESSAGE);
  });

  it('«Tentar de novo» é botão com texto, e reenvia de verdade', async () => {
    const store = criarStore();
    const espia = vi.spyOn(store, 'dispatch');
    const w = mount(MessageRow, {
      props: {
        variant: 'user',
        message: { id: 1, content: 'oi', status: 'failed' },
      },
      global: globalDeMontagem({
        plugins: [store, i18n],
        stubs: {
          Avatar: true,
          AgentMessageBubble: true,
          UserMessageBubble: true,
          MessageReplyButton: true,
          ReplyToChip: true,
          DragWrapper: { template: '<div><slot /></div>' },
        },
        directives: { 'dompurify-html': {} },
      }),
    });

    const botao = w.find('button.message-erro__acao');
    expect(botao.exists()).toBe(true);
    expect(botao.text()).toContain(ptBR.COMPONENTS.MESSAGE_BUBBLE.RETRY);

    await botao.trigger('click');
    expect(espia).toHaveBeenCalledWith('conversation/sendMessageWithData', {
      message: { id: 1, content: 'oi', status: 'failed' },
    });
  });

  it('mensagem entregue não anuncia erro nenhum', () => {
    // A condição ruim forçada ao contrário: `role="alert"` que aparece sempre
    // faria o leitor de tela gritar a cada mensagem enviada com sucesso.
    const w = montarLinha('sent');
    expect(w.find('[role="alert"]').exists()).toBe(false);
    expect(w.text()).not.toContain(
      ptBR.COMPONENTS.MESSAGE_BUBBLE.ERROR_MESSAGE
    );
  });

  it('mensagem em voo também não anuncia erro', () => {
    const w = montarLinha('in_progress');
    expect(w.find('[role="alert"]').exists()).toBe(false);
  });
});

describe('2.07 — o estado vazio da conversa', () => {
  const criarStore = ({ buscando = false, tamanho = 0 } = {}) =>
    createStore({
      modules: {
        appConfig: { namespaced: true, getters: { darkMode: () => 'light' } },
        conversation: {
          namespaced: true,
          getters: {
            getEarliestMessage: () => ({}),
            getLastMessage: () => ({}),
            getAllMessagesLoaded: () => true,
            getIsFetchingList: () => buscando,
            getConversationSize: () => tamanho,
            getIsAgentTyping: () => false,
          },
          actions: { fetchOldConversations: () => {} },
        },
        conversationAttributes: {
          namespaced: true,
          getters: { getConversationParams: () => ({ status: 'open' }) },
        },
      },
    });

  const montar = (opcoes, groupedMessages = []) =>
    mount(ConversationWrap, {
      props: { groupedMessages },
      global: globalDeMontagem({
        plugins: [criarStore(opcoes), i18n],
        stubs: { ChatMessage: true, WDateSeparator: true },
      }),
    });

  it('conversa sem mensagem nenhuma mostra o estado vazio, com texto', () => {
    const w = montar();
    const vazio = w.find('.w-empty-state');

    expect(vazio.exists()).toBe(true);
    expect(vazio.text()).toContain(ptBR.EMPTY_STATE.CONVERSATION.TITLE);
    expect(vazio.text()).toContain(ptBR.EMPTY_STATE.CONVERSATION.BODY);
  });

  it('com mensagem na lista o estado vazio some', () => {
    const w = montar({ tamanho: 1 }, [
      { date: 'hoje', messages: [{ id: 1, content: 'oi' }] },
    ]);
    expect(w.find('.w-empty-state').exists()).toBe(false);
  });

  it('enquanto BUSCA, o esqueleto manda e o vazio não aparece', () => {
    // Sem esta guarda o visitante veria "nenhuma mensagem ainda" piscando no
    // meio do carregamento — que é uma afirmação falsa sobre a conversa dele.
    const w = montar({ buscando: true });
    expect(w.find('.w-empty-state').exists()).toBe(false);
  });

  it('o estado vazio não é lido como conteúdo da conversa duas vezes', () => {
    // Ele mora DENTRO do `role="log"`, então o ícone decorativo tem de estar
    // escondido do leitor de tela; o texto é que fala.
    const w = montar();
    const icone = w.find('.w-empty-state__icone');
    expect(icone.exists()).toBe(true);
    expect(icone.attributes('aria-hidden')).toBe('true');
  });

  it('o modificador `is-empty` entra vazio e SAI com mensagem', () => {
    // A regra de centralizar vive num modificador porque, aplicada ao seletor
    // base, ela mudaria o encaixe das bolhas em toda conversa do produto — que
    // é o que os 20 snapshots de pixel do widget medem. Esta é a asserção de
    // que ela não vazou para o caminho comum.
    expect(montar().find('.conversation-wrap').classes()).toContain('is-empty');
    const comMensagem = montar({ tamanho: 1 }, [
      { date: 'hoje', messages: [{ id: 1, content: 'oi' }] },
    ]);
    expect(comMensagem.find('.conversation-wrap').classes()).not.toContain(
      'is-empty'
    );
  });
});
