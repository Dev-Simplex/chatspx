import Cookies from 'js-cookie';
import { IFrameHelper } from '../sdk/IFrameHelper';
import {
  getBubbleView,
  getDarkMode,
  getWidgetStyle,
} from '../sdk/settingsHelper';
import { mergeSnippetConfig } from '../sdk/snippetConfig';
import { camposSobrescritosPeloSite } from '../sdk/appearance';
import {
  publishDefaults,
  updateConsent,
  consentState,
} from '../sdk/tracking/consent';
import {
  computeHashForUserData,
  getUserCookieName,
  hasUserKeys,
} from '../sdk/cookieHelpers';
import {
  addClasses,
  removeClasses,
  restoreWidgetInDOM,
} from '../sdk/DOMHelpers';
import { setCookieWithDomain } from '../sdk/cookieHelpers';
import { SDK_SET_BUBBLE_VISIBILITY } from 'shared/constants/sharedFrameEvents';
import { enfileirar } from '../sdk/preBootQueue';
import { captureOrigin } from '../sdk/tracking/capture';
import { dispatchWindowEvent } from 'shared/helpers/CustomEventHelper';
import { CHATWOOT_ERROR } from '../widget/constants/sdkEvents';

/**
 * Bloco 5.16 — o formato do nome de evento, verificado NO NAVEGADOR.
 *
 * AS TRÊS REGRAS DO CONTRATO NUMA EXPRESSÃO SÓ (`docs/tracking/contrato-de-eventos.md` §1):
 * prefixo `chatspx_`, `snake_case`, e no máximo 40 caracteres — que é limite do GA4, não
 * preferência nossa. O `{0,32}` É o limite de 40: `chatspx_` já gasta 8. Escrever assim, em
 * vez de um `if` de comprimento separado, custa menos bytes no arquivo com teto (A13) e
 * ainda deixa as três regras visíveis num lugar só.
 *
 * O servidor as reaplica em `TrackingEvent` — este arquivo não é a autoridade, é o aviso
 * ANTECIPADO (garantia 2 do bloco 1.23: a validação é imediata). Sem ele, o `chatspxLead` que
 * o integrador digitou errado voltaria 422 de dentro de um `catch` que conta e não mostra, e
 * ele ficaria olhando um evento que some sem dizer por quê.
 */
const NOME_DE_EVENTO = /^chatspx_[a-z0-9_]{0,32}$/;

// A chave de IDEMPOTÊNCIA de uma chamada de `track()`. Ela vira `dedup_key` no servidor e
// colide no índice único de 5.03: o reenvio da MESMA requisição (falha de rede) devolve o
// mesmo `event_id`; uma segunda chamada de `track()` traz chave nova e é fato novo. Sem ela a
// derivação padrão usaria `occurred_at.to_i`, e dois `track()` no mesmo segundo virariam um.
//
// `randomUUID` não existe em contexto inseguro (http) nem em navegador antigo, e widget em
// site http existe. O reserva não precisa ser criptográfico: só precisa distinguir duas
// chamadas do MESMO visitante, e a `dedup_key` do servidor já é prefixada pelo `source_id`.
const chaveDoEvento = () =>
  window.crypto?.randomUUID?.() ||
  Date.now().toString(36) + Math.random().toString(36).slice(2);

/**
 * Contrato dos métodos de DADOS da API pública — bloco 1.23.
 *
 * Três garantias, e cada uma existe por um defeito medido:
 *
 * 1. NUNCA LANÇA DE FORMA SÍNCRONA. Um container do GTM executa as tags em
 *    sequência no mesmo contexto: um `throw` numa tag impede as seguintes de
 *    rodar. Hoje `setUser({}, …)` derruba o resto do container. Aqui o erro vira
 *    `Promise` rejeitada, que não interrompe ninguém.
 * 2. A VALIDAÇÃO É IMEDIATA, o despacho é que espera. Adiar a validação junto
 *    com o envio faria o erro de digitação do integrador aparecer 300 ms depois,
 *    desligado da linha que o causou.
 * 3. RETORNA `Promise` QUE RESOLVE QUANDO A MENSAGEM SAIU DE FATO — inclusive
 *    quando ela ficou na fila pré-boot. É o que permite ao integrador encadear
 *    (`.then`) em vez de adivinhar com `setTimeout`.
 */
