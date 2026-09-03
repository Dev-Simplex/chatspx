/**
 * Mecanismo de aceite do bloco 2.07 — os ESTADOS DE VERDADE do widget.
 *
 * ACEITE (§2.2): «Rede cortada 10 s: nada nos primeiros 3 s, faixa depois,
 * composer utilizável; micro-queda de 1,5 s não mostra nada» e, no corpo do
 * bloco, «skeleton só acima de 600 ms».
 *
 * ── A ARMADILHA QUE ESTE ARQUIVO EXISTE PARA NÃO CAIR ────────────────────────
 *
 * `connectionMonitor.js` e `loadingGate.js` já tinham teste verde antes deste
 * arquivo — e NINGUÉM os lia. Um teste de "a função foi chamada", "o módulo
 * exporta" ou "o componente importa" passa exatamente igual com o consumidor
 * desligado: foi assim que os dois módulos passaram uma onda inteira mortos.
 *
 * Então aqui NADA é medido por chamada nem por identidade de módulo. Toda
 * asserção é sobre a ÁRVORE RENDERIZADA: a conexão cai de verdade, o relógio
 * anda de verdade, e o que se pergunta é se a faixa está no DOM. Se alguém
 * apagar o `<ConnectionBanner />` de `Messages.vue`, ou o
 * `<ConversationSkeleton>` de `ConversationWrap.vue`, estes testes ficam
 * vermelhos — que é a única coisa que distingue "ligado" de "existe".
 *
 * ── Por que os imports são dinâmicos ─────────────────────────────────────────
 *
 * As duas instâncias (`widget/state`) nascem na AVALIAÇÃO do módulo, e capturam
 * `setTimeout` ali. `vi.useFakeTimers()` chamado depois trocaria o global sem
 * alcançar a referência já capturada, e o relógio falso não moveria nada — um
 * teste que "passa" porque nada acontece. Instalando o relógio ANTES do
 * `import()`, as instâncias nascem já com o relógio do teste.
 */
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import ptBR from 'widget/i18n/locale/pt_BR.json';

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

// `vi.resetModules()` obriga cada teste a REAVALIAR os módulos, e reavaliar
// `Messages.vue`/`ConversationWrap.vue` é trabalho de verdade — trabalho que o
// relógio falso não acelera, porque ele é de CPU e não de tempo. Com o teto
// padrão de 5 s isto passa sozinho e reprova quando a suíte inteira roda em
// paralelo: um vermelho que não fala do código. O teto vai a 30 s por isso, e
// os imports abaixo são sob demanda para que cada teste pague só o que usa.
vi.setConfig({ testTimeout: 30000 });

let estado;

const carregarTela = async () => {
  estado.Messages = (await import('widget/views/Messages.vue')).default;
};

const carregarLista = async () => {
  estado.ConversationWrap = (
    await import('widget/components/ConversationWrap.vue')
  ).default;
};

beforeEach(async () => {
  vi.resetModules();
  vi.useFakeTimers();
  estado = {
    ...(await import('widget/state')),
    ConnectionBanner: (await import('widget/components/ConnectionBanner.vue'))
      .default,
    ConversationSkeleton: (
      await import('widget/components/ConversationSkeleton.vue')
    ).default,
  };
});

afterEach(() => {
  vi.useRealTimers();
});

