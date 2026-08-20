import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import {
  createTagsBridge,
  entradaDoMapa,
  metaPixelInicializado,
  ga4Configurado,
  semPii,
  PII_KEYS,
} from '../tags';
import { SDK_EVENT_CONTRACT } from 'widget/constants/sdkEvents';

/**
 * Bloco 5.10 — a PONTE DE TAGS.
 *
 * O que estes exemplos protegem nao e "a funcao chama a funcao": e o dinheiro do cliente.
 * Uma pagina com dois pixels e um `fbq('track', ...)` conta a conversao nos DOIS, e o
 * cliente decide midia sobre um numero que nunca aconteceu. E uma excecao dentro da ponte,
 * num container do GTM, mata as tags SEGUINTES do container — o site do cliente para de
 * medir e a culpa cai no chat.
 */

const PIXEL = '123456789012345';
const GA4 = 'G-ABC123';
const ADS = 'AW-123456789/AbCdEfGhIj';

let fbq;
let gtag;
let consoleSpies;

const comTresPixels = () => {
  fbq = vi.fn();
  fbq.getState = () => ({
    pixels: [
      { id: '999999999999999' },
      { id: PIXEL },
      { id: '888888888888888' },
    ],
  });
  window.fbq = fbq;
};

const comGtag = (configurados = [GA4]) => {
  gtag = vi.fn();
  window.gtag = gtag;
  window.dataLayer = window.dataLayer || [];
  configurados.forEach(id => window.dataLayer.push(['config', id]));
};

const ponte = (overrides = {}) =>
  createTagsBridge({
    tracking: {
      meta_pixel_id: PIXEL,
      ga4_measurement_id: GA4,
      google_ads_send_to: ADS,
      event_map: {
        chatspx_lead: { enabled: true, meta: 'Lead', ga4: 'generate_lead' },
        chatspx_conversation_started: {
          enabled: true,
          meta: 'Contact',
          ga4: 'conversation_start',
        },
        chatspx_widget_opened: {
          enabled: false,
          meta: null,
          ga4: 'widget_open',
        },
      },
      ...overrides.tracking,
    },
    isAllowed: overrides.isAllowed ?? (() => true),
  });

beforeEach(() => {
  window.dataLayer = [];
  delete window.fbq;
  delete window.gtag;
  consoleSpies = ['log', 'warn', 'error', 'info', 'debug'].map(nivel =>
    vi.spyOn(console, nivel).mockImplementation(() => {})
  );
});

afterEach(() => {
  consoleSpies.forEach(spy => spy.mockRestore());
});

const eventosDoDataLayer = () =>
  window.dataLayer.filter(item => !Array.isArray(item) && item?.event);

describe('5.10 — o dataLayer vai SEMPRE, e e o unico que vai sem configuracao', () => {
  it('publica o evento com o nome de tracking e o event_id', () => {
    ponte().onTrackingEvent({
      name: 'chatspx_lead',
      properties: { value: 199, currency: 'BRL' },
      eventId: 'uuid-1',
    });

    expect(eventosDoDataLayer()).toEqual([
      {
        event: 'chatspx_lead',
        value: 199,
        currency: 'BRL',
        chatspx_event_id: 'uuid-1',
      },
    ]);
  });

  it('omite a chave do id quando nao ha id, em vez de publicar undefined', () => {
    ponte().onTrackingEvent({ name: 'chatspx_lead', properties: {} });

    expect(eventosDoDataLayer()[0]).toEqual({ event: 'chatspx_lead' });
    expect(Object.keys(eventosDoDataLayer()[0])).not.toContain(
      'chatspx_event_id'
    );
  });

  // T-C4.10 — o padrao de fabrica. Quem nao configurou NADA nao tem tag nossa no site dele.
  it('sem configuracao nenhuma: dataLayer sim, fbq e gtag nao', () => {
    comTresPixels();
    comGtag();

    createTagsBridge({ tracking: {}, isAllowed: () => true }).onTrackingEvent({
      name: 'chatspx_lead',
      properties: { value: 10 },
      eventId: 'uuid-1',
    });

    expect(eventosDoDataLayer()).toHaveLength(1);
    expect(fbq).not.toHaveBeenCalled();
    expect(gtag).not.toHaveBeenCalled();
  });

  // O evento proprio do site (5.16) nao esta no event_map. Ele publica e para ai.
  it('evento proprio do site vai so ao dataLayer, mesmo com pixel configurado', () => {
    comTresPixels();
    comGtag();

    ponte().onTrackingEvent({
      name: 'chatspx_orcamento_pedido',
      properties: { plano: 'pro' },
      eventId: 'uuid-9',
    });

    expect(eventosDoDataLayer()[0].event).toBe('chatspx_orcamento_pedido');
    expect(fbq).not.toHaveBeenCalled();
    expect(gtag).not.toHaveBeenCalled();
  });

  it('nao substitui o dataLayer do cliente — empurra no MESMO array', () => {
    const doCliente = window.dataLayer;
    doCliente.push({ event: 'algo_do_cliente' });

    ponte().onTrackingEvent({ name: 'chatspx_lead', eventId: 'uuid-1' });

    expect(window.dataLayer).toBe(doCliente);
    expect(window.dataLayer[0]).toEqual({ event: 'algo_do_cliente' });
  });
});