// O SDK "deixar de ser mudo" inclui não engolir o próprio erro. Sem isto, um
// integrador com a chave errada não recebe sinal nenhum — que é o defeito que
// este bloco fecha, não um log esquecido.
//
// O CONSOLE NÃO ERA SINAL SUFICIENTE, e isso foi medido: `console.error` sai no
// navegador do VISITANTE, e quem integra por GTM não está lá. O sinal precisa
// chegar onde o site já escuta — `chatwoot:error` é o evento de `window` que o
// painel emite desde sempre (`IFrameHelper.events.error`), e agora os erros da
// própria API pública entram pelo mesmo nome, sem contrato novo para aprender.
//
// O QUE VIAJA NO EVENTO: o MÉTODO e o MOTIVO. Nada do que o integrador passou.
// O `window` do site é legível por qualquer script de terceiro da página (regra
// RC5 do plano 25) — o argumento de `setUser` é PII por definição, e ele não
// entra aqui nem dentro do objeto de erro.
//
// `method` É O DISCRIMINADOR, e ele está aqui de propósito. O mesmo nome de
// evento agora carrega DUAS formas: a do painel (`IFrameHelper.events.error`,
// que repassa o corpo do erro do servidor) e esta. Um evento com duas formas e
// nenhuma maneira de distingui-las é o defeito da §12.7 outra vez — quem
// escuta precisa poder decidir sem adivinhar. `detail.method` existe só nesta,
// e é o que o site testa para saber qual das duas chegou.
const reportarErro = (nome, erro) => {
  // eslint-disable-next-line no-console
  console.error(`[chatwoot] ${nome}:`, erro);
  dispatchWindowEvent({
    eventName: CHATWOOT_ERROR,
    data: { method: nome, message: erro?.message || String(erro) },
  });
};

const chamadaDeDados = (nome, validar, despachar) => {
  let promessa;
  try {
    // `validar?.()` e nao `validar()`: METODO SEM VALIDACAO E CASO LEGITIMO — `setConsent` e
    // `updateConsent` (5.09) nao tem o que validar, e passavam `undefined` aqui. O `validar()`
    // cru lancava `TypeError` dentro do try, virava `Promise.reject`, e `enfileirar(despachar)`
    // NUNCA era chamado: os dois metodos rejeitavam sempre e o consentimento nunca era publicado.
    // Medido em navegador: `setConsent({analytics_storage:'granted'})` deixava o estado em
    // `denied` e o `dataLayer` sem nenhuma entrada de consent. Um site com CMP que aceita ficava
    // com a medicao inteira desligada, em silencio.
    validar?.();
    promessa = enfileirar(despachar, nome);
  } catch (erro) {
    promessa = Promise.reject(erro);
  }

  promessa.catch(erro => reportarErro(nome, erro));

  // A LINHA ACIMA NÃO É DECORATIVA, e a ordem importa.
  //
  // O aceite pede "nenhuma exceção não capturada", e uma `Promise` rejeitada que
  // ninguém observa É uma: o navegador dispara `unhandledrejection`, que vai
  // parar no rastreador de erros do CLIENTE como se o site dele tivesse um bug.
  // Quem integra por GTM chama `setUser(...)` e não encadeia nada — é o caso
  // comum, não o descuidado.
  //
  // Anexar um handler aqui marca a rejeição como tratada e ainda reporta o erro
  // no console. Devolvemos a promessa ORIGINAL, não a derivada do `catch`: assim
  // quem quiser tratar continua podendo (`.catch` do integrador funciona), e
  // quem não quiser não polui o console alheio.
  return promessa;
};

