import { SDK_EVENT_CONTRACT } from 'widget/constants/sdkEvents';

/**
 * A PONTE DE TAGS — bloco 5.10 (T-C4.1 a T-C4.10).
 *
 * ── O QUE ELA EXISTE PARA IMPEDIR ───────────────────────────────────────────────────────
 *
 * Uma pagina de cliente costuma ter MAIS DE UM pixel: o dele, o da agencia, o do
 * marketplace. `fbq('track', 'Lead', …)` dispara em TODOS eles. O cliente ve a conversao
 * do chat aparecer numa conta de anuncio que nao e a dele, e decide midia sobre um numero
 * que nunca aconteceu. `trackSingle` nomeia o pixel; `send_to` nomeia a propriedade do
 * Google. E por isso que os dois existem, e o aceite ("pagina com 3 pixels: o evento nao
 * vaza") e a medida disso.
 *
 * O `dataLayer` vai SEMPRE, e a razao e de natureza, nao de configuracao: ele nao dispara
 * nada. E um array do proprio navegador; publicar nele nao manda byte nenhum para fora, e
 * quem escuta (o GTM do cliente) decide o que fazer — com o gate de consentimento DELE. Por
 * isso ele sobrevive ate ao consentimento negado, enquanto `fbq` e `gtag` nao.
 *
 * ── A JUNCAO QUE QUASE VIROU DEFEITO SILENCIOSO ─────────────────────────────────────────
 *
 * `isAllowed` e INJETADO. Ele NAO e importado de `./consent` — e nao pode ser.
 *
 * `entrypoints/sdk.js` importa `consent.js` e o build o inlina no `sdk.js`; este arquivo
 * vive no artefato `tracking.js`, que e outro bundle. Importar `consent.js` aqui criaria uma
 * SEGUNDA copia do modulo, com um SEGUNDO objeto de estado. O visitante chamaria
 * `$chatwoot.setConsent({ ad_storage: 'granted' })`, a copia do `sdk.js` seria atualizada, e
 * esta copia continuaria em "negado" para sempre. Os dois lados ficariam verdes no teste
 * unitario e o gate estaria morto em producao. `specs/tagsBundleIsolation.spec.js` guarda
 * essa regra lendo o codigo deste arquivo.
 *
 * ── ONDE ELE MORA, E POR QUE ────────────────────────────────────────────────────────────
 *
 * No artefato sob demanda (T-C4.9), junto do coletor de 5.08. O `sdk.js` tem teto (A13) e e
 * baixado por 100% dos visitantes de todos os sites; a ponte so e util para quem configurou
 * tracking. O que fica no lado eager e uma linha de registro em `IFrameHelper`.
 */

/**
 * As chaves que o servidor recusa em `properties` (`TrackingEvent::PII_KEYS`), repetidas
 * aqui porque este arquivo roda no navegador e nao alcanca o Ruby.
 *
 * A duplicacao e guardada: `specs/tags.spec.js` cruza esta lista com a do modelo lendo o
 * arquivo Ruby, e reprova se uma das duas ganhar uma chave que a outra nao tem. Sem isso, a
 * proxima chave de PII entraria de um lado so — e o lado que faltasse seria justamente o que
 * publica no `window` do cliente.
 */
export const PII_KEYS = Object.freeze([
  'em',
  'ph',
  'fn',
  'ln',
  'email',
  'phone',
  'phone_number',
  'first_name',
  'last_name',
]);

/** Copia sem nenhuma chave de PII, em profundidade. Nao muta a entrada. */
export const semPii = valor => {
  if (Array.isArray(valor)) return valor.map(semPii);
  if (!valor || typeof valor !== 'object') return valor;

  return Object.entries(valor).reduce((acc, [chave, item]) => {
    if (!PII_KEYS.includes(String(chave).toLowerCase()))
      acc[chave] = semPii(item);
    return acc;
  }, {});
};