describe('5.10 — Meta: trackSingle, e o evento NAO vaza para os outros pixels', () => {
  it('dispara trackSingle no pixel configurado, com eventID, uma vez so', () => {
    comTresPixels();

    ponte().onTrackingEvent({
      name: 'chatspx_lead',
      properties: { value: 199, currency: 'BRL' },
      eventId: 'uuid-1',
    });

    expect(fbq).toHaveBeenCalledTimes(1);
    expect(fbq).toHaveBeenCalledWith(
      'trackSingle',
      PIXEL,
      'Lead',
      { value: 199, currency: 'BRL' },
      { eventID: 'uuid-1' }
    );
  });

  // A diferenca deliberada contra a referencia de mercado: `track` vaza para TODOS.
  it('nunca usa o verbo `track`, que dispararia nos tres pixels da pagina', () => {
    comTresPixels();

    ponte().onTrackingEvent({ name: 'chatspx_lead', eventId: 'uuid-1' });

    const verbos = fbq.mock.calls.map(chamada => chamada[0]);
    expect(verbos).toEqual(['trackSingle']);
  });

  // "sem pixel: nenhum PageView duplicado" — nos nunca instalamos nem inicializamos.
  it('nunca chama init nem PageView', () => {
    comTresPixels();

    ponte().onTrackingEvent({ name: 'chatspx_lead', eventId: 'uuid-1' });
    ponte().onTrackingEvent({
      name: 'chatspx_conversation_started',
      eventId: 'uuid-2',
    });

    const chamadas = fbq.mock.calls.flat();
    expect(chamadas).not.toContain('init');
    expect(chamadas).not.toContain('PageView');
  });

  it('sem `window.fbq` na pagina, nao dispara nada de Meta e nao lanca', () => {
    comGtag();

    expect(() =>
      ponte().onTrackingEvent({ name: 'chatspx_lead', eventId: 'uuid-1' })
    ).not.toThrow();
    expect(eventosDoDataLayer()).toHaveLength(1);
  });

  it('evento desligado no mapa nao vai a Meta, mas continua indo ao dataLayer', () => {
    comTresPixels();

    ponte().onTrackingEvent({
      name: 'chatspx_widget_opened',
      eventId: 'uuid-1',
    });

    expect(fbq).not.toHaveBeenCalled();
    expect(eventosDoDataLayer()).toHaveLength(1);
  });

  it('evento sem nome de Meta no mapa nao vai a Meta', () => {
    comTresPixels();
    const p = ponte({
      tracking: {
        event_map: {
          chatspx_lead: { enabled: true, meta: null, ga4: 'generate_lead' },
        },
      },
    });

    p.onTrackingEvent({ name: 'chatspx_lead', eventId: 'uuid-1' });

    expect(fbq).not.toHaveBeenCalled();
  });
});

