import eventsModule from '../events';
import events from 'widget/api/events';
import { IFrameHelper } from 'widget/helpers/utils';
import { reportWidgetError } from 'widget/helpers/telemetry';

vi.mock('widget/api/events');
vi.mock('widget/helpers/telemetry', () => ({ reportWidgetError: vi.fn() }));
vi.mock('widget/helpers/utils', () => ({
  IFrameHelper: { sendMessage: vi.fn() },
}));

/**
 * Bloco 5.16 — `track()`: UMA chamada, os DOIS caminhos.
 *
 * A ORDEM É O ACEITE, não detalhe: o `event_id` nasce no servidor (regra RC7) e é ele que a
 * publicação no navegador carrega. Publicar antes de saber o id daria dois ids para o mesmo fato
 * — e a dedup do 5.13 não teria por onde juntar os dois lados.
 */
const { track } = eventsModule.actions;

describe('5.16 — store `events/track`', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('grava no servidor PRIMEIRO e publica com o `event_id` que ele devolveu', async () => {
    events.track.mockResolvedValue({ data: { event_id: 'uuid-7' } });

    await track(null, {
      name: 'chatspx_orcamento_pedido',
      properties: { valor: 990 },
    });

    expect(events.track).toHaveBeenCalledWith('chatspx_orcamento_pedido', {
      valor: 990,
    });
    expect(IFrameHelper.sendMessage).toHaveBeenCalledWith({
      event: 'onEvent',
      eventIdentifier: null,
      data: { valor: 990 },
      tracking: 'chatspx_orcamento_pedido',
      eventId: 'uuid-7',
    });
  });

  it('POST que falha NÃO cancela a publicação — sai sem id, que é a verdade', async () => {
    const falha = new Error('rede caiu');
    events.track.mockRejectedValue(falha);

    await track(null, { name: 'chatspx_orcamento_pedido', properties: {} });

    // O contrário — silêncio no navegador porque o servidor não respondeu — faria o GTM do
    // cliente perder um evento que aconteceu, por um motivo que não é dele.
    expect(IFrameHelper.sendMessage).toHaveBeenCalledWith(
      expect.objectContaining({
        tracking: 'chatspx_orcamento_pedido',
        eventId: null,
      })
    );
    expect(reportWidgetError).toHaveBeenCalledWith(falha, {
      origem: 'store/events/track',
    });
  });

  it('resposta sem `event_id` publica com `null`, nunca com `undefined`', async () => {
    events.track.mockResolvedValue({ data: {} });

    await track(null, { name: 'chatspx_x', properties: {} });

    expect(IFrameHelper.sendMessage).toHaveBeenCalledWith(
      expect.objectContaining({ eventId: null })
    );
  });

  it('a ação `create` (o `pushEvent` de sempre) continua intocada', async () => {
    events.create.mockResolvedValue({});

    await eventsModule.actions.create(null, { name: 'webwidget.triggered' });

    expect(events.create).toHaveBeenCalledWith('webwidget.triggered');
    expect(IFrameHelper.sendMessage).not.toHaveBeenCalled();
  });
});