const runSDK = ({ baseUrl, websiteToken }) => {
  if (window.$chatwoot) {
    return;
  }

  // Bloco 2.14. O snippet mostra um link de contato alternativo quando o
  // bundle não carrega — e um dos gatilhos dele é um PRAZO, porque parte dos
  // bloqueadores de conteúdo apenas descarta a requisição sem disparar
  // `onerror`. Em rede muito lenta esse prazo produz falso positivo: o link
  // aparece e, segundos depois, o SDK chega. Chamar `hide()` aqui é o que
  // impede o link de conviver com um widget que passou a funcionar.
  //
  // `?.` em tudo de propósito: o snippet antigo, já colado no site de clientes
  // que existem hoje, NÃO define `chatwootFallback`. Uma chamada direta
  // quebraria o widget deles no primeiro deploy.
  window.chatwootFallback?.hide?.();

  // Bloco 5.08 — a CAPTURA de origem, e ela é eager por necessidade, não por descuido.
  //
  // O aceite é "chega por anúncio, navega 5 páginas e só então abre o chat". Quando o chat
  // abre, `location.search` já não tem o `gclid` há cinco páginas e o referrer já é interno:
  // se a captura esperasse a abertura, a origem já estaria perdida — e não há como
  // recuperá-la depois. Por isso ela roda aqui, no boot de toda página, e por isso o resto
  // do coletor (cookies, `_fbc`, `client_id`) fica num artefato buscado sob demanda.
  //
  // Não lança e não bloqueia: ver `sdk/tracking/capture.js`.
  captureOrigin();

  // if this is a Rails Turbo app
  document.addEventListener('turbo:before-render', event => {
    // when morphing the page, this typically happens on reload like events
    // say you update a "Customer" on a form and it reloads the page
    // We have already added data-turbo-permananent to true. This
    // will ensure that the widget it preserved
    // Read more about morphing here: https://turbo.hotwired.dev/handbook/page_refreshes#morphing
    // and peristing elements here: https://turbo.hotwired.dev/handbook/building#persisting-elements-across-page-loads
    if (event.detail.renderMethod === 'morph') return;

    restoreWidgetInDOM(event.detail.newBody);
  });

  if (window.Turbolinks) {
    document.addEventListener('turbolinks:before-render', event => {
      restoreWidgetInDOM(event.data.newBody);
    });
  }

  // if this is an astro app
  document.addEventListener('astro:before-swap', event =>
    restoreWidgetInDOM(event.newDocument.body)
  );

  // Bloco 5.18 — configuracao tambem pode vir por `data-*` no proprio snippet. Identidade e
  // credencial NAO: o snippet e HTML, aparece no view-source e entra em cache de CDN. A recusa e
  // ALTA E VISIVEL — recusa silenciosa faria o integrador achar que configurou.
  const snippetEl =
    document.currentScript ||
    document.querySelector('script[data-chatspx-snippet]') ||
    document.getElementById('chatwoot-sdk');
  const { settings: chatwootSettings, rejected: recusadasDoSnippet } =
    mergeSnippetConfig(window.chatwootSettings || {}, snippetEl?.dataset || {});

  if (recusadasDoSnippet.length) {
    // eslint-disable-next-line no-console
    console.warn(
      `[ChatSPX] O snippet trouxe ${recusadasDoSnippet.length} atributo(s) que NAO viajam por data-*: ` +
        `${recusadasDoSnippet.join(', ')}. Identidade e credencial so pela API JS (setUser/updateUser), ` +
        'porque o snippet e HTML publico.'
    );
  }
  let locale = chatwootSettings.locale;
  let baseDomain = chatwootSettings.baseDomain;

  if (chatwootSettings.useBrowserLanguage) {
    locale = window.navigator.language.replace('-', '_');
  }

  // Bloco 3.18 — QUAIS chaves de aparencia este site esta sobrescrevendo.
  //
  // Medido AQUI, e nao no `loaded`, porque este e o unico instante em que o
  // objeto do site ainda existe separado do estado do widget: dali a tres linhas
  // `chatwootSettings.position` e `window.$chatwoot.position` viram a mesma
  // coisa, e "quem escreveu este valor" deixa de ser respondivel.
  //
  // A lista serve a duas coisas, nesta ordem: ela diz ao `IFrameHelper` quais
  // campos o banco NAO pode preencher (a regra de precedencia), e vira o aviso
  // de override na tela de aparencia — que ate aqui lia uma chave que ninguem
  // escrevia (`widget_appearance_overrides`), e por isso ficava sempre inerte.
  const appearanceOverrides = camposSobrescritosPeloSite(chatwootSettings);

  window.$chatwoot = {
    baseUrl,
    baseDomain,
    appearanceOverrides,
    hasLoaded: false,
    hideMessageBubble: chatwootSettings.hideMessageBubble || false,
    isOpen: false,
    position: chatwootSettings.position === 'left' ? 'left' : 'right',
    websiteToken,
    locale,
    useBrowserLanguage: chatwootSettings.useBrowserLanguage || false,
    type: getBubbleView(chatwootSettings.type),
    launcherTitle: chatwootSettings.launcherTitle || '',
    showPopoutButton: chatwootSettings.showPopoutButton || false,
    showUnreadMessagesDialog: chatwootSettings.showUnreadMessagesDialog ?? true,
    widgetStyle: getWidgetStyle(chatwootSettings.widgetStyle) || 'standard',
    resetTriggered: false,
    darkMode: getDarkMode(chatwootSettings.darkMode),
    welcomeTitle: chatwootSettings.welcomeTitle || '',
    welcomeDescription: chatwootSettings.welcomeDescription || '',
    availableMessage: chatwootSettings.availableMessage || '',
    unavailableMessage: chatwootSettings.unavailableMessage || '',
    enableFileUpload: chatwootSettings.enableFileUpload,
    enableEmojiPicker: chatwootSettings.enableEmojiPicker ?? true,
    enableEndConversation: chatwootSettings.enableEndConversation ?? true,

    toggle(state) {
      IFrameHelper.events.toggleBubble(state);
    },

    /**
     * `open()` e `close()` IDEMPOTENTES — item 37 da §8.1, que o plano manda
     * entrar junto deste bloco.
     *
     * Até aqui a API pública só tinha `toggle`, e `toggle` obriga quem chama a
     * saber o estado atual. Numa automação — GTM, teste E2E, botão do site —
     * ninguém sabe: chamar duas vezes fechava o que se queria abrir. Os 20
     * widgets globais do corpus medido têm os dois métodos; nós não tínhamos.
     *
     * Idempotente aqui quer dizer o que a palavra quer dizer: chamar `open()`
     * com o painel já aberto não faz nada, e não é erro.
     */
    open() {
      if (window.$chatwoot.isOpen) return;
      IFrameHelper.events.toggleBubble('open');
    },

    close() {
      if (!window.$chatwoot.isOpen) return;
      IFrameHelper.events.toggleBubble('close');
    },

    toggleBubbleVisibility(visibility) {
      let widgetElm = document.querySelector('.woot--bubble-holder');
      let widgetHolder = document.querySelector('.woot-widget-holder');
      if (visibility === 'hide') {
        addClasses(widgetHolder, 'woot-widget--without-bubble');
        addClasses(widgetElm, 'woot-hidden');
        window.$chatwoot.hideMessageBubble = true;
      } else if (visibility === 'show') {
        removeClasses(widgetElm, 'woot-hidden');
        removeClasses(widgetHolder, 'woot-widget--without-bubble');
        window.$chatwoot.hideMessageBubble = false;
      }
      IFrameHelper.sendMessage(SDK_SET_BUBBLE_VISIBILITY, {
        hideMessageBubble: window.$chatwoot.hideMessageBubble,
      });
    },

    popoutChatWindow() {
      IFrameHelper.events.popoutChatWindow({
        baseUrl: window.$chatwoot.baseUrl,
        websiteToken: window.$chatwoot.websiteToken,
        locale,
      });
    },

    // Bloco 5.17 — LEGADO, mantido intacto: `setUser` SUBSTITUI o contato. Para corrigir um campo
    // sem apagar os outros, use `updateUser`. O metodo continua funcionando exatamente como antes;
    // o que mudou neste bloco foi o hash de dedupe, que agora enxerga telefone, empresa e o resto.
    setUser(identifier, user) {
      return chamadaDeDados(
        'setUser',
        () => {
          if (
            typeof identifier !== 'string' &&
            typeof identifier !== 'number'
          ) {
            throw new Error('Identifier should be a string or a number');
          }
          if (!hasUserKeys(user)) {
            throw new Error(
              'User object should have one of the keys [avatar_url, email, name, phone_number]'
            );
          }
        },
        () => {
          // O cookie de dedupe é gravado no DESPACHO, não na chamada: se a
          // mensagem ficou na fila e o visitante saiu da página antes do boot,
          // gravar o hash antes faria a próxima visita achar que já identificou.
          const userCookieName = getUserCookieName();
          const hashToBeStored = computeHashForUserData({ identifier, user });
          if (hashToBeStored === Cookies.get(userCookieName)) {
            return;
          }
          window.$chatwoot.identifier = identifier;
          window.$chatwoot.user = user;
          IFrameHelper.sendMessage('set-user', { identifier, user });
          setCookieWithDomain(userCookieName, hashToBeStored, { baseDomain });
        }
      );
    },

    // Bloco 5.09 — consentimento. Publica a linha de base do Consent Mode v2. O padrao e NEGADO
    // em tudo: sob LGPD o tratamento precisa de base legal ANTES de acontecer, e disparo que ja
    // saiu do navegador nao volta.
    setConsent(consent = {}) {
      return chamadaDeDados('setConsent', undefined, () =>
        publishDefaults(consent)
      );
    },

    // Bloco 5.09 — a decisao do visitante, depois que a CMP responde. Se o default ainda nao tiver
    // sido publicado, ele vai ANTES: update sem linha de base a plataforma le como desconhecido.
    updateConsent(consent = {}) {
      return chamadaDeDados('updateConsent', undefined, () =>
        updateConsent(consent)
      );
    },

    getConsent() {
      return consentState();
    },

    // Bloco 5.17 — o verbo que MESCLA: campo que voce nao mandar NAO e apagado.
    updateUser(identifier, user) {
      return chamadaDeDados(
        'updateUser',
        () => {
          if (
            typeof identifier !== 'string' &&
            typeof identifier !== 'number'
          ) {
            throw new Error('Identifier should be a string or a number');
          }
          if (!hasUserKeys(user)) {
            throw new Error(
              'User object should have one of the keys [avatar_url, email, name, phone_number]'
            );
          }
        },
        () => {
          // Sem cookie de dedupe aqui de proposito: `updateUser` existe para corrigir um campo, e
          // deduplicar por hash faria a segunda correcao do mesmo campo virar silencio.
          window.$chatwoot.identifier = identifier;
          window.$chatwoot.user = { ...(window.$chatwoot.user || {}), ...user };
          IFrameHelper.sendMessage('update-user', { identifier, user });
        }
      );
    },

    // Bloco 5.17 — getters. Ler o que foi identificado era possivel so espiando
    // `window.$chatwoot.user`, que e estado interno; agora ha leitura declarada.
    getUser() {
      return window.$chatwoot.user || null;
    },

    getIdentifier() {
      return window.$chatwoot.identifier || null;
    },

    /**
     * Item 39 da §8.1 — o contador de não lidas na API pública, que o plano
     * manda entrar junto deste bloco. 15 dos 20 widgets globais do corpus
     * medido têm; nós tínhamos o número só como CLASSE CSS na bolha
     * (`unread-notification`), legível por ninguém.
     *
     * Quem esconde a bolha (`hideMessageBubble`) e desenha o próprio badge no
     * site precisa exatamente disto: o número, sem depender do nosso enfeite.
     *
     * `?? 0` e não um campo no literal do `$chatwoot`: antes da primeira
     * mensagem do painel não existe contagem nenhuma, e "ainda não sei" e
     * "zero não lidas" valem a mesma resposta para quem vai desenhar um badge.
     * A leitura nunca devolve `undefined`.
     */
    getUnreadCount() {
      return window.$chatwoot.unreadMessageCount ?? 0;
    },

    /**
     * Bloco 5.16 — `track(name, properties)`: o evento tipado do site do cliente.
     *
     * UMA chamada, dois destinos, e é isso que o aceite mede: o fato entra no registro
     * server-side (que gera o `event_id`) e sai no `dataLayer` — pela mesma chamada, sem o
     * integrador precisar escrever `dataLayer.push` do lado dele nem saber que existe um.
     *
     * O VOCABULÁRIO É O DO TRACKING (`chatspx_*`), não o do barramento interno. `pushEvent`
     * continua existindo, intocado, falando o vocabulário antigo — os dois verbos não se
     * misturam porque não são o mesmo contrato.
     *
     * PII NÃO PASSA: o servidor recusa `email`/`phone_number` e afins em `properties` com 422,
     * e a ponte de tags descarta as mesmas chaves antes de publicar. O `window` do site é
     * legível por qualquer script de terceiro da página (regra RC5).
     */
    track(name, properties = {}) {
      return chamadaDeDados(
        'track',
        () => {
          if (typeof name !== 'string' || !NOME_DE_EVENTO.test(name)) {
            throw new Error(
              'Event name should match /^chatspx_[a-z0-9_]{0,32}$/ (e.g. chatspx_orcamento_pedido)'
            );
          }
          if (properties && typeof properties !== 'object') {
            throw new Error('Properties should be an object');
          }
        },
        () =>
          IFrameHelper.sendMessage('track-event', {
            name,
            properties: properties || {},
            eventKey: chaveDoEvento(),
          })
      );
    },

    setCustomAttributes(customAttributes = {}) {
      return chamadaDeDados(
        'setCustomAttributes',
        () => {
          if (!customAttributes || !Object.keys(customAttributes).length) {
            throw new Error('Custom attributes should have atleast one key');
          }
        },
        () =>
          IFrameHelper.sendMessage('set-custom-attributes', {
            customAttributes,
          })
      );
    },

    deleteCustomAttribute(customAttribute = '') {
      return chamadaDeDados(
        'deleteCustomAttribute',
        () => {
          if (!customAttribute) {
            throw new Error('Custom attribute is required');
          }
        },
        () =>
          IFrameHelper.sendMessage('delete-custom-attribute', {
            customAttribute,
          })
      );
    },

    setConversationCustomAttributes(customAttributes = {}) {
      return chamadaDeDados(
        'setConversationCustomAttributes',
        () => {
          if (!customAttributes || !Object.keys(customAttributes).length) {
            throw new Error('Custom attributes should have atleast one key');
          }
        },
        () =>
          IFrameHelper.sendMessage('set-conversation-custom-attributes', {
            customAttributes,
          })
      );
    },

    deleteConversationCustomAttribute(customAttribute = '') {
      return chamadaDeDados(
        'deleteConversationCustomAttribute',
        () => {
          if (!customAttribute) {
            throw new Error('Custom attribute is required');
          }
        },
        () =>
          IFrameHelper.sendMessage('delete-conversation-custom-attribute', {
            customAttribute,
          })
      );
    },

    setLabel(label = '') {
      return chamadaDeDados(
        'setLabel',
        () => {
          // sem validação: rótulo vazio é no-op no painel, não erro
        },
        () => IFrameHelper.sendMessage('set-label', { label })
      );
    },

    removeLabel(label = '') {
      return chamadaDeDados(
        'removeLabel',
        () => {
          // sem validação: rótulo vazio é no-op no painel, não erro
        },
        () => IFrameHelper.sendMessage('remove-label', { label })
      );
    },

    setLocale(localeToBeUsed = 'en') {
      IFrameHelper.sendMessage('set-locale', { locale: localeToBeUsed });
    },

    setColorScheme(darkMode = 'light') {
      IFrameHelper.sendMessage('set-color-scheme', {
        darkMode: getDarkMode(darkMode),
      });
    },

    reset() {
      if (window.$chatwoot.isOpen) {
        IFrameHelper.events.toggleBubble();
      }

      Cookies.remove('cw_conversation');
      Cookies.remove(getUserCookieName());

      const iframe = IFrameHelper.getAppFrame();
      iframe.src = IFrameHelper.getUrl({
        baseUrl: window.$chatwoot.baseUrl,
        websiteToken: window.$chatwoot.websiteToken,
      });

      window.$chatwoot.resetTriggered = true;
    },
  };

  IFrameHelper.createFrame({
    baseUrl,
    websiteToken,
  });
};

window.chatwootSDK = {
  run: runSDK,
};