describe('5.10 — Google: send_to explicito, para nao disparar em todas as propriedades', () => {
  it('GA4 recebe o nome mapeado e o send_to do measurement id', () => {
    comGtag();

    ponte().onTrackingEvent({
      name: 'chatspx_lead',
      properties: { value: 199, currency: 'BRL' },
      eventId: 'uuid-1',
    });

    expect(gtag).toHaveBeenCalledWith('event', 'generate_lead', {
      value: 199,
      currency: 'BRL',
      send_to: GA4,
    });
  });

  it('a conversao do Ads sai com send_to, valor e transaction_id = event_id', () => {
    comGtag();

    ponte().onTrackingEvent({
      name: 'chatspx_lead',
      properties: { value: 199, currency: 'BRL' },
      eventId: 'uuid-1',
    });

    expect(gtag).toHaveBeenCalledWith('event', 'conversion', {
      send_to: ADS,
      value: 199,
      currency: 'BRL',
      transaction_id: 'uuid-1',
    });
  });

  // O gatilho do Ads e o VALOR. Sem valor, uma conversao do Ads e um ping sem sentido que
  // envenena a conta de anuncio do cliente.
  it('sem `value` nas properties, o Ads NAO dispara — o GA4 sim', () => {
    comGtag();

    ponte().onTrackingEvent({
      name: 'chatspx_conversation_started',
      eventId: 'uuid-1',
    });

    const conversoes = gtag.mock.calls.filter(c => c[1] === 'conversion');
    expect(conversoes).toEqual([]);
    expect(gtag).toHaveBeenCalledWith('event', 'conversation_start', {
      send_to: GA4,
    });
  });

  it('sem `window.gtag`, nao dispara nada do Google e nao lanca', () => {
    comTresPixels();

    expect(() =>
      ponte().onTrackingEvent({
        name: 'chatspx_lead',
        properties: { value: 1 },
        eventId: 'uuid-1',
      })
    ).not.toThrow();
  });

  it('nao substitui o gtag do cliente', () => {
    comGtag();
    const doCliente = window.gtag;

    ponte().onTrackingEvent({
      name: 'chatspx_lead',
      properties: { value: 1 },
      eventId: 'u',
    });

    expect(window.gtag).toBe(doCliente);
  });
});

describe('5.10 — o gate de consentimento (5.09) e injetado, nunca importado', () => {
  it('com o proposito negado, fbq e gtag nao disparam — o dataLayer continua', () => {
    comTresPixels();
    comGtag();

    ponte({ isAllowed: () => false }).onTrackingEvent({
      name: 'chatspx_lead',
      properties: { value: 1 },
      eventId: 'uuid-1',
    });

    expect(fbq).not.toHaveBeenCalled();
    expect(gtag).not.toHaveBeenCalled();
    expect(eventosDoDataLayer()).toHaveLength(1);
  });

  it('separa os propositos: analytics concedido e anuncio negado deixa passar so o GA4', () => {
    comTresPixels();
    comGtag();

    ponte({
      isAllowed: proposito => proposito === 'analytics_storage',
    }).onTrackingEvent({
      name: 'chatspx_lead',
      properties: { value: 199 },
      eventId: 'uuid-1',
    });

    expect(fbq).not.toHaveBeenCalled();
    const eventos = gtag.mock.calls.map(c => c[1]);
    expect(eventos).toEqual(['generate_lead']);
  });
});

describe('5.10 — a ponte NUNCA lanca (T-C4.8)', () => {
  it('fbq que explode nao impede o gtag nem o dataLayer', () => {
    fbq = vi.fn(() => {
      throw new Error('tag de terceiro quebrada');
    });
    fbq.getState = () => ({ pixels: [{ id: PIXEL }] });
    window.fbq = fbq;
    comGtag();

    expect(() =>
      ponte().onTrackingEvent({
        name: 'chatspx_lead',
        properties: { value: 1 },
        eventId: 'uuid-1',
      })
    ).not.toThrow();

    expect(gtag).toHaveBeenCalled();
    expect(eventosDoDataLayer()).toHaveLength(1);
  });

  it('dataLayer que explode nao impede as tags', () => {
    window.dataLayer = {
      push: () => {
        throw new Error('dataLayer sequestrado');
      },
      filter: () => [],
    };
    comTresPixels();

    expect(() =>
      ponte().onTrackingEvent({ name: 'chatspx_lead', eventId: 'uuid-1' })
    ).not.toThrow();
    expect(fbq).toHaveBeenCalled();
  });

  it('evento sem nome nao faz nada e nao lanca', () => {
    comTresPixels();

    expect(() => ponte().onTrackingEvent({})).not.toThrow();
    expect(fbq).not.toHaveBeenCalled();
  });

  it('console limpo: nenhuma tag nossa escreve no console do cliente', () => {
    comTresPixels();
    comGtag();

    ponte().onTrackingEvent({
      name: 'chatspx_lead',
      properties: { value: 1 },
      eventId: 'uuid-1',
    });
    ponte().onWindowEvent('chatwoot:conversation-created', {
      conversation_id: 7,
    });

    consoleSpies.forEach(spy => expect(spy).not.toHaveBeenCalled());
  });
});