describe('2.07 — a faixa de conexão', () => {
  const montarFaixa = () =>
    mount(estado.ConnectionBanner, { global: globalDeMontagem() });

  it('micro-queda de 1,5 s não mostra NADA', async () => {
    const w = montarFaixa();

    estado.widgetConnectionMonitor.reportDisconnected();
    vi.advanceTimersByTime(1500);
    estado.widgetConnectionMonitor.reportConnected();
    await w.vm.$nextTick();

    expect(w.find('.w-banner').exists()).toBe(false);
    expect(w.text()).toBe('');
  });

  it('rede cortada: nada nos primeiros 3 s, faixa depois', async () => {
    const w = montarFaixa();
    estado.widgetConnectionMonitor.reportDisconnected();

    vi.advanceTimersByTime(2999);
    await w.vm.$nextTick();
    expect(w.find('.w-banner').exists()).toBe(false);

    vi.advanceTimersByTime(2);
    await w.vm.$nextTick();
    const faixa = w.find('.w-banner');
    expect(faixa.exists()).toBe(true);
    expect(faixa.text()).toBe(ptBR.CONNECTION.RECONNECTING);
    // `status` e não `alert`: reconectando é aviso, não erro — `alert`
    // interromperia a leitura de tela no meio da conversa.
    expect(faixa.attributes('role')).toBe('status');
    expect(faixa.classes()).toContain('w-banner--warning');
  });

  it('aos 15 s a faixa vira erro, e é aí que ela interrompe o leitor de tela', async () => {
    const w = montarFaixa();
    estado.widgetConnectionMonitor.reportDisconnected();

    vi.advanceTimersByTime(14999);
    await w.vm.$nextTick();
    expect(w.find('.w-banner').classes()).toContain('w-banner--warning');

    vi.advanceTimersByTime(2);
    await w.vm.$nextTick();
    const faixa = w.find('.w-banner');
    expect(faixa.text()).toBe(ptBR.CONNECTION.OFFLINE);
    expect(faixa.classes()).toContain('w-banner--error');
    expect(faixa.attributes('role')).toBe('alert');
  });

  it('a faixa some quando a conexão volta', async () => {
    const w = montarFaixa();
    estado.widgetConnectionMonitor.reportDisconnected();
    vi.advanceTimersByTime(4000);
    await w.vm.$nextTick();
    expect(w.find('.w-banner').exists()).toBe(true);

    estado.widgetConnectionMonitor.reportConnected();
    await w.vm.$nextTick();
    expect(w.find('.w-banner').exists()).toBe(false);
  });

  it('nasce já avisando quando o widget abre com a conexão caída', async () => {
    // A queda acontece ANTES de a tela existir — o visitante abre o widget sem
    // rede. Um consumidor que só escuta mudanças nasceria mudo aqui.
    estado.widgetConnectionMonitor.reportDisconnected();
    vi.advanceTimersByTime(4000);

    const w = montarFaixa();
    await w.vm.$nextTick();

    expect(w.find('.w-banner').text()).toBe(ptBR.CONNECTION.RECONNECTING);
  });
});

describe('2.07 — a faixa está LIGADA na tela de mensagens', () => {
  const criarStore = () =>
    createStore({
      modules: {
        appConfig: { namespaced: true, getters: { darkMode: () => 'light' } },
        conversation: {
          namespaced: true,
          getters: { getGroupedConversation: () => [] },
          actions: { setUserLastSeen: () => {} },
        },
      },
    });

  // O rodapé é um dublê com um campo de texto de verdade: o que o aceite pede
  // é que ele continue UTILIZÁVEL com a rede caída, e isso se mede perguntando
  // ao campo, não lendo o template.
  const RodapeFalso = {
    name: 'ChatFooter',
    template:
      '<footer class="rodape-falso"><textarea class="campo" /></footer>',
  };

  const montarTela = async () => {
    await carregarTela();
    return mount(estado.Messages, {
      global: globalDeMontagem({
        plugins: [criarStore(), i18n],
        stubs: { ConversationWrap: true, ChatFooter: RodapeFalso },
      }),
    });
  };

  it('com a rede caída a faixa aparece NA TELA, acima da conversa', async () => {
    const w = await montarTela();
    expect(w.find('.w-banner').exists()).toBe(false);

    estado.widgetConnectionMonitor.reportDisconnected();
    vi.advanceTimersByTime(4000);
    await w.vm.$nextTick();

    const faixa = w.find('.w-banner');
    expect(faixa.exists()).toBe(true);

    // Ordem no documento: a faixa vem ANTES da conversa. Um overlay ancorado no
    // rodapé passaria em "a faixa existe" e reprovaria o aceite.
    const nos = [...w.element.querySelectorAll('*')];
    const conversa = w.find('conversation-wrap-stub').element;
    expect(nos.indexOf(faixa.element)).toBeLessThan(nos.indexOf(conversa));
  });

  it('composer utilizável: o campo continua lá e habilitado com a rede caída', async () => {
    const w = await montarTela();
    estado.widgetConnectionMonitor.reportDisconnected();
    vi.advanceTimersByTime(20000); // passa de reconectando para offline
    await w.vm.$nextTick();

    expect(w.find('.w-banner').classes()).toContain('w-banner--error');
    const campo = w.find('textarea.campo');
    expect(campo.exists()).toBe(true);
    expect(campo.attributes('disabled')).toBeUndefined();
    expect(w.find('.rodape-falso').isVisible()).toBe(true);
  });
});