/**
 * T-C4.2 — o que JA existe na pagina.
 *
 * `fbq.getState().pixels` e a leitura que a propria biblioteca da Meta expoe. Ela pode nao
 * existir (versao antiga, stub de bloqueador, `fbq` que e so uma funcao vazia), e por isso
 * tudo aqui e defensivo: a resposta errada e `false`, nunca uma excecao no site do cliente.
 */
export const metaPixelInicializado = pixelId => {
  try {
    const pixels = window.fbq?.getState?.().pixels;
    return (
      Array.isArray(pixels) &&
      pixels.some(p => String(p?.id) === String(pixelId))
    );
  } catch {
    return false;
  }
};

/** T-C4.2 — varredura do `dataLayer` por `['config', <measurement id>]`, o padrao do gtag. */
export const ga4Configurado = measurementId => {
  try {
    return (window.dataLayer || []).some(
      item =>
        Array.isArray(item) && item[0] === 'config' && item[1] === measurementId
    );
  } catch {
    return false;
  }
};

/**
 * T-C4.3 — INSTALAR A TAG QUE FALTA. O unico caminho deste arquivo que escreve no `window`
 * do cliente, e por isso o unico que exige opt-in explicito (decisao Q5).
 *
 * ── A PRECEDENCIA, que e a razao de a funcao existir ────────────────────────────────────
 *
 *   1. Pixel configurado E `fbq` na pagina  -> `trackSingle` naquele id. Nada e instalado.
 *   2. Pixel configurado e `fbq` AUSENTE    -> instalar, sem `PageView`, e so com opt-in.
 *   3. Sempre, e independente de 1 e 2      -> `dataLayer.push`.
 *
 * Sem o caminho 2, o cliente que cola o Pixel ID na nossa tela e nao tem o pixel no site
 * NAO RECEBE NADA na Meta — e nada avisa. Era o buraco de aceite que este bloco tinha.
 *
 * ── POR QUE `skipPageView` E O CORACAO DISTO ────────────────────────────────────────────
 *
 * O snippet publicado pela Meta termina em `fbq('init', id)` SEGUIDO de
 * `fbq('track', 'PageView')`. Rodar os dois numa pagina que ja mede tráfego dobra a contagem
 * de visitas do cliente — o numero do painel dele sobe sem que nada tenha acontecido, e a
 * culpa cai no chat. Aqui o `init` sai e o `PageView` NAO: e literalmente a linha que nao
 * escrevemos. O equivalente do Google e `send_page_view: false` no `config`.
 *
 * ── E POR QUE TUDO E ADITIVO ────────────────────────────────────────────────────────────
 *
 * `if (typeof window.fbq === 'function') return true` antes de qualquer escrita. Sobrescrever
 * o `fbq` ou o `gtag` do cliente e a forma mais rapida de quebrar a medicao do site inteiro
 * (R9): a fila que ele ja tinha some, e as tags do container dele passam a chamar a nossa
 * funcao. Quem ja tem a tag nao ganha outra — ganha `trackSingle`/`send_to` na que existe.
 */

const FBEVENTS_SRC = 'https://connect.facebook.net/en_US/fbevents.js';
const GTAG_SRC = 'https://www.googletagmanager.com/gtag/js?id=';

/** Insere o script assincrono, do jeito que os dois fornecedores publicam. Nunca lanca. */
const injetarScript = src => {
  const script = document.createElement('script');
  script.async = true;
  script.src = src;
  const primeiro = document.getElementsByTagName('script')[0];
  if (primeiro && primeiro.parentNode)
    primeiro.parentNode.insertBefore(script, primeiro);
  else document.head.appendChild(script);
};

/**
 * O snippet da Meta, menos o `PageView`.
 *
 * Devolve `true` quando ha um `fbq` utilizavel ao fim — o que inclui o caso "ja existia", que
 * e o que torna esta funcao idempotente sem guardar estado de modulo nenhum. Estado de modulo
 * aqui seria um segundo lugar para a verdade divergir do `window`.
 */
