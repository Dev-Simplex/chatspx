import { describe, it, expect, beforeEach, vi } from 'vitest';

const post = vi.fn();
const sendMessage = vi.fn();
const reportWidgetError = vi.fn();

vi.mock('widget/helpers/axios', () => ({
  API: { post: (...a) => post(...a) },
}));
vi.mock('widget/helpers/utils', () => ({
  IFrameHelper: { sendMessage: (...a) => sendMessage(...a) },
}));
vi.mock('widget/helpers/telemetry', () => ({
  reportWidgetError: (...a) => reportWidgetError(...a),
}));

const carregar = async () =>
  (await import('widget/store/modules/events')).default;

// `buildSearchParamsWithLocale` le o locale de `window.WOOT_WIDGET.$root.$i18n.locale` —
// e o painel montado. Sem este duble, o `catch` do modulo engole um TypeError de setup e o
// exemplo fica verde por nao ter feito nada, que e o pior falso verde que existe.
const montarLocale = () => {
  window.WOOT_WIDGET = { $root: { $i18n: { locale: 'pt_BR' } } };
};

/**
 * Blocos 5.05 e 5.16, do lado do iframe.
 *
 * O que estes exemplos protegem e a TRAVESSIA: o `event_id` nasce no servidor e so vale se
 * chegar ao host, onde estao as tags do cliente. Se ele parar aqui dentro, os dois lados
 * ficam verdes — o backend gravou, o widget nao quebrou — e a Meta conta a conversao duas
 * vezes, porque o disparo do navegador foi sem `eventID`.
 */
describe('5.05 — o event_id atravessa do servidor para o host', () => {
  beforeEach(() => {
    vi.resetModules();
    post.mockReset();
    sendMessage.mockReset();
    reportWidgetError.mockReset();
    montarLocale();
  });

  it('events/create repassa nome e event_id ao host', async () => {
    post.mockResolvedValue({
      data: { event_id: 'uuid-1', name: 'chatspx_widget_opened' },
    });
    const modulo = await carregar();

    await modulo.actions.create({}, { name: 'webwidget.triggered' });

    expect(sendMessage).toHaveBeenCalledWith({
      event: 'trackingEvent',
      name: 'chatspx_widget_opened',
      properties: {},
      eventId: 'uuid-1',
    });
  });

  // `campaign.triggered` responde com `name: null` porque o contrato declara `tracking: null`
  // para o fato. Sem esta guarda o host receberia um evento de tracking sem nome e a ponte
  // publicaria `{ event: null }` no dataLayer do cliente.
  it('nao repassa nada quando o fato nao tem contraparte de tracking', async () => {
    post.mockResolvedValue({ data: { event_id: null, name: null } });
    const modulo = await carregar();

    await modulo.actions.create({}, { name: 'campaign.triggered' });

    expect(sendMessage).not.toHaveBeenCalled();
  });

  it('erro de rede vira erro CONTADO e nao interrompe o visitante', async () => {
    post.mockRejectedValue(new Error('rede'));
    const modulo = await carregar();

    await expect(
      modulo.actions.create({}, { name: 'webwidget.triggered' })
    ).resolves.toBeUndefined();
    expect(reportWidgetError).toHaveBeenCalled();
    expect(sendMessage).not.toHaveBeenCalled();
  });
});

describe('5.16 — track() manda properties e a chave de idempotencia', () => {
  beforeEach(() => {
    vi.resetModules();
    post.mockReset();
    sendMessage.mockReset();
    reportWidgetError.mockReset();
    montarLocale();
  });

  it('posta name, properties e event_key no endpoint de eventos', async () => {
    post.mockResolvedValue({
      data: { event_id: 'uuid-9', name: 'chatspx_orcamento_pedido' },
    });
    const modulo = await carregar();

    await modulo.actions.track(
      {},
      {
        name: 'chatspx_orcamento_pedido',
        properties: { plano: 'pro' },
        eventKey: 'k-1',
      }
    );

    expect(post).toHaveBeenCalledWith(
      expect.stringContaining('/api/v1/widget/events'),
      {
        name: 'chatspx_orcamento_pedido',
        properties: { plano: 'pro' },
        event_key: 'k-1',
      }
    );
  });

  // As properties voltam do STORE, nao da resposta: o servidor nao as devolve, e o dataLayer
  // do cliente precisa delas. Sem isto o evento chega ao GTM sem nenhum parametro.
  it('repassa ao host as properties que o site mandou, junto do event_id', async () => {
    post.mockResolvedValue({
      data: { event_id: 'uuid-9', name: 'chatspx_orcamento_pedido' },
    });
    const modulo = await carregar();

    await modulo.actions.track(
      {},
      {
        name: 'chatspx_orcamento_pedido',
        properties: { plano: 'pro' },
        eventKey: 'k-1',
      }
    );

    expect(sendMessage).toHaveBeenCalledWith({
      event: 'trackingEvent',
      name: 'chatspx_orcamento_pedido',
      properties: { plano: 'pro' },
      eventId: 'uuid-9',
    });
  });

  it('422 do servidor (nome invalido, PII) e contado e nao repassado', async () => {
    post.mockRejectedValue(new Error('422'));
    const modulo = await carregar();

    await modulo.actions.track({}, { name: 'chatspx_x', eventKey: 'k-1' });

    expect(reportWidgetError).toHaveBeenCalled();
    expect(sendMessage).not.toHaveBeenCalled();
  });
});
