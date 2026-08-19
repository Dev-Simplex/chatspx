import { pushToDataLayer } from './dataLayer';
import { PII_KEYS } from './trackContract';

/**
 * Bloco 5.10 — A PONTE DE TAGS (T-C4.1 a T-C4.10).
 *
 * ── O QUE ESTE ARQUIVO EXISTE PARA IMPEDIR ──────────────────────────────────────────────────
 *
 * Uma página de cliente com dois pixels da Meta — o dele e o da agência — é o caso comum, não o
 * exótico. `fbq('track', 'Lead')` dispara o evento em TODOS os pixels inicializados na página
 * (a própria Meta avisa que isso *"could produce over-firing"*). O cliente vê a conversão contada
 * duas vezes, numa conta que não é a dele, e a decisão de mídia sai de um número mentiroso.
 *
 * Daí as duas regras que dão nome ao bloco:
 *  · **RC3 · Meta**: `fbq('trackSingle', <pixel>, …)` — o evento vai para UM pixel, nomeado.
 *  · **RC3 · Google**: `gtag('event', …, { send_to: <id> })` — idem para GA4 e Ads.
 *
 * E daí o motivo de o `dataLayer` ser o único caminho que vai SEMPRE (RC4): ele não dispara nada,
 * só publica. Quem escuta — o GTM do cliente — decide. Um `push` a mais não vira conversão a mais.
 *
 * ── O QUE ELE EXISTE PARA NÃO QUEBRAR ───────────────────────────────────────────────────────
 *
 * O site é do cliente, e a medição dele já estava lá antes de nós (**RC2**, risco **R9**):
 *  · nada é reatribuído — `window.gtag = window.gtag || …`, nunca `window.gtag = …`;
 *  · nada é instalado sem opt-in explícito (`install_tags`, decisão **Q5**), e quando é, entra
 *    **sem `PageView`** — duplicar o `PageView` do cliente é errar o número que ele mais olha;
 *  · nada lança (T-C4.8): uma exceção dentro de uma tag do GTM **interrompe as tags seguintes do
 *    contêiner**, e o defeito apareceria como "o GTM parou de funcionar depois que instalei o chat";
 *  · nada escreve no console — nem `warn`, nem `error`. "Console limpo" é aceite deste bloco.
 *
 * ── ONDE ELE MORA, E POR QUÊ ────────────────────────────────────────────────────────────────
 *
 * Neste arquivo, que vive no artefato SOB DEMANDA (`public/packs/js/tracking.js`, bloco 5.07(c)),
 * nunca no `sdk.js` — T-C4.9. O `sdk.js` é baixado por 100% dos visitantes de todos os sites de
 * todos os clientes; a ponte só interessa a quem configurou destino.
 *
 * O `pushToDataLayer` é a exceção declarada: ele é eager, mora em `dataLayer.js`, e é o que
 * mantém o modo "somente `dataLayer`" (T-C4.10) alcançável para quem não configurou nada — que é
 * exatamente o cliente que integra por GTM. Ver o cabeçalho daquele arquivo.
 */

/**
 * Os eventos que a Meta reconhece como PADRÃO. A lista existe por causa do aceite "console
 * limpo": `trackSingle` com um nome que não está aqui faz o `fbevents.js` avisar no console do
 * site do cliente que o evento não é padrão. Nome fora da lista vai por `trackSingleCustom`, que
 * é a chamada que a Meta publica para evento próprio — mesmo efeito, sem o aviso.
 */
export const META_STANDARD_EVENTS = Object.freeze([
  'AddPaymentInfo',
  'AddToCart',
  'AddToWishlist',
  'CompleteRegistration',
  'Contact',
  'CustomizeProduct',
  'Donate',
  'FindLocation',
  'InitiateCheckout',
  'Lead',
  'PageView',
  'Purchase',
  'Schedule',
  'Search',
  'StartTrial',
  'SubmitApplication',
  'Subscribe',
  'ViewContent',
]);

