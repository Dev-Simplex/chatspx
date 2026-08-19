/**
 * Mecanismo de aceite do bloco 2.07 — os estados, medidos em milissegundos.
 *
 * ACEITE (§2.2): "Rede cortada 10 s: nada nos primeiros 3 s, faixa depois,
 * composer utilizável; micro-queda de 1,5 s não mostra nada".
 *
 * O aceite é sobre TEMPO. Com relógio falso ele vira asserção exata — e é assim
 * que se prova que a carência tem 3 000 ms, e não "uns segundos".
 */
import {
  CONNECTION_STATES,
  createConnectionMonitor,
} from '../connectionMonitor';
import { createLoadingGate } from '../loadingGate';

describe('2.07 — a faixa de reconexão', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('rede cortada por 10 s: nada nos primeiros 3 s, faixa depois', () => {
    const monitor = createConnectionMonitor();

    monitor.reportDisconnected();
    expect(monitor.state).toBe(CONNECTION_STATES.ONLINE);

    vi.advanceTimersByTime(2999);
    expect(monitor.state).toBe(CONNECTION_STATES.ONLINE);

    vi.advanceTimersByTime(1);
    expect(monitor.state).toBe(CONNECTION_STATES.RECONNECTING);

    vi.advanceTimersByTime(7000); // 10 s no total
    expect(monitor.state).toBe(CONNECTION_STATES.RECONNECTING);
  });

  it('micro-queda de 1,5 s não mostra nada — nem aparece, nem some', () => {
    const monitor = createConnectionMonitor();
    const vistos = [];
    monitor.subscribe(estado => vistos.push(estado));

    monitor.reportDisconnected();
    vi.advanceTimersByTime(1500);
    monitor.reportConnected();
    vi.advanceTimersByTime(10000);

    expect(monitor.state).toBe(CONNECTION_STATES.ONLINE);
    expect(vistos).toEqual([]);
  });

  it('o composer continua utilizável em todo estado', () => {
    const monitor = createConnectionMonitor();

    expect(monitor.canCompose).toBe(true);
    monitor.reportDisconnected();
    vi.advanceTimersByTime(20000);
    expect(monitor.state).toBe(CONNECTION_STATES.OFFLINE);
    expect(monitor.canCompose).toBe(true);
  });

  it('depois de 15 s o estado vira offline, não fica em reconectando para sempre', () => {
    const monitor = createConnectionMonitor();

    monitor.reportDisconnected();
    vi.advanceTimersByTime(14999);
    expect(monitor.state).toBe(CONNECTION_STATES.RECONNECTING);

    vi.advanceTimersByTime(1);
    expect(monitor.state).toBe(CONNECTION_STATES.OFFLINE);
  });

  it('voltar do offline avisa uma vez só, e volta a online', () => {
    const monitor = createConnectionMonitor();
    const vistos = [];
    monitor.subscribe(estado => vistos.push(estado));

    monitor.reportDisconnected();
    vi.advanceTimersByTime(20000);
    monitor.reportConnected();

    expect(vistos).toEqual([
      CONNECTION_STATES.RECONNECTING,
      CONNECTION_STATES.OFFLINE,
      CONNECTION_STATES.ONLINE,
    ]);
  });

  it('quedas repetidas não empilham temporizador', () => {
    const monitor = createConnectionMonitor();

    monitor.reportDisconnected();
    vi.advanceTimersByTime(1000);
    monitor.reportDisconnected();
    monitor.reportDisconnected();
    vi.advanceTimersByTime(2000);

    // 3 000 ms desde a PRIMEIRA queda: a faixa aparece uma vez.
    expect(monitor.state).toBe(CONNECTION_STATES.RECONNECTING);
  });

  it('destruir para de avisar quem escutava', () => {
    const monitor = createConnectionMonitor();
    const vistos = [];
    monitor.subscribe(estado => vistos.push(estado));

    monitor.reportDisconnected();
    monitor.destroy();
    vi.advanceTimersByTime(20000);

    expect(vistos).toEqual([]);
  });
});

describe('2.07 — o esqueleto só acima de 600 ms', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('resposta em 300 ms não mostra esqueleto nenhum', () => {
    const gate = createLoadingGate();
    const vistos = [];
    gate.subscribe(v => vistos.push(v));

    gate.start();
    vi.advanceTimersByTime(300);
    gate.stop();
    vi.advanceTimersByTime(5000);

    expect(gate.isVisible).toBe(false);
    expect(vistos).toEqual([]);
  });

  it('em 600 ms exatos o esqueleto aparece', () => {
    const gate = createLoadingGate();

    gate.start();
    vi.advanceTimersByTime(599);
    expect(gate.isVisible).toBe(false);

    vi.advanceTimersByTime(1);
    expect(gate.isVisible).toBe(true);
  });

  it('quando some, avisa quem escutava', () => {
    const gate = createLoadingGate();
    const vistos = [];
    gate.subscribe(v => vistos.push(v));

    gate.start();
    vi.advanceTimersByTime(600);
    gate.stop();

    expect(vistos).toEqual([true, false]);
  });
});

// O ActionCable é dublado: o que se mede é o TEMPORIZADOR de 15 s, não a
// biblioteca de websocket. Sem o dublê, instanciar o connector tentaria abrir
// um socket que não existe no jsdom.
vi.mock('@rails/actioncable', () => ({
  createConsumer: () => ({
    subscriptions: { create: () => ({ perform: () => {} }) },
    connection: { isOpen: () => true },
  }),
}));

describe('2.07 — o watchdog passa a ter consumidor no widget', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  const montarConnector = async () => {
    const { default: Base } = await import(
      'shared/helpers/BaseActionCableConnector'
    );
    const app = {
      $store: {
        getters: { getCurrentAccountId: 1, getCurrentUserID: 2 },
        dispatch: () => {},
      },
    };
    return new Base(app, 'token');
  };

  it('com o fluxo silencioso e a aba visível, o gancho é chamado aos 15 s', async () => {
    const connector = await montarConnector();
    const chamadas = [];
    connector.onStaleConnection = () => chamadas.push('stale');
    // 26 s atrás: acima do limiar de 25 s que a classe chama de "silencioso".
    connector.lastEventReceivedAt = Date.now() - 26000;

    connector.triggerStaleCheckInterval();
    expect(chamadas).toEqual([]);

    vi.advanceTimersByTime(15000);

    expect(chamadas).toEqual(['stale']);
    connector.isDestroyed = true;
  });

  it('fluxo recente NÃO dispara o gancho — o watchdog não é um cronômetro cego', async () => {
    const connector = await montarConnector();
    const chamadas = [];
    connector.onStaleConnection = () => chamadas.push('stale');
    connector.lastEventReceivedAt = Date.now();

    connector.triggerStaleCheckInterval();
    vi.advanceTimersByTime(15000);

    expect(chamadas).toEqual([]);
    connector.isDestroyed = true;
  });
});