describe('2.07 — o esqueleto de carregamento', () => {
  const montarEsqueleto = props =>
    mount(estado.ConversationSkeleton, {
      props,
      global: globalDeMontagem(),
    });

  it('carregamento de 400 ms não mostra esqueleto nenhum', async () => {
    const w = montarEsqueleto({ loading: true });

    vi.advanceTimersByTime(400);
    await w.setProps({ loading: false });
    vi.advanceTimersByTime(2000);
    await w.vm.$nextTick();

    expect(w.find('.w-skeleton').exists()).toBe(false);
  });

  it('acima de 600 ms o esqueleto aparece', async () => {
    const w = montarEsqueleto({ loading: true });

    vi.advanceTimersByTime(599);
    await w.vm.$nextTick();
    expect(w.find('.w-skeleton').exists()).toBe(false);

    vi.advanceTimersByTime(2);
    await w.vm.$nextTick();
    expect(w.find('.w-skeleton').exists()).toBe(true);
  });

  it('quem anuncia o carregamento é o spinner, não as caixas cinzas', async () => {
    const w = montarEsqueleto({ loading: true });
    vi.advanceTimersByTime(700);
    await w.vm.$nextTick();

    expect(w.find('.w-skeleton').attributes('aria-hidden')).toBe('true');
    const spinner = w.find('.w-spinner');
    expect(spinner.attributes('role')).toBe('status');
    expect(spinner.attributes('aria-label')).toBe(ptBR.CONNECTION.LOADING);
  });

  it('o esqueleto some quando o carregamento termina', async () => {
    const w = montarEsqueleto({ loading: true });
    vi.advanceTimersByTime(700);
    await w.vm.$nextTick();
    expect(w.find('.w-skeleton').exists()).toBe(true);

    await w.setProps({ loading: false });
    await w.vm.$nextTick();
    expect(w.find('.w-skeleton').exists()).toBe(false);
  });
});

describe('2.07 — o esqueleto está LIGADO na lista de mensagens', () => {
  const criarStore = buscando =>
    createStore({
      modules: {
        appConfig: { namespaced: true, getters: { darkMode: () => 'light' } },
        conversation: {
          namespaced: true,
          getters: {
            getEarliestMessage: () => ({ id: 1 }),
            getLastMessage: () => ({}),
            getAllMessagesLoaded: () => false,
            getIsFetchingList: () => buscando,
            getConversationSize: () => 0,
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

  const montarLista = async buscando => {
    await carregarLista();
    return mount(estado.ConversationWrap, {
      props: { groupedMessages: [] },
      global: globalDeMontagem({
        plugins: [criarStore(buscando), i18n],
        stubs: { ChatMessage: true, WDateSeparator: true },
      }),
    });
  };

  it('buscando a lista há mais de 600 ms, o esqueleto aparece DENTRO da conversa', async () => {
    const w = await montarLista(true);

    vi.advanceTimersByTime(599);
    await w.vm.$nextTick();
    expect(w.find('.w-skeleton').exists()).toBe(false);

    vi.advanceTimersByTime(2);
    await w.vm.$nextTick();
    expect(w.find('.w-skeleton').exists()).toBe(true);
  });

  it('sem busca em curso, nada aparece por mais que o tempo passe', async () => {
    const w = await montarLista(false);

    vi.advanceTimersByTime(5000);
    await w.vm.$nextTick();

    expect(w.find('.w-skeleton').exists()).toBe(false);
  });
});