/**
 * Copia os parâmetros descartando PII (**RC5**), com a lista de `trackContract.js`.
 *
 * Aqui a PII é DESCARTADA, e não recusada como em `track()`: neste ponto o payload já passou pela
 * porta de entrada, e o que chega vem do nosso próprio widget. Descartar é a última linha antes
 * de o dado virar `dataLayer` — que qualquer script de terceiro da página lê — e antes de virar
 * params do `fbq`, que viajam em claro. O caminho da PII é o servidor, que normaliza e hasheia
 * (bloco 5.11, contrato §6 ponto 3).
 */
export const withoutPii = (properties = {}) =>
  Object.entries(properties || {}).reduce((acc, [chave, valor]) => {
    if (!PII_KEYS.includes(String(chave).toLowerCase())) acc[chave] = valor;
    return acc;
  }, {});

// ─────────────────────────────────────────────────────────────────────────────────────────────
// T-C4.2 — DETECÇÃO DO QUE JÁ EXISTE NA PÁGINA
//
// Antes de instalar qualquer coisa, olhar. Instalar um pixel que já está lá é o caminho mais
// curto para o evento sair duas vezes.
// ─────────────────────────────────────────────────────────────────────────────────────────────

/** Os pixels da Meta já inicializados nesta página, pelo estado que o próprio `fbevents.js` expõe. */
export const metaPixelsOnPage = () => {
  try {
    return (window.fbq?.getState?.()?.pixels || []).map(pixel =>
      String(pixel?.id)
    );
  } catch {
    return [];
  }
};

/**
 * Os Measurement IDs já configurados nesta página, varrendo o `dataLayer` por `['config', ID]`.
 *
 * O `dataLayer` guarda o objeto `arguments` da chamada `gtag(...)`, não um array — por isso a
 * leitura é por índice, e não por `Array.isArray`. É a mesma varredura que a Leadster faz, e ela
 * funciona porque `gtag('config', 'G-XXXX')` é a única forma documentada de configurar o GA4.
 */
export const ga4ConfigsOnPage = () => {
  try {
    return (window.dataLayer || []).reduce((acc, entrada) => {
      if (entrada?.[0] === 'config' && typeof entrada?.[1] === 'string') {
        acc.push(entrada[1]);
      }
      return acc;
    }, []);
  } catch {
    return [];
  }
};

// ─────────────────────────────────────────────────────────────────────────────────────────────
// T-C4.3 — INSTALAÇÃO CONDICIONAL, COM `skipPageView`
//
// Só acontece atrás de `install_tags` (decisão Q5: opt-in explícito, nunca por padrão), e só
// quando a tag NÃO está na página. As duas instalações omitem o `PageView`/`page_view` de
// propósito: a página do cliente já conta a visita dela, e contá-la de novo por nossa conta é
// estragar o número dele para medir o nosso.
// ─────────────────────────────────────────────────────────────────────────────────────────────

const injectScript = src => {
  const script = document.createElement('script');
  script.async = true;
  script.src = src;
  document.head.appendChild(script);
  return script;
};

/**
 * Instala o `fbevents.js` e inicializa o pixel — **sem** `fbq('track', 'PageView')`.
 *
 * O snippet oficial da Meta tem duas linhas: `init` e `track PageView`. A segunda é o que
 * duplicaria a contagem de visita de quem já tem o pixel em outro lugar do site; nós só queremos
 * a primeira. É literalmente o "skipPageView" do T-C4.3.
 */
export const installMetaPixel = pixelId => {
  try {
    if (!window.fbq) {
      const fbq = function chatspxFbq(...args) {
        if (fbq.callMethod) fbq.callMethod.apply(fbq, args);
        else fbq.queue.push(args);
      };
      fbq.push = fbq;
      fbq.loaded = true;
      fbq.version = '2.0';
      fbq.queue = [];
      window.fbq = fbq;
      // `_fbq` é o nome que o snippet oficial da Meta usa, e o `fbevents.js` o procura por esse
      // nome exato — renomear para agradar o linter quebraria a integração de verdade.
      // eslint-disable-next-line no-underscore-dangle
      window._fbq = window._fbq || fbq;
      injectScript('https://connect.facebook.net/en_US/fbevents.js');
    }
    window.fbq('init', pixelId);
    return true;
  } catch {
    return false;
  }
};

