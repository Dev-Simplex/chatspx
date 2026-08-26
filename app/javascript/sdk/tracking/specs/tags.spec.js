import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import {
  createTagsBridge,
  entradaDoMapa,
  metaPixelInicializado,
  ga4Configurado,
  semPii,
  instalarMetaPixel,
  instalarGoogleTag,
  contaDoAds,
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

/**
 * T-C4.3 — a instalacao CONDICIONAL da tag que falta.
 *
 * Estes exemplos existem porque este e o unico caminho do arquivo que ESCREVE no `window` do
 * cliente. Os outros so leem e chamam o que ja esta la; este cria `fbq`/`gtag` e injeta script
 * de terceiro. Duas coisas tem de ficar provadas o tempo todo:
 *
 *   · sem o opt-in, NADA acontece — e o "sem pixel: nenhum PageView duplicado" do aceite;
 *   · com o opt-in, o `init` sai e o `PageView` NAO — que e o `skipPageView` propriamente.
 *
 * Um exemplo que so afirma ausencia ("nao instalou") passa tambem quando a funcao nem existe.
 * Por isso cada ausencia aqui tem, ao lado, o exemplo que LIGA o interruptor e exige o efeito:
 * o par e que distingue "esta desligado" de "nao faz nada".
 */
const scriptsInjetados = () =>
  [...document.querySelectorAll('script[src]')].map(s => s.getAttribute('src'));

const chamadasDaFila = () => [...(window.fbq?.queue ?? [])].map(a => [...a]);

const comandosDoGtag = () =>
  (window.dataLayer || [])
    .filter(
      item => item && typeof item.length === 'number' && !Array.isArray(item)
    )
    .map(a => [...a]);

describe('5.10 / T-C4.3 — instalar a tag que falta, so com opt-in', () => {
  beforeEach(() => {
    document.querySelectorAll('script[src]').forEach(el => el.remove());
    // eslint-disable-next-line no-underscore-dangle -- `_fbq` e nome do snippet da Meta
    delete window._fbq;
  });

  describe('o padrao de fabrica: desligado', () => {
    it('sem `install_tags`, pagina crua: nenhum fbq, nenhum gtag, nenhum script', () => {
      ponte().onTrackingEvent({
        name: 'chatspx_lead',
        properties: { value: 10 },
        eventId: 'u1',
      });

      expect(window.fbq).toBeUndefined();
      expect(window.gtag).toBeUndefined();
      expect(scriptsInjetados()).toEqual([]);
      // e o dataLayer continua recebendo — "somente dataLayer" e um modo de verdade
      expect(eventosDoDataLayer()).toHaveLength(1);
    });

    it('`install_tags` presente e com os dois FALSOS nao instala nada', () => {
      ponte({
        tracking: { install_tags: { meta: false, google: false } },
      }).onTrackingEvent({ name: 'chatspx_lead', properties: { value: 10 } });

      expect(window.fbq).toBeUndefined();
      expect(window.gtag).toBeUndefined();
    });

    it('opt-in da Meta NAO instala o Google, e vice-versa', () => {
      ponte({ tracking: { install_tags: { meta: true } } }).onTrackingEvent({
        name: 'chatspx_lead',
        properties: { value: 10 },
      });

      expect(typeof window.fbq).toBe('function');
      expect(window.gtag).toBeUndefined();
    });
  });

  describe('ligado: o `init` sai, o `PageView` NAO', () => {
    it('instala o pixel e dispara trackSingle — sem nenhum PageView', () => {
      ponte({ tracking: { install_tags: { meta: true } } }).onTrackingEvent({
        name: 'chatspx_lead',
        properties: { value: 10 },
        eventId: 'u1',
      });

      const chamadas = chamadasDaFila();
      expect(chamadas[0]).toEqual(['init', PIXEL]);
      expect(chamadas.map(c => c[0])).not.toContain('track');
      expect(chamadas.flat()).not.toContain('PageView');
      expect(chamadas.some(c => c[0] === 'trackSingle' && c[1] === PIXEL)).toBe(
        true
      );
    });

    it('injeta o `fbevents.js`, uma vez so, mesmo com dois eventos', () => {
      const p = ponte({ tracking: { install_tags: { meta: true } } });
      p.onTrackingEvent({ name: 'chatspx_lead', properties: { value: 1 } });
      p.onTrackingEvent({ name: 'chatspx_conversation_started' });

      expect(scriptsInjetados()).toEqual([
        'https://connect.facebook.net/en_US/fbevents.js',
      ]);
      expect(chamadasDaFila().filter(c => c[0] === 'init')).toHaveLength(1);
    });

    it('o Google entra com `send_page_view: false` — no GA4 E na conta do Ads', () => {
      ponte({ tracking: { install_tags: { google: true } } }).onTrackingEvent({
        name: 'chatspx_lead',
        properties: { value: 10, currency: 'BRL' },
        eventId: 'u1',
      });

      const configs = comandosDoGtag().filter(c => c[0] === 'config');
      expect(configs).toEqual([
        ['config', GA4, { send_page_view: false }],
        ['config', 'AW-123456789', { send_page_view: false }],
      ]);
      expect(scriptsInjetados()).toEqual([
        `https://www.googletagmanager.com/gtag/js?id=${GA4}`,
      ]);
    });

    it('e depois de instalado o evento sai com `send_to`, como em tag que ja existia', () => {
      ponte({ tracking: { install_tags: { google: true } } }).onTrackingEvent({
        name: 'chatspx_lead',
        properties: { value: 10 },
        eventId: 'u1',
      });

      const evento = comandosDoGtag().find(c => c[1] === 'generate_lead');
      expect(evento?.[2]).toMatchObject({ send_to: GA4 });
    });
  });

  describe('aditivo: quem ja tem a tag nao ganha outra (R9)', () => {
    it('com `fbq` do cliente na pagina, o opt-in nao instala nem sobrescreve', () => {
      comTresPixels();
      const antes = window.fbq;

      ponte({ tracking: { install_tags: { meta: true } } }).onTrackingEvent({
        name: 'chatspx_lead',
        properties: { value: 1 },
        eventId: 'u1',
      });

      expect(window.fbq).toBe(antes);
      expect(scriptsInjetados()).toEqual([]);
      expect(fbq.mock.calls.flat()).not.toContain('init');
    });

    it('com `gtag` do cliente na pagina, idem', () => {
      comGtag();
      const antes = window.gtag;

      ponte({ tracking: { install_tags: { google: true } } }).onTrackingEvent({
        name: 'chatspx_lead',
        properties: { value: 1 },
        eventId: 'u1',
      });

      expect(window.gtag).toBe(antes);
      expect(scriptsInjetados()).toEqual([]);
    });
  });

  describe('o consentimento vem ANTES da instalacao', () => {
    it('negado + opt-in ligado: nada e instalado e nada e pedido para fora', () => {
      ponte({
        tracking: { install_tags: { meta: true, google: true } },
        isAllowed: () => false,
      }).onTrackingEvent({ name: 'chatspx_lead', properties: { value: 10 } });

      expect(window.fbq).toBeUndefined();
      expect(window.gtag).toBeUndefined();
      expect(scriptsInjetados()).toEqual([]);
      // mas o dataLayer continua: publicar nao e disparar
      expect(eventosDoDataLayer()).toHaveLength(1);
    });

    it('so `analytics_storage` concedido instala o Google e NAO instala a Meta', () => {
      ponte({
        tracking: { install_tags: { meta: true, google: true } },
        isAllowed: proposito => proposito === 'analytics_storage',
      }).onTrackingEvent({ name: 'chatspx_lead', properties: { value: 10 } });

      expect(window.fbq).toBeUndefined();
      expect(typeof window.gtag).toBe('function');
      // e o Ads (que e `ad_storage`) nao disparou, mesmo com o gtag ja instalado
      expect(comandosDoGtag().some(c => c[1] === 'conversion')).toBe(false);
    });
  });

  describe('as funcoes de instalacao, isoladas', () => {
    it('`instalarMetaPixel` sem pixel id nao escreve nada', () => {
      expect(instalarMetaPixel(null)).toBe(false);
      expect(window.fbq).toBeUndefined();
    });

    it('`instalarMetaPixel` com `fbq` existente devolve true sem tocar em nada', () => {
      comTresPixels();
      const antes = window.fbq;

      expect(instalarMetaPixel(PIXEL)).toBe(true);
      expect(window.fbq).toBe(antes);
      expect(scriptsInjetados()).toEqual([]);
    });

    it('`instalarGoogleTag` sem destino nenhum nao cria gtag', () => {
      expect(instalarGoogleTag([])).toBe(false);
      expect(instalarGoogleTag([null, undefined])).toBe(false);
      expect(window.gtag).toBeUndefined();
    });

    it('`contaDoAds` separa a conta do rotulo — e o rotulo pertence a conversao', () => {
      expect(contaDoAds('AW-123456789/AbCdEf')).toBe('AW-123456789');
      expect(contaDoAds('AW-123456789')).toBe('AW-123456789');
      expect(contaDoAds(null)).toBeNull();
    });

    it('instalar nunca lanca, mesmo com o documento hostil', () => {
      const original = document.getElementsByTagName;
      document.getElementsByTagName = () => {
        throw new Error('tag de terceiro quebrada');
      };

      expect(() =>
        ponte({ tracking: { install_tags: { meta: true } } }).onTrackingEvent({
          name: 'chatspx_lead',
          properties: { value: 1 },
        })
      ).not.toThrow();

      document.getElementsByTagName = original;
    });
  });

  it('console limpo: instalar nao escreve no console do cliente', () => {
    ponte({
      tracking: { install_tags: { meta: true, google: true } },
    }).onTrackingEvent({ name: 'chatspx_lead', properties: { value: 10 } });

    consoleSpies.forEach(spy => expect(spy).not.toHaveBeenCalled());
  });

  it('a projecao publica de 5.01 e a unica fonte do interruptor', () => {
    // Se alguem trocar a leitura por um default ligado, este exemplo pega: a ponte montada
    // SEM `install_tags` tem de reportar os dois alvos como nao autorizados.
    expect(ponte().instalacaoAutorizada()).toEqual({
      meta: false,
      google: false,
    });
    expect(
      ponte({
        tracking: { install_tags: { meta: true } },
      }).instalacaoAutorizada()
    ).toEqual({ meta: true, google: false });
  });
});