export const instalarMetaPixel = pixelId => {
  if (!pixelId) return false;
  if (typeof window.fbq === 'function') return true;

  /* eslint-disable prefer-rest-params, func-names, no-underscore-dangle --
     Este bloco e o snippet PUBLICADO pela Meta, com uma unica alteracao nossa (a ausencia do
     `PageView`). `arguments`, a funcao anonima e o nome `_fbq` sao contrato do `fbevents.js`,
     que le a fila que fica aqui. "Modernizar" qualquer um dos tres e uma mudanca cujo unico
     lugar de descobrir o erro e a conta de anuncio do cliente. */
  const fila = function () {
    // eslint-disable-next-line no-unused-expressions
    fila.callMethod
      ? fila.callMethod.apply(fila, arguments)
      : fila.queue.push(arguments);
  };
  window.fbq = fila;
  if (!window._fbq) window._fbq = fila;
  /* eslint-enable prefer-rest-params, func-names, no-underscore-dangle */
  fila.push = fila;
  fila.loaded = true;
  fila.version = '2.0';
  fila.queue = [];

  injetarScript(FBEVENTS_SRC);
  window.fbq('init', pixelId);
  // AQUI nao vem `window.fbq('track', 'PageView')`. E o `skipPageView` do T-C4.3.

  return true;
};

/**
 * O snippet do Google, com `send_page_view: false` em todo `config`.
 *
 * Recebe a LISTA de destinos porque um `gtag` serve os dois: o GA4 (`G-…`) e a conta do
 * Google Ads (`AW-…`, a parte do `send_to` antes da barra). Instalar so o GA4 deixaria a
 * conversao de Ads sem transporte — o mesmo silencio que o T-C4.3 existe para acabar.
 */
export const instalarGoogleTag = destinos => {
  const alvos = (destinos || []).filter(Boolean);
  if (!alvos.length) return false;
  if (typeof window.gtag === 'function') return true;

  window.dataLayer = window.dataLayer || [];
  /* eslint-disable prefer-rest-params, func-names -- mesma razao do `fbq`: o `gtag.js` le o
     `dataLayer` e distingue um objeto `arguments` de um array comum. */
  window.gtag = function () {
    window.dataLayer.push(arguments);
  };
  /* eslint-enable prefer-rest-params, func-names */

  injetarScript(`${GTAG_SRC}${encodeURIComponent(alvos[0])}`);
  window.gtag('js', new Date());
  // `send_page_view: false` em TODOS: e o `skipPageView` do lado do Google.
  alvos.forEach(id => window.gtag('config', id, { send_page_view: false }));

  return true;
};

/** `AW-123456789/rotulo` -> `AW-123456789`. E a conta; o rotulo pertence a conversao. */
export const contaDoAds = sendTo =>
  sendTo ? String(sendTo).split('/')[0] || null : null;

/**
 * A entrada do `event_map` para um evento, normalizada.
 *
 * DUAS FORMAS, e a tolerancia e deliberada — as duas pontas do produto escrevem diferente:
 *
 *   · OBJETO `{ enabled, meta, ga4 }` — o que a tela de 5.06 grava (`DEFAULT_EVENT_MAP`);
 *   · STRING `"Lead"` — o que o schema de 5.01 declara
 *     (`WidgetTrackingSchema::SCHEMA['event_map'].additionalProperties.type == 'string'`).
 *
 * As duas nao podem estar certas, e a divergencia esta ESCALADA no relatorio desta trilha —
 * nao arbitrada aqui. O que esta ponte faz e nao quebrar com nenhuma das duas: a string e
 * lida como "renomeie este evento assim nos dois destinos", que e a unica leitura que o
 * schema comporta.
 *
 * AUSENTE devolve `null`, e `null` significa SOMENTE DATALAYER (T-C4.10). E por isso que o
 * padrao de fabrica e seguro sem nenhum `if` especial: quem nao configurou o mapa nao tem
 * mapa, e quem nao tem mapa nao tem tag nossa disparando no site dele. Vale igual para o
 * evento proprio do site (5.16), que nunca esta no mapa.
 */