/**
 * Instala o `gtag.js` para um Measurement ID — com `send_page_view: false`, que é o
 * `skipPageView` do lado do Google.
 *
 * `window.gtag` é criado só se não existir (**RC2**). Reatribuí-lo apagaria a função que o GTM ou
 * o próprio site já publicou, e com ela toda a medição do cliente.
 */
export const installGoogleTag = measurementId => {
  try {
    window.dataLayer = window.dataLayer || [];
    if (!window.gtag) {
      window.gtag = function chatspxGtag() {
        // eslint-disable-next-line prefer-rest-params
        window.dataLayer.push(arguments);
      };
      injectScript(
        `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(measurementId)}`
      );
      window.gtag('js', new Date());
    }
    window.gtag('config', measurementId, { send_page_view: false });
    return true;
  } catch {
    return false;
  }
};

// ─────────────────────────────────────────────────────────────────────────────────────────────
// O MAPA DE EVENTOS
//
// `event_map` é do cliente: é onde ele diz para qual nome cada evento do ChatSPX vai, em cada
// destino, e quais estão ativos (T-C1.5). A ponte NÃO carrega um mapa de fábrica próprio — o
// default mora na tela (bloco 5.06) e é gravado COMPLETO quando o administrador salva. Uma
// segunda cópia aqui seria uma quarta fonte da verdade, e a que ninguém lembraria de atualizar.
//
// Consequência declarada: evento sem entrada no mapa **não vai a destino nenhum** — só ao
// `dataLayer`. É o comportamento conservador que a decisão Q5 pede, e ele não prejudica quem
// salvou a tela uma vez, porque a tela grava as doze linhas de uma vez.
// ─────────────────────────────────────────────────────────────────────────────────────────────

/**
 * Normaliza a entrada do mapa para `{ enabled, meta, ga4 }`.
 *
 * Aceita as DUAS formas que existem hoje na base, e isso não é generosidade — é uma divergência
 * real, registrada no relatório desta trilha: o schema de gravação (`WidgetTrackingSchema`, bloco
 * 5.01) declara `event_map` como `nome → string`, enquanto a tela (bloco 5.06) grava
 * `nome → { enabled, meta, ga4 }`. Enquanto a arbitragem não escolher uma, a ponte lê as duas em
 * vez de escolher sozinha por um lado; a forma string vale como "este nome, nos dois destinos".
 */
export const routeFor = (eventMap, name) => {
  const entrada = eventMap?.[name];
  if (typeof entrada === 'string' && entrada) {
    return { enabled: true, meta: entrada, ga4: entrada };
  }
  if (entrada && typeof entrada === 'object') {
    return {
      enabled: entrada.enabled !== false,
      meta: entrada.meta || null,
      ga4: entrada.ga4 || null,
    };
  }
  return null;
};

// ─────────────────────────────────────────────────────────────────────────────────────────────
// A PONTE
// ─────────────────────────────────────────────────────────────────────────────────────────────

/**
 * Monta o publicador de eventos para uma inbox.
 *
 * `isAllowed` é INJETADO, e a injeção é a parte que importa: o estado de consentimento (bloco
 * 5.09) vive no módulo eager `tracking/consent.js`, dentro do `sdk.js`. Se este arquivo o
 * importasse, o bundler do artefato sob demanda traria uma SEGUNDA cópia do módulo — com um
 * segundo `state`, que nunca receberia o `setConsent`/`updateConsent` do site. O gate leria
 * sempre o estado inicial e o consentimento viraria decoração. Recebendo a função de fora, o
 * estado continua sendo um só.
 *
 * @param {object}   tracking   a projeção pública de `widget_tracking` (bloco 5.01).
 * @param {function} isAllowed  `(purpose) => boolean`, de `tracking/consent.js` (bloco 5.09).
 * @returns {function} `(name, properties, eventId) => void` — e ela nunca lança.
 */
