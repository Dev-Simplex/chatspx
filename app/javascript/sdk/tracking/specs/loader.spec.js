/**
 * Bloco 5.07(c) + 5.08 (T-C2.8) — o carregamento SOB DEMANDA e a entrega ao widget.
 *
 * Duas garantias, e a primeira é de orçamento de bytes: sem configuração de tracking na
 * inbox, **nada é buscado** — nem a requisição acontece. A segunda é de contrato: a origem
 * chega ao widget pelos dois eventos que o bridge JÁ trata, com `first_*` no contato e o
 * resto na conversa, exatamente como o `Tracking::OriginRecorder` grava.
 */
import { hasTrackingConfig, loadCollector, COLLECTOR_PATH } from '../loader';
import { attachOriginAttributes } from '../attach';
import { captureOrigin } from '../capture';

describe('5.08 — só carrega quando a inbox tem tracking (T-C2.8)', () => {
  it('reconhece configuração por qualquer um dos três identificadores públicos', () => {
    expect(hasTrackingConfig({ ga4_measurement_id: 'G-ABC' })).toBe(true);
    expect(hasTrackingConfig({ meta_pixel_id: '123' })).toBe(true);
    expect(hasTrackingConfig({ google_ads_send_to: 'AW-1/x' })).toBe(true);
  });

  it('NÃO considera `test_mode` como configuração — ligar por causa dele seria decidir pelo cliente', () => {
    expect(hasTrackingConfig({ test_mode: true })).toBe(false);
  });

  it('inbox sem tracking: nem a requisição acontece', async () => {
    expect(hasTrackingConfig(undefined)).toBe(false);
    expect(hasTrackingConfig({})).toBe(false);
    await expect(
      loadCollector({ baseUrl: 'https://app.test', tracking: {} })
    ).resolves.toBeNull();
  });

  it('devolve null — e não lança — quando o artefato não carrega', async () => {
    await expect(
      loadCollector({
        baseUrl: 'https://nao-existe.invalid',
        tracking: { ga4_measurement_id: 'G-ABC' },
      })
    ).resolves.toBeNull();
  });

  it('o caminho do artefato é fixo e é o coberto pelo SdkCachePolicy', () => {
    expect(COLLECTOR_PATH).toBe('/packs/js/tracking.js');
  });
});

describe('5.08 — entrega ao widget (T-C2.6)', () => {
  beforeEach(() => window.localStorage.clear());

  const chegarPorAnuncio = () =>
    captureOrigin({
      location: {
        search: '?utm_source=google&gclid=Cj0KCQ',
        host: 'loja.com.br',
        origin: 'https://loja.com.br',
        pathname: '/promo',
      },
      referrer: 'https://www.google.com/',
    });

  it('manda `first_*` ao CONTATO e o resto à CONVERSA — o mesmo escopo do backend', async () => {
    chegarPorAnuncio();
    const sendMessage = vi.fn();

    await attachOriginAttributes({ tracking: {}, sendMessage });

    const eventos = Object.fromEntries(
      sendMessage.mock.calls.map(([nome, corpo]) => [
        nome,
        corpo.customAttributes,
      ])
    );
    expect(Object.keys(eventos).sort()).toEqual([
      'set-conversation-custom-attributes',
      'set-custom-attributes',
    ]);
    expect(eventos['set-custom-attributes'].first_utm_source).toBe('google');
    expect(eventos['set-custom-attributes'].last_utm_source).toBeUndefined();
    expect(eventos['set-conversation-custom-attributes'].last_utm_source).toBe(
      'google'
    );
    expect(eventos['set-conversation-custom-attributes'].gcl_aw).toMatch(
      /^GCL\./
    );
  });

  it('não manda evento nenhum quando não há origem coletada', async () => {
    const sendMessage = vi.fn();

    await attachOriginAttributes({ tracking: {}, sendMessage });

    expect(sendMessage).not.toHaveBeenCalled();
  });

  it('não propaga exceção de um `sendMessage` quebrado — o chat não pode cair por causa disto', async () => {
    chegarPorAnuncio();
    const sendMessage = vi.fn(() => {
      throw new Error('iframe sumiu');
    });

    await expect(
      attachOriginAttributes({ tracking: {}, sendMessage })
    ).resolves.toEqual({});
  });
});
