/**
 * Mecanismo do bloco 2.07 — O WATCHDOG QUE RECONECTA E REPORTA.
 *
 * O diagnóstico media o defeito assim: `STALE_CHECK_INTERVAL` roda a cada 15 s
 * dentro do widget e a única coisa que fazia era `syncLatestMessages()`. Ele
 * não reabria o socket e não avisava ninguém — nem o monitor de conexão, que é
 * quem acende a faixa. Com o canal FECHADO isso é buscar o passado por cima de
 * um canal morto: o visitante ficava numa tela que dizia que estava tudo bem.
 *
 * ── O RECORTE, para o próximo a mexer aqui ───────────────────────────────────
 *
 * O último teste deste arquivo não é decoração: ele TRAVA o gate `!isOpen()`.
 * `lastEventReceivedAt` só sobe em evento de subscription, e o ping do servidor
 * é consumido dentro de `connection.js` (`case message_types.ping: return null`),
 * então 25 s de silêncio numa conversa parada é o estado NORMAL — tirar o gate
 * reabriria o socket de todo visitante ocioso a cada 15 s. E o socket que morre
 * com `readyState` ainda OPEN já tem dono: o `ConnectionMonitor` da própria
 * lib, com `staleThreshold = 6` s contados nos pings. Este arquivo mede o que
 * sobra, que é o canal fechado.
 *
 * ── O QUE ESTE ARQUIVO NÃO FAZ ───────────────────────────────────────────────
 *
 * Não mede "a função foi chamada" num dublê do connector. O sujeito é a classe
 * REAL do widget (`widget/helpers/actionCable.js`), com a herança real, sobre
 * um `@rails/actioncable` dublado NA FORMA REAL da lib instalada
 * (`consumer.connection.isOpen()/reopen()/isActive()`,
 * `consumer.subscriptions.create(params, mixin)`) — conferida em
 * `node_modules/@rails/actioncable/src/connection.js`. Um dublê com a forma
 * errada deixaria o aceite passar aqui e morto no cliente.
 *
 * E o que se pergunta no fim é o ESTADO DO MONITOR, que é o mesmo objeto que a
 * faixa lê em `ConnectionBanner.vue` (medido em `estadosDeVerdade.spec.js`).
 */
import { CONNECTION_STATES } from 'widget/state/connectionMonitor';

const STALE_CHECK_INTERVAL = 15000;
const STALE_EVENT_THRESHOLD = 25000;

// O `beforeEach` reavalia os módulos (`resetModules` + `import()` do connector
// inteiro). É trabalho de CPU, não de tempo, e o relógio falso não o acelera:
// com este arquivo e `components/specs/estadosDeVerdade.spec.js` na mesma
// máquina, o hook estourava o teto CRAVADO de 10 s e o vermelho saía como
// «Hook timed out in 10000ms» — um vermelho que não fala do código, e que ainda
// derruba o teste seguinte por deixar `estado` pela metade.
vi.setConfig({ testTimeout: 30000, hookTimeout: 30000 });

// O socket falso. `aberta` é o valor que o teste controla, porque a decisão do
// watchdog depende dele: silêncio com socket ABERTO é outra coisa (o fluxo está
// quieto) que silêncio com socket FECHADO (o fluxo morreu sem avisar).
const criarConsumidorFalso = () => {
  const conexao = {
    aberta: false,
    isOpen: vi.fn(() => conexao.aberta),
    isActive: vi.fn(() => conexao.aberta),
    reopen: vi.fn(() => {
      conexao.aberta = true;
    }),
  };
  const consumidor = {
    connection: conexao,
    // A lib guarda o mixin e devolve a subscription; é por esse mixin que os
    // callbacks `connected`/`disconnected` chegam ao connector.
    mixin: null,
    subscriptions: {
      create: vi.fn((params, mixin) => {
        consumidor.mixin = mixin;
        return { perform: vi.fn(), unsubscribe: vi.fn() };
      }),
    },
    disconnect: vi.fn(),
  };
  return consumidor;
};

let consumidorFalso;

vi.mock('@rails/actioncable', () => ({
  createConsumer: vi.fn(() => consumidorFalso),
}));

// O widget toca som ao receber mensagem; nada disso importa aqui e o jsdom não
// tem `Audio` de verdade.
vi.mock('widget/helpers/WidgetAudioNotificationHelper', () => ({
  playNewMessageNotificationInWidget: vi.fn(),
}));

// `document.visibilityState` é somente leitura; o helper abaixo é o que o
// watchdog consulta, e é por ele que o teste manda a aba para o fundo.
vi.mock('dashboard/helper/AudioAlerts/WindowVisibilityHelper', () => ({
  default: { isWindowVisible: vi.fn(() => true) },
}));

const criarAppFalso = () => ({
  $store: {
    getters: {
      getCurrentAccountId: 1,
      getCurrentUserID: 2,
      'conversationAttributes/getConversationParams': { id: 7 },
    },
    dispatch: vi.fn(() => Promise.resolve()),
  },
});

let estado;

/** Avança o relógio até o watchdog rodar uma vez, com o fluxo já silencioso. */
const deixarOFluxoSilenciar = conector => {
  // O watchdog só age se `Date.now() - lastEventReceivedAt > 25 s`. Empurrar a
  // marca para trás é o mesmo que ter passado o tempo, e não depende de o
  // relógio falso mexer em `Date.now()`.
  conector.lastEventReceivedAt = Date.now() - (STALE_EVENT_THRESHOLD + 1000);
  vi.advanceTimersByTime(STALE_CHECK_INTERVAL + 1);
};

