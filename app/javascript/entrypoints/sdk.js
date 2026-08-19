import Cookies from 'js-cookie';
import { IFrameHelper } from '../sdk/IFrameHelper';
import {
  getBubbleView,
  getDarkMode,
  getWidgetStyle,
} from '../sdk/settingsHelper';
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
// eslint-disable-next-line no-console
const reportarErro = (nome, erro) => console.error(`[chatwoot] ${nome}:`, erro);

const chamadaDeDados = (nome, validar, despachar) => {
  let promessa;
  try {
    validar();
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

  const chatwootSettings = window.chatwootSettings || {};
  let locale = chatwootSettings.locale;
  let baseDomain = chatwootSettings.baseDomain;

  if (chatwootSettings.useBrowserLanguage) {
    locale = window.navigator.language.replace('-', '_');
  }

  window.$chatwoot = {
    baseUrl,
    baseDomain,
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