describe('5.10 — PII nunca sai no client-side (R10 / RC5)', () => {
  it.each(PII_KEYS)(
    'descarta a chave `%s` do payload de todos os destinos',
    chave => {
      comTresPixels();
      comGtag();

      ponte().onTrackingEvent({
        name: 'chatspx_lead',
        properties: { value: 1, [chave]: 'ana@exemplo.com' },
        eventId: 'uuid-1',
      });

      const publicado = JSON.stringify([
        window.dataLayer,
        fbq.mock.calls,
        gtag.mock.calls,
      ]);
      expect(publicado).not.toContain('ana@exemplo.com');
      expect(publicado).not.toContain(`"${chave}"`);
    }
  );

  it('descarta PII ANINHADA', () => {
    expect(semPii({ value: 1, cliente: { email: 'a@b.c' } })).toEqual({
      value: 1,
      cliente: {},
    });
  });
});

describe('5.10 — a ponte com o vocabulario do 5.04', () => {
  it('traduz o evento de window para o nome de tracking do contrato', () => {
    ponte().onWindowEvent('chatwoot:conversation-created', {
      conversation_id: 7,
      inbox_id: 3,
    });

    expect(eventosDoDataLayer()).toEqual([
      {
        event: 'chatspx_conversation_started',
        conversation_id: 7,
        inbox_id: 3,
      },
    ]);
  });

  it('evento de window declarado com tracking null nao vira evento de tracking', () => {
    expect(SDK_EVENT_CONTRACT['chatwoot:message-sent'].tracking).toBeNull();

    ponte().onWindowEvent('chatwoot:message-sent', { conversation_id: 7 });

    expect(eventosDoDataLayer()).toEqual([]);
  });

  it('evento de window fora do contrato (os sete antigos) nao vira tracking', () => {
    ponte().onWindowEvent('chatwoot:ready', {});

    expect(eventosDoDataLayer()).toEqual([]);
  });
});

describe('5.10 — deteccao do que ja existe na pagina (T-C4.2)', () => {
  it('reconhece o pixel entre os tres inicializados', () => {
    comTresPixels();

    expect(metaPixelInicializado(PIXEL)).toBe(true);
    expect(metaPixelInicializado('000000000000000')).toBe(false);
  });

  it('sem fbq, nada esta inicializado', () => {
    expect(metaPixelInicializado(PIXEL)).toBe(false);
  });

  it('acha o config do GA4 varrendo o dataLayer', () => {
    comGtag([GA4, 'G-OUTRO']);

    expect(ga4Configurado(GA4)).toBe(true);
    expect(ga4Configurado('G-NAOTEM')).toBe(false);
  });

  it('deteccao nunca lanca com fbq de formato inesperado', () => {
    window.fbq = () => {};
    expect(() => metaPixelInicializado(PIXEL)).not.toThrow();
    expect(metaPixelInicializado(PIXEL)).toBe(false);
  });
});

describe('5.10 — o mapa de eventos aceita as duas formas que as pontas escrevem', () => {
  it('forma objeto: enabled + meta + ga4', () => {
    expect(
      entradaDoMapa({ a: { enabled: true, meta: 'Lead', ga4: 'gl' } }, 'a')
    ).toEqual({
      enabled: true,
      meta: 'Lead',
      ga4: 'gl',
    });
  });

  it('forma string (schema de 5.01): o nome vale para os dois destinos', () => {
    expect(entradaDoMapa({ a: 'Lead' }, 'a')).toEqual({
      enabled: true,
      meta: 'Lead',
      ga4: 'Lead',
    });
  });

  it('ausente: nulo, que significa somente dataLayer', () => {
    expect(entradaDoMapa({}, 'a')).toBeNull();
    expect(entradaDoMapa(undefined, 'a')).toBeNull();
  });
});