export const createTagBridge = ({
  tracking = {},
  isAllowed = () => true,
} = {}) => {
  const eventMap = tracking.event_map || {};
  const podeInstalar = tracking.install_tags === true;

  // A resolução de cada destino é feita UMA vez e guardada: varrer o `dataLayer` a cada evento
  // custaria uma passada por um array que, num site com GTM cheio, tem centenas de entradas.
  const resolvido = {};

  const metaPixel = () => {
    if (resolvido.meta === undefined) {
      const pixelId = tracking.meta_pixel_id;
      if (!pixelId) resolvido.meta = null;
      else if (metaPixelsOnPage().includes(String(pixelId)))
        resolvido.meta = pixelId;
      else
        resolvido.meta =
          podeInstalar && installMetaPixel(pixelId) ? pixelId : null;
    }
    return resolvido.meta;
  };

  const ga4Id = () => {
    if (resolvido.ga4 === undefined) {
      const measurementId = tracking.ga4_measurement_id;
      if (!measurementId) resolvido.ga4 = null;
      else if (ga4ConfigsOnPage().includes(measurementId))
        resolvido.ga4 = measurementId;
      else
        resolvido.ga4 =
          podeInstalar && installGoogleTag(measurementId)
            ? measurementId
            : null;
      // `gtag` publicado pelo próprio site (sem `config` para este ID) ainda serve para o
      // `send_to`: é o caso do cliente que gerencia o GA4 pelo GTM.
      if (
        !resolvido.ga4 &&
        measurementId &&
        typeof window.gtag === 'function'
      ) {
        resolvido.ga4 = measurementId;
      }
    }
    return resolvido.ga4;
  };

  const fireMeta = (nomeNoDestino, params, eventId) => {
    const pixelId = metaPixel();
    if (!pixelId || !nomeNoDestino) return;

    const verbo = META_STANDARD_EVENTS.includes(nomeNoDestino)
      ? 'trackSingle'
      : 'trackSingleCustom';
    // O 5º argumento é o que a Meta usa para deduplicar contra o CAPI (bloco 5.13). Só entra
    // quando existe: `{ eventID: undefined }` faria o `fbevents.js` mandar a chave vazia.
    if (eventId)
      window.fbq(verbo, pixelId, nomeNoDestino, params, { eventID: eventId });
    else window.fbq(verbo, pixelId, nomeNoDestino, params);
  };

  const fireGa4 = (nomeNoDestino, params) => {
    const measurementId = ga4Id();
    if (!measurementId || !nomeNoDestino || typeof window.gtag !== 'function')
      return;

    window.gtag('event', nomeNoDestino, { ...params, send_to: measurementId });
  };

  // T-C4.6 — Google Ads. O `send_to` já traz `AW-XXXX/rótulo`, e o nome do evento é sempre
  // `conversion`: é assim que o Ads reconhece a conversão, independentemente de como o evento se
  // chama para nós.
  const fireAds = (params, eventId) => {
    const sendTo = tracking.google_ads_send_to;
    if (!sendTo || typeof window.gtag !== 'function') return;

    window.gtag('event', 'conversion', {
      send_to: sendTo,
      ...(params.value !== undefined ? { value: params.value } : {}),
      ...(params.currency !== undefined ? { currency: params.currency } : {}),
      ...(eventId ? { transaction_id: eventId } : {}),
    });
  };

  return (name, properties = {}, eventId = null) => {
    try {
      if (!name) return;
      const params = withoutPii(properties);

      // SEMPRE, e antes de tudo (RC4). Não depende de consentimento, de mapa nem de destino: o
      // `dataLayer` não entrega nada a lugar nenhum — ele publica, e quem escuta decide. Gatear
      // esta linha deixaria sem evento justamente o cliente que integra por GTM, que é quem não
      // cola Pixel ID nenhum aqui.
      pushToDataLayer({
        event: name,
        ...params,
        ...(eventId ? { event_id: eventId } : {}),
      });

      const rota = routeFor(eventMap, name);
      if (!rota?.enabled) return;

      // T-C7.3 — o gate do consentimento (bloco 5.09) vem ANTES do disparo, nunca depois. Com o
      // modo de consentimento desligado na inbox, `isAllowed` devolve `true` e o produto se
      // comporta como antes do 5.09.
      if (isAllowed('ad_storage')) {
        fireMeta(rota.meta, params, eventId);
        fireAds(params, eventId);
      }
      if (isAllowed('analytics_storage')) fireGa4(rota.ga4, params);
    } catch {
      // T-C4.8. Silêncio é o comportamento correto: um `console.warn` aqui apareceria no console
      // do site do cliente a cada evento, e "console limpo" é aceite deste bloco.
    }
  };
};