export const entradaDoMapa = (eventMap, nome) => {
  const bruto = eventMap?.[nome];
  if (bruto === undefined || bruto === null) return null;
  if (typeof bruto === 'string')
    return { enabled: true, meta: bruto, ga4: bruto };
  if (typeof bruto !== 'object') return null;

  return {
    enabled: bruto.enabled !== false,
    meta: bruto.meta ?? null,
    ga4: bruto.ga4 ?? null,
  };
};

// Cada destino num `try` proprio: T-C4.8. Uma excecao dentro de uma tag do GTM quebra as
// tags SEGUINTES do container — o site do cliente para de medir e a culpa cai no chat. E se
// o `fbq` de um terceiro explodir, o `gtag` e o `dataLayer` ainda tem de sair.
const protegido = fn => {
  try {
    fn();
  } catch {
    // Silencio deliberado: "console limpo" e aceite deste bloco. O diagnostico do que nao
    // saiu e do bloco 5.14 (painel por inbox), que le o registro server-side — nao um
    // `console.warn` no navegador de um visitante que nunca vai ler.
  }
};

const numero = valor =>
  typeof valor === 'number' && Number.isFinite(valor) ? valor : null;

/**
 * @param {object}   opcoes
 * @param {object}   opcoes.tracking  a projecao publica de `widget_tracking` (5.01)
 * @param {function} opcoes.isAllowed `(proposito) => boolean` — o gate de 5.09, INJETADO
 */
