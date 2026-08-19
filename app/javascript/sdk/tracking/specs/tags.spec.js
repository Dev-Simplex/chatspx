import {
  createTagBridge,
  ga4ConfigsOnPage,
  installGoogleTag,
  installMetaPixel,
  metaPixelsOnPage,
  routeFor,
  withoutPii,
  META_STANDARD_EVENTS,
} from '../tags';

/**
 * Bloco 5.10 — a ponte de tags.
 *
 * O aceite tem quatro frases, e cada uma vira um bloco aqui:
 *   · página com 3 pixels: o evento **não** vaza;
 *   · sem pixel: nenhum `PageView` duplicado;
 *   · `gtag`/`dataLayer` do cliente continuam funcionais;
 *   · console limpo.
 */

const mapaComLead = {
  chatspx_lead: { enabled: true, meta: 'Lead', ga4: 'generate_lead' },
};

/** Simula o `fbq` real: guarda as chamadas e responde `getState()` como o `fbevents.js` faz. */
const fakeFbq = (pixels = []) => {
  const fbq = vi.fn();
  fbq.getState = () => ({ pixels: pixels.map(id => ({ id })) });
  return fbq;
};

describe('5.10 — a ponte de tags', () => {
  let consoleSpy;

  beforeEach(() => {
    window.dataLayer = [];
    delete window.fbq;
    // eslint-disable-next-line no-underscore-dangle
    delete window._fbq;
    delete window.gtag;
    document.head.innerHTML = '';
    // "Console limpo" é aceite deste bloco, não gosto pessoal: o console é do site do cliente.
    consoleSpy = {
      warn: vi.spyOn(console, 'warn').mockImplementation(() => {}),
      error: vi.spyOn(console, 'error').mockImplementation(() => {}),
      log: vi.spyOn(console, 'log').mockImplementation(() => {}),
    };
  });

  afterEach(() => {
    Object.values(consoleSpy).forEach(spy => spy.mockRestore());
  });

  const semRuidoNoConsole = () => {
    expect(consoleSpy.warn).not.toHaveBeenCalled();
    expect(consoleSpy.error).not.toHaveBeenCalled();
    expect(consoleSpy.log).not.toHaveBeenCalled();
  };

  // ── O `dataLayer` SEMPRE (RC4, T-C4.7) ────────────────────────────────────────────────────
  describe('o `dataLayer` recebe sempre', () => {
    it('publica mesmo sem destino nenhum configurado — é o padrão de fábrica', () => {
      const publicar = createTagBridge({ tracking: {} });

      publicar('chatspx_lead', { lead_source: 'web_widget' });

      expect(window.dataLayer).toEqual([
        { event: 'chatspx_lead', lead_source: 'web_widget' },
      ]);
      semRuidoNoConsole();
    });

    it('publica mesmo quando o evento está DESLIGADO nos destinos', () => {
      // Desligar um evento é decisão sobre para onde o dinheiro do cliente conta — Meta, GA4,
      // Ads. O `dataLayer` não conta nada: ele publica, e quem escuta decide. Gatear esta linha
      // deixaria o GTM do cliente sem um evento que aconteceu.
      const publicar = createTagBridge({
        tracking: {
          meta_pixel_id: '111',
          event_map: { chatspx_lead: { enabled: false, meta: 'Lead' } },
        },
      });
      window.fbq = fakeFbq(['111']);

      publicar('chatspx_lead', {});

      expect(window.dataLayer).toHaveLength(1);
      expect(window.fbq).not.toHaveBeenCalled();
    });

    it('acrescenta o `event_id` quando ele existe, e não a chave vazia quando não', () => {
      const publicar = createTagBridge({ tracking: {} });

      publicar('chatspx_lead', {}, 'uuid-1');
      publicar('chatspx_lead', {});

      expect(window.dataLayer[0]).toEqual({
        event: 'chatspx_lead',
        event_id: 'uuid-1',
      });
      expect(window.dataLayer[1]).toEqual({ event: 'chatspx_lead' });
    });

    it('ESTENDE o `dataLayer` do cliente em vez de substituí-lo (RC2)', () => {
      window.dataLayer = [{ event: 'gtm.js' }, { event: 'meu_evento' }];
      createTagBridge({ tracking: {} })('chatspx_lead', {});

      expect(window.dataLayer).toHaveLength(3);
      expect(window.dataLayer[0]).toEqual({ event: 'gtm.js' });
    });
  });

  // ── A frase que dá nome ao bloco (RC3, T-C4.4) ────────────────────────────────────────────
  describe('página com três pixels: o evento não vaza', () => {
    it('usa `trackSingle` com o pixel NOMEADO, nunca `track`', () => {
      window.fbq = fakeFbq(['111', '222', '333']);
      const publicar = createTagBridge({
        tracking: { meta_pixel_id: '222', event_map: mapaComLead },
      });

      publicar('chatspx_lead', { value: 10 }, 'uuid-1');

      expect(window.fbq).toHaveBeenCalledTimes(1);
      expect(window.fbq).toHaveBeenCalledWith(
        'trackSingle',
        '222',
        'Lead',
        { value: 10 },
        { eventID: 'uuid-1' }
      );
      // A asserção que importa: nenhuma chamada usou o verbo que dispara em TODOS os pixels.
      const verbos = window.fbq.mock.calls.map(([verbo]) => verbo);
      expect(verbos).not.toContain('track');
      expect(verbos).not.toContain('trackCustom');
    });

    it('sem `event_id`, não manda `{ eventID: undefined }`', () => {
      window.fbq = fakeFbq(['222']);
      createTagBridge({
        tracking: { meta_pixel_id: '222', event_map: mapaComLead },
      })('chatspx_lead', {});

      expect(window.fbq).toHaveBeenCalledWith('trackSingle', '222', 'Lead', {});
    });

    it('nome fora dos eventos padrão da Meta vai por `trackSingleCustom` — é o console limpo', () => {
      window.fbq = fakeFbq(['222']);
      createTagBridge({
        tracking: {
          meta_pixel_id: '222',
          event_map: {
            chatspx_orcamento: { enabled: true, meta: 'Orcamento' },
          },
        },
      })('chatspx_orcamento', {});

      expect(window.fbq).toHaveBeenCalledWith(
        'trackSingleCustom',
        '222',
        'Orcamento',
        {}
      );
      expect(META_STANDARD_EVENTS).toContain('Lead');
      expect(META_STANDARD_EVENTS).not.toContain('Orcamento');
    });
  });

  // ── Sem pixel: nenhum PageView duplicado (T-C4.3, decisão Q5) ──────────────────────────────
  describe('sem a tag na página', () => {
    it('NÃO instala nada sem `install_tags` — e não dispara', () => {
      const publicar = createTagBridge({
        tracking: { meta_pixel_id: '222', event_map: mapaComLead },
      });

      publicar('chatspx_lead', {});

      expect(window.fbq).toBeUndefined();
      expect(document.querySelectorAll('script')).toHaveLength(0);
      expect(window.dataLayer).toHaveLength(1); // o `dataLayer` recebeu assim mesmo
      semRuidoNoConsole();
    });

    it('com `install_tags`, instala o pixel SEM `PageView`', () => {
      const publicar = createTagBridge({
        tracking: {
          meta_pixel_id: '222',
          install_tags: true,
          event_map: mapaComLead,
        },
      });

      publicar('chatspx_lead', {});

      const chamadas = window.fbq.queue.concat(
        window.fbq.mock ? window.fbq.mock.calls : []
      );
      const verbos = chamadas.map(args => args[0]);
      expect(verbos).toContain('init');
      // O snippet oficial da Meta tem DUAS linhas; a segunda é a que duplicaria a contagem de
      // visita do cliente. Ela não está aqui, e é isso que "skipPageView" quer dizer.
      expect(verbos).not.toContain('track');
      expect(
        [...document.querySelectorAll('script')].map(s => s.src)
      ).toContain('https://connect.facebook.net/en_US/fbevents.js');
    });

    it('com `install_tags`, configura o GA4 com `send_page_view: false`', () => {
      createTagBridge({
        tracking: {
          ga4_measurement_id: 'G-ABC123',
          install_tags: true,
          event_map: mapaComLead,
        },
      })('chatspx_lead', {});

      const configs = window.dataLayer.filter(e => e?.[0] === 'config');
      expect(configs[0][1]).toBe('G-ABC123');
      expect(configs[0][2]).toEqual({ send_page_view: false });
    });

    it('não instala o pixel que JÁ está na página — instalar de novo é disparar duas vezes', () => {
      window.fbq = fakeFbq(['222']);
      createTagBridge({
        tracking: {
          meta_pixel_id: '222',
          install_tags: true,
          event_map: mapaComLead,
        },
      })('chatspx_lead', {});

      expect(document.querySelectorAll('script')).toHaveLength(0);
      const verbos = window.fbq.mock.calls.map(([verbo]) => verbo);
      expect(verbos).not.toContain('init');
    });
  });

  // ── O `gtag` do cliente continua funcionando (RC2, T-C4.5, T-C4.6) ────────────────────────
  describe('Google', () => {
    it('dispara com `send_to`, no `gtag` que já existe — sem reatribuí-lo', () => {
      const gtagDoCliente = vi.fn();
      window.gtag = gtagDoCliente;
      window.dataLayer = [['config', 'G-ABC123']];

      createTagBridge({
        tracking: { ga4_measurement_id: 'G-ABC123', event_map: mapaComLead },
      })('chatspx_lead', { value: 5 });

      expect(window.gtag).toBe(gtagDoCliente);
      expect(gtagDoCliente).toHaveBeenCalledWith('event', 'generate_lead', {
        value: 5,
        send_to: 'G-ABC123',
      });
    });

    it('Google Ads vai como `conversion` para o `send_to` do rótulo', () => {
      window.gtag = vi.fn();
      window.dataLayer = [['config', 'G-ABC123']];

      createTagBridge({
        tracking: {
          ga4_measurement_id: 'G-ABC123',
          google_ads_send_to: 'AW-999/abc',
          event_map: mapaComLead,
        },
      })('chatspx_lead', { value: 5, currency: 'BRL' }, 'uuid-9');

      expect(window.gtag).toHaveBeenCalledWith('event', 'conversion', {
        send_to: 'AW-999/abc',
        value: 5,
        currency: 'BRL',
        transaction_id: 'uuid-9',
      });
    });
  });

  // ── Consentimento (T-C7.3, bloco 5.09) ────────────────────────────────────────────────────
  describe('o gate de consentimento vem ANTES do disparo', () => {
    it('com tudo negado, nenhuma tag dispara — mas o `dataLayer` recebe', () => {
      window.fbq = fakeFbq(['222']);
      window.gtag = vi.fn();
      window.dataLayer = [['config', 'G-ABC123']];

      createTagBridge({
        tracking: {
          meta_pixel_id: '222',
          ga4_measurement_id: 'G-ABC123',
          event_map: mapaComLead,
        },
        isAllowed: () => false,
      })('chatspx_lead', {});

      expect(window.fbq).not.toHaveBeenCalled();
      expect(window.gtag).not.toHaveBeenCalled();
      expect(
        window.dataLayer.filter(e => e?.event === 'chatspx_lead')
      ).toHaveLength(1);
    });

    it('separa os dois propósitos: analytics concedido não libera anúncio', () => {
      window.fbq = fakeFbq(['222']);
      window.gtag = vi.fn();
      window.dataLayer = [['config', 'G-ABC123']];

      createTagBridge({
        tracking: {
          meta_pixel_id: '222',
          ga4_measurement_id: 'G-ABC123',
          event_map: mapaComLead,
        },
        isAllowed: proposito => proposito === 'analytics_storage',
      })('chatspx_lead', {});

      expect(window.fbq).not.toHaveBeenCalled();
      expect(window.gtag).toHaveBeenCalledWith(
        'event',
        'generate_lead',
        expect.objectContaining({ send_to: 'G-ABC123' })
      );
    });
  });

  // ── PII (RC5) e robustez (T-C4.8) ─────────────────────────────────────────────────────────
  describe('o que nunca sai, e o que nunca quebra', () => {
    it('descarta PII antes do `dataLayer` e antes do `fbq`', () => {
      window.fbq = fakeFbq(['222']);

      createTagBridge({
        tracking: { meta_pixel_id: '222', event_map: mapaComLead },
      })('chatspx_lead', {
        lead_source: 'web_widget',
        email: 'ana@exemplo.com.br',
        phone_number: '+5565999',
      });

      expect(JSON.stringify(window.dataLayer)).not.toContain('ana@exemplo');
      expect(JSON.stringify(window.fbq.mock.calls)).not.toContain('+5565999');
      expect(window.dataLayer[0]).toEqual({
        event: 'chatspx_lead',
        lead_source: 'web_widget',
      });
    });

    it('`withoutPii` é rasa e preserva o resto', () => {
      expect(withoutPii({ EMAIL: 'x', value: 3 })).toEqual({ value: 3 });
    });

    it('NÃO lança quando a tag do cliente explode — e não escreve no console', () => {
      window.fbq = fakeFbq(['222']);
      window.fbq.mockImplementation(() => {
        throw new Error('tag de terceiro quebrada');
      });

      expect(() =>
        createTagBridge({
          tracking: { meta_pixel_id: '222', event_map: mapaComLead },
        })('chatspx_lead', {})
      ).not.toThrow();
      semRuidoNoConsole();
    });

    it('NÃO lança sem nome de evento', () => {
      expect(() => createTagBridge({ tracking: {} })('')).not.toThrow();
      expect(window.dataLayer).toHaveLength(0);
    });
  });

  // ── Detecção (T-C4.2) e mapa ──────────────────────────────────────────────────────────────
  describe('detecção do que já existe', () => {
    it('lê os pixels do estado do próprio `fbevents.js`, e tolera a ausência dele', () => {
      expect(metaPixelsOnPage()).toEqual([]);
      window.fbq = fakeFbq(['1', '2']);
      expect(metaPixelsOnPage()).toEqual(['1', '2']);
    });

    it('varre o `dataLayer` por `[config, ID]` — inclusive quando é `arguments`', () => {
      window.dataLayer = [];
      // É assim que o `gtag()` empurra: o objeto `arguments`, não um array.
      (function empurrar() {
        // eslint-disable-next-line prefer-rest-params
        window.dataLayer.push(arguments);
      })('config', 'G-XYZ');

      expect(ga4ConfigsOnPage()).toEqual(['G-XYZ']);
    });

    it('as instalações não lançam em ambiente hostil', () => {
      expect(() => installMetaPixel('1')).not.toThrow();
      expect(() => installGoogleTag('G-1')).not.toThrow();
    });
  });

  describe('routeFor lê as duas formas de `event_map` que existem hoje', () => {
    it('a forma rica da tela (5.06)', () => {
      expect(routeFor(mapaComLead, 'chatspx_lead')).toEqual({
        enabled: true,
        meta: 'Lead',
        ga4: 'generate_lead',
      });
    });

    it('a forma string do schema de gravação (5.01) vale para os dois destinos', () => {
      expect(routeFor({ chatspx_lead: 'Lead' }, 'chatspx_lead')).toEqual({
        enabled: true,
        meta: 'Lead',
        ga4: 'Lead',
      });
    });

    it('evento fora do mapa não vai a destino nenhum', () => {
      expect(routeFor({}, 'chatspx_lead')).toBeNull();
    });
  });
});