beforeEach(async () => {
  vi.resetModules();
  vi.useFakeTimers();
  consumidorFalso = criarConsumidorFalso();
  estado = {
    ActionCableConnector: (await import('widget/helpers/actionCable')).default,
    ...(await import('widget/state')),
    WindowVisibilityHelper: (
      await import('dashboard/helper/AudioAlerts/WindowVisibilityHelper')
    ).default,
  };
  estado.WindowVisibilityHelper.isWindowVisible.mockReturnValue(true);
  const Base = (await import('shared/helpers/BaseActionCableConnector'))
    .default;
  Base.isDisconnected = false;
});

afterEach(() => {
  vi.useRealTimers();
});

describe('2.07 — o watchdog com o socket morto em silêncio', () => {
  it('o dublê está de fato no lugar do @rails/actioncable', () => {
    // Guarda anti-`vi.mock` órfão: se o especificador do import mudar, o mock
    // fica sem alvo e TODO o resto deste arquivo passaria medindo o socket de
    // verdade — ou explodindo por motivo nenhum.
    const conector = new estado.ActionCableConnector(criarAppFalso(), 'tok');
    expect(consumidorFalso.subscriptions.create).toHaveBeenCalledTimes(1);
    expect(typeof consumidorFalso.mixin.connected).toBe('function');
    conector.disconnect();
  });

  it('REABRE o socket quando o fluxo silencia e a conexão está fechada', () => {
    const conector = new estado.ActionCableConnector(criarAppFalso(), 'tok');
    consumidorFalso.connection.aberta = false;
    consumidorFalso.connection.reopen.mockClear();

    deixarOFluxoSilenciar(conector);

    expect(consumidorFalso.connection.reopen).toHaveBeenCalledTimes(1);
    conector.disconnect();
  });

  it('REPORTA a queda ao monitor, e a faixa acende depois da carência', () => {
    const conector = new estado.ActionCableConnector(criarAppFalso(), 'tok');
    consumidorFalso.connection.aberta = false;

    deixarOFluxoSilenciar(conector);
    expect(estado.widgetConnectionMonitor.state).toBe(CONNECTION_STATES.ONLINE);

    // A carência de 3 s do bloco continua valendo: o watchdog reporta o FATO,
    // quem decide quando avisar o visitante é o monitor.
    vi.advanceTimersByTime(3001);
    expect(estado.widgetConnectionMonitor.state).toBe(
      CONNECTION_STATES.RECONNECTING
    );
    conector.disconnect();
  });

  it('a volta do socket APAGA a faixa — o laço fecha', () => {
    const conector = new estado.ActionCableConnector(criarAppFalso(), 'tok');
    consumidorFalso.connection.aberta = false;

    deixarOFluxoSilenciar(conector);
    vi.advanceTimersByTime(3001);
    expect(estado.widgetConnectionMonitor.state).toBe(
      CONNECTION_STATES.RECONNECTING
    );

    // O socket volta e a lib chama `connected`. Sem a marca de "estava caído",
    // `checkConnection()` cai no ramo `else` e `onReconnect` NUNCA roda: a
    // faixa fica acesa para sempre, com a conexão de volta.
    consumidorFalso.connection.aberta = true;
    consumidorFalso.mixin.connected();

    expect(estado.widgetConnectionMonitor.state).toBe(CONNECTION_STATES.ONLINE);
    conector.disconnect();
  });

  it('com o socket ABERTO e só quieto, não reabre nem assusta o visitante', () => {
    // Forçando a condição contrária: silêncio de 25 s pode ser conversa parada.
    // Reabrir um socket saudável derruba o canal por nada, e acender a faixa
    // ensina o visitante a ignorá-la.
    const conector = new estado.ActionCableConnector(criarAppFalso(), 'tok');
    consumidorFalso.connection.aberta = true;
    consumidorFalso.connection.reopen.mockClear();

    deixarOFluxoSilenciar(conector);
    vi.advanceTimersByTime(5000);

    expect(consumidorFalso.connection.reopen).not.toHaveBeenCalled();
    expect(estado.widgetConnectionMonitor.state).toBe(CONNECTION_STATES.ONLINE);
    conector.disconnect();
  });

  it('mas continua fazendo o gap-fill que já fazia', () => {
    // O que o bloco NÃO pode perder: o `syncLatestMessages` que já existia.
    const app = criarAppFalso();
    const conector = new estado.ActionCableConnector(app, 'tok');
    app.$store.dispatch.mockClear();
    consumidorFalso.connection.aberta = true;

    deixarOFluxoSilenciar(conector);

    expect(app.$store.dispatch).toHaveBeenCalledWith(
      'conversation/syncLatestMessages'
    );
    conector.disconnect();
  });

  it('com a aba OCULTA o watchdog não faz nada', () => {
    const conector = new estado.ActionCableConnector(criarAppFalso(), 'tok');
    estado.WindowVisibilityHelper.isWindowVisible.mockReturnValue(false);
    consumidorFalso.connection.aberta = false;
    consumidorFalso.connection.reopen.mockClear();

    deixarOFluxoSilenciar(conector);
    vi.advanceTimersByTime(5000);

    expect(consumidorFalso.connection.reopen).not.toHaveBeenCalled();
    expect(estado.widgetConnectionMonitor.state).toBe(CONNECTION_STATES.ONLINE);
    conector.disconnect();
  });
});