export const createTagsBridge = ({
  tracking = {},
  isAllowed = () => true,
} = {}) => {
  const pixelId = tracking.meta_pixel_id || null;
  const measurementId = tracking.ga4_measurement_id || null;
  const adsSendTo = tracking.google_ads_send_to || null;

  /**
   * T-C4.3 — o opt-in, vindo da projecao publica de 5.01 (`WidgetTrackingSchema`).
   *
   * AUSENTE E DESLIGADO, e nao ha valor de fabrica em lugar nenhum: quem nunca marcou o
   * interruptor nao tem a chave, e `undefined` cai no `!` abaixo. E a decisao Q5 escrita como
   * ausencia de codigo, que e a unica forma dela que nao pode ser desfeita por engano.
   */
  const installTags = tracking.install_tags || {};

  /**
   * "Ha um `fbq`/`gtag` utilizavel?" — e, se nao houver, "posso criar um?".
   *
   * As duas sao chamadas DEPOIS do gate de consentimento de cada disparo, nunca antes.
   * Injetar `fbevents.js` ou `gtag.js` e uma requisicao a um terceiro que le cookie: fazer
   * isso antes do consentimento seria vazar o visitante justamente pelo caminho que o bloco
   * 5.09 existe para fechar — e o `isAllowed` nao teria como desfazer.
   */
  const garantirMeta = () => {
    if (typeof window.fbq === 'function') return true;
    if (!installTags.meta) return false;
    return instalarMetaPixel(pixelId);
  };

  const garantirGoogle = () => {
    if (typeof window.gtag === 'function') return true;
    if (!installTags.google) return false;
    return instalarGoogleTag([measurementId, contaDoAds(adsSendTo)]);
  };

  const paraDataLayer = (nome, params, eventId) =>
    protegido(() => {
      window.dataLayer = window.dataLayer || [];
      window.dataLayer.push({
        event: nome,
        ...params,
        ...(eventId ? { chatspx_event_id: eventId } : {}),
      });
    });

  // T-C4.4 — `trackSingle` nomeia o pixel. `eventID` e o que permite a Meta reconhecer que
  // este disparo e o MESMO fato que o CAPI de 5.11 vai mandar, dentro da janela de 48 h.
  const paraMeta = (entrada, params, eventId) =>
    protegido(() => {
      if (!pixelId || !entrada?.enabled || !entrada.meta) return;
      if (!isAllowed('ad_storage')) return;
      // Ordem deliberada: o gate vem ANTES de `garantirMeta`, senao o opt-in de instalar
      // passaria por cima do consentimento negado.
      if (!garantirMeta()) return;

      window.fbq('trackSingle', pixelId, entrada.meta, params, {
        ...(eventId ? { eventID: eventId } : {}),
      });
    });

  // T-C4.5 — `send_to` nomeia a propriedade. Sem ele o `gtag` dispara em TODAS as
  // propriedades configuradas na pagina, inclusive as que nao sao do cliente.
  const paraGa4 = (entrada, params) =>
    protegido(() => {
      if (!measurementId || !entrada?.enabled || !entrada.ga4) return;
      if (!isAllowed('analytics_storage')) return;
      if (!garantirGoogle()) return;

      window.gtag('event', entrada.ga4, { ...params, send_to: measurementId });
    });

  /**
   * T-C4.6 — a conversao do Google Ads.
   *
   * O GATILHO E O VALOR, e a escolha esta declarada no relatorio: T-C4.6 diz COMO disparar,
   * nao QUANDO. Ha um unico `google_ads_send_to` por inbox, entao disparar em todo evento
   * habilitado mandaria "abriu o painel" para a mesma acao de conversao que "fechou negocio"
   * — e a conta de anuncio do cliente passaria a otimizar para o evento errado. Valor
   * presente e o unico sinal, no dado que temos, de que o fato vale uma conversao.
   *
   * `transaction_id` recebe o `event_id`: e o campo pelo qual o Ads deduplica.
   */
  const paraGoogleAds = (entrada, params, eventId) =>
    protegido(() => {
      if (!adsSendTo || !entrada?.enabled) return;
      if (!isAllowed('ad_storage')) return;

      const valor = numero(params.value);
      if (valor === null) return;
      // `garantirGoogle` por ultimo: sem valor nao ha conversao, e sem conversao nao ha
      // razao para injetar script de terceiro na pagina de quem nao vai disparar nada.
      if (!garantirGoogle()) return;

      window.gtag('event', 'conversion', {
        send_to: adsSendTo,
        value: valor,
        ...(params.currency ? { currency: params.currency } : {}),
        ...(eventId ? { transaction_id: eventId } : {}),
      });
    });

  const dispatch = (nome, properties, eventId) => {
    if (!nome) return;

    const params = semPii(properties || {});
    const entrada = entradaDoMapa(tracking.event_map, nome);

    paraDataLayer(nome, params, eventId);
    paraMeta(entrada, params, eventId);
    paraGa4(entrada, params);
    paraGoogleAds(entrada, params, eventId);
  };

  return {
    /** Caminho de 5.05 e 5.16: o fato ja nasceu com nome `chatspx_` e com `event_id`. */
    onTrackingEvent: ({ name, properties, eventId } = {}) =>
      dispatch(name, properties, eventId),

    /**
     * Caminho de 5.04: o evento de `window` chega ao host e ESTE arquivo faz a traducao para
     * o vocabulario de tracking, usando o mapa 1:1 que `sdkEvents.js` declara. Evento com
     * `tracking: null` (sinal interno) e evento fora do contrato (os sete antigos) nao viram
     * evento de tracking — a ausencia esta declarada la, e le-se dela.
     */
    onWindowEvent: (eventName, data) => {
      const nome = SDK_EVENT_CONTRACT[eventName]?.tracking;
      if (!nome) return;
      dispatch(nome, data, null);
    },

    metaPixelInicializado: () => metaPixelInicializado(pixelId),
    ga4Configurado: () => ga4Configurado(measurementId),

    /** T-C4.3 — o que o opt-in autoriza nesta inbox. Leitura, nao efeito. */
    instalacaoAutorizada: () => ({
      meta: Boolean(installTags.meta),
      google: Boolean(installTags.google),
    }),
  };
};
