import Cookies from 'js-cookie';
import {
  addClasses,
  loadCSS,
  removeClasses,
  onLocationChangeListener,
} from './DOMHelpers';
import {
  body,
  widgetHolder,
  createBubbleHolder,
  createBubbleIcon,
  bubbleSVG,
  chatBubble,
  closeBubble,
  bubbleHolder,
  onClickChatBubble,
  onBubbleClick,
  setBubbleText,
  addUnreadClass,
  removeUnreadClass,
} from './bubbleHelpers';
import { WIDGET_TOKEN_NAMES } from '../widget/helpers/IframeEventHelper';
import { dispatchWindowEvent } from 'shared/helpers/CustomEventHelper';
import {
  CHATWOOT_ERROR,
  CHATWOOT_POSTBACK,
  CHATWOOT_READY,
} from '../widget/constants/sdkEvents';
import { SET_USER_ERROR } from '../widget/constants/errorTypes';
import { getUserCookieName, setCookieWithDomain } from './cookieHelpers';
import {
  getAlertAudio,
  initOnEvents,
} from 'shared/helpers/AudioNotificationHelper';
import { isFlatWidgetStyle } from './settingsHelper';
import { popoutChatWindow } from '../widget/helpers/popoutHelper';
import addHours from 'date-fns/addHours';

const updateAuthCookie = (cookieContent, baseDomain = '') =>
  setCookieWithDomain('cw_conversation', cookieContent, {
    baseDomain,
  });

// Bloco 1.03 — os tokens do servidor pintam o launcher, que vive no host.
//
// O valor chega por `postMessage`, e `postMessage` é superfície de entrada:
// escrever a string recebida direto num `style` daria a quem conseguisse forjar
// a mensagem uma primitiva de CSS no documento do CLIENTE. Por isso passa por
// aqui: nome tem de estar na lista fechada de `WIDGET_TOKEN_NAMES`, e valor tem
// de ser hex de 3/6/8 dígitos ou uma referência `var(--w-…)` — o alfabeto
// inteiro que o `WidgetTokens` do servidor sabe produzir.
const SAFE_TOKEN_VALUE =
  /^(#[0-9a-f]{3}|#[0-9a-f]{6}|#[0-9a-f]{8}|var\(--w-[a-z-]+\))$/i;

export const applyWidgetTokens = (element, tokens = {}) => {
  if (!element?.style) return {};
  const applied = {};
  WIDGET_TOKEN_NAMES.forEach(name => {
    const value = tokens[name];
    if (typeof value !== 'string' || !SAFE_TOKEN_VALUE.test(value.trim())) {
      return;
    }
    element.style.setProperty(name, value.trim());
    applied[name] = value.trim();
  });
  return applied;
};

const updateCampaignReadStatus = baseDomain => {
  const expireBy = addHours(new Date(), 1);
  setCookieWithDomain('cw_snooze_campaigns_till', Number(expireBy), {
    expires: expireBy,
    baseDomain,
  });
};

export const IFrameHelper = {
  getUrl({ baseUrl, websiteToken }) {
    return `${baseUrl}/widget?website_token=${websiteToken}`;
  },
  createFrame: ({ baseUrl, websiteToken }) => {
    if (IFrameHelper.getAppFrame()) {
      return;
    }

    loadCSS();
    const iframe = document.createElement('iframe');
    const cwCookie = Cookies.get('cw_conversation');
    let widgetUrl = IFrameHelper.getUrl({ baseUrl, websiteToken });
    if (cwCookie) {
      widgetUrl = `${widgetUrl}&cw_conversation=${cwCookie}`;
    }
    iframe.src = widgetUrl;
    iframe.allow =
      'camera;microphone;fullscreen;display-capture;picture-in-picture;clipboard-write;';
    iframe.id = 'chatwoot_live_chat_widget';
    iframe.style.visibility = 'hidden';

    let holderClassName = `woot-widget-holder woot--hide woot-elements--${window.$chatwoot.position}`;
    if (window.$chatwoot.hideMessageBubble) {
      holderClassName += ` woot-widget--without-bubble`;
    }
    if (isFlatWidgetStyle(window.$chatwoot.widgetStyle)) {
      holderClassName += ` woot-widget-holder--flat`;
    }

    addClasses(widgetHolder, holderClassName);
    widgetHolder.id = 'cw-widget-holder';
    widgetHolder.dataset.turboPermanent = true;
    widgetHolder.appendChild(iframe);
    body.appendChild(widgetHolder);
    IFrameHelper.initPostMessageCommunication();
    IFrameHelper.initWindowSizeListener();
    IFrameHelper.preventDefaultScroll();
  },
  getAppFrame: () => document.getElementById('chatwoot_live_chat_widget'),
  getBubbleHolder: () => document.getElementsByClassName('woot--bubble-holder'),
  sendMessage: (key, value) => {
    const element = IFrameHelper.getAppFrame();
    const targetOrigin = element?.src
      ? new URL(element.src).origin
      : window.location.origin;
    element.contentWindow.postMessage(
      `chatwoot-widget:${JSON.stringify({ event: key, ...value })}`,
      targetOrigin
    );
  },
  initPostMessageCommunication: () => {
    window.onmessage = e => {
      if (
        typeof e.data !== 'string' ||
        e.data.indexOf('chatwoot-widget:') !== 0
      ) {
        return;
      }
      const message = JSON.parse(e.data.replace('chatwoot-widget:', ''));
      if (typeof IFrameHelper.events[message.event] === 'function') {
        IFrameHelper.events[message.event](message);
      }
    };
  },
  initWindowSizeListener: () => {
    window.addEventListener('resize', () => IFrameHelper.toggleCloseButton());
  },
  preventDefaultScroll: () => {
    widgetHolder.addEventListener('wheel', event => {
      const deltaY = event.deltaY;
      const contentHeight = widgetHolder.scrollHeight;
      const visibleHeight = widgetHolder.offsetHeight;
      const scrollTop = widgetHolder.scrollTop;

      if (
        (scrollTop === 0 && deltaY < 0) ||
        (visibleHeight + scrollTop === contentHeight && deltaY > 0)
      ) {
        event.preventDefault();
      }
    });
  },

  setFrameHeightToFitContent: (extraHeight, isFixedHeight) => {
    const iframe = IFrameHelper.getAppFrame();
    const updatedIframeHeight = isFixedHeight ? `${extraHeight}px` : '100%';

    if (iframe)
      iframe.setAttribute('style', `height: ${updatedIframeHeight} !important`);
  },

  setupAudioListeners: () => {
    const { baseUrl = '' } = window.$chatwoot;
    getAlertAudio(baseUrl, { type: 'widget', alertTone: 'ding' }).then(() =>
      initOnEvents.forEach(event => {
        document.removeEventListener(
          event,
          IFrameHelper.setupAudioListeners,
          false
        );
      })
    );
  },

  events: {
    loaded: message => {
      updateAuthCookie(message.config.authToken, window.$chatwoot.baseDomain);
      window.$chatwoot.hasLoaded = true;
      const campaignsSnoozedTill = Cookies.get('cw_snooze_campaigns_till');
      IFrameHelper.sendMessage('config-set', {
        locale: window.$chatwoot.locale,
        position: window.$chatwoot.position,
        hideMessageBubble: window.$chatwoot.hideMessageBubble,
        showPopoutButton: window.$chatwoot.showPopoutButton,
        widgetStyle: window.$chatwoot.widgetStyle,
        darkMode: window.$chatwoot.darkMode,
        showUnreadMessagesDialog: window.$chatwoot.showUnreadMessagesDialog,
        campaignsSnoozedTill,
        welcomeTitle: window.$chatwoot.welcomeTitle,
        welcomeDescription: window.$chatwoot.welcomeDescription,
        availableMessage: window.$chatwoot.availableMessage,
        unavailableMessage: window.$chatwoot.unavailableMessage,
        enableFileUpload: window.$chatwoot.enableFileUpload,
        enableEmojiPicker: window.$chatwoot.enableEmojiPicker,
        enableEndConversation: window.$chatwoot.enableEndConversation,
      });
      IFrameHelper.onLoad({
        widgetColor: message.config.channelConfig.widgetColor,
        // Mesma fonte que o `<style>` do painel: `WidgetTokens` no servidor.
        // O host NÃO recalcula contraste — ele consome o resultado.
        tokens: message.config.tokens || message.config.channelConfig.tokens,
      });
      IFrameHelper.toggleCloseButton();

      if (window.$chatwoot.user) {
        IFrameHelper.sendMessage('set-user', window.$chatwoot.user);
      }

      window.playAudioAlert = () => {};

      initOnEvents.forEach(e => {
        document.addEventListener(e, IFrameHelper.setupAudioListeners, false);
      });

      if (!window.$chatwoot.resetTriggered) {
        dispatchWindowEvent({ eventName: CHATWOOT_READY });
      }
    },
    error: ({ errorType, data }) => {
      dispatchWindowEvent({ eventName: CHATWOOT_ERROR, data: data });

      if (errorType === SET_USER_ERROR) {
        Cookies.remove(getUserCookieName());
      }
    },
    onEvent({ eventIdentifier: eventName, data }) {
      dispatchWindowEvent({ eventName, data });
    },
    setBubbleLabel(message) {
      setBubbleText(window.$chatwoot.launcherTitle || message.label);
    },

    setAuthCookie({ data: { widgetAuthToken } }) {
      updateAuthCookie(widgetAuthToken, window.$chatwoot.baseDomain);
    },

    setCampaignReadOn() {
      updateCampaignReadStatus(window.$chatwoot.baseDomain);
    },

    postback(data) {
      dispatchWindowEvent({
        eventName: CHATWOOT_POSTBACK,
        data,
      });
    },

    toggleBubble: state => {
      let bubbleState = {};
      if (state === 'open') {
        bubbleState.toggleValue = true;
      } else if (state === 'close') {
        bubbleState.toggleValue = false;
      }

      onBubbleClick(bubbleState);
    },

    popoutChatWindow: ({ baseUrl, websiteToken, locale }) => {
      const cwCookie = Cookies.get('cw_conversation');
      window.$chatwoot.toggle('close');
      popoutChatWindow(baseUrl, websiteToken, locale, cwCookie);
    },

    closeWindow: () => {
      onBubbleClick({ toggleValue: false });
      removeUnreadClass();
    },

    onBubbleToggle: isOpen => {
      IFrameHelper.sendMessage('toggle-open', { isOpen });
      if (isOpen) {
        IFrameHelper.pushEvent('webwidget.triggered');
      }
    },
    onLocationChange: ({ referrerURL, referrerHost }) => {
      IFrameHelper.sendMessage('change-url', {
        referrerURL,
        referrerHost,
      });
    },
    updateIframeHeight: message => {
      const { extraHeight = 0, isFixedHeight } = message;

      IFrameHelper.setFrameHeightToFitContent(extraHeight, isFixedHeight);
    },

    setUnreadMode: () => {
      addUnreadClass();
      onBubbleClick({ toggleValue: true });
    },

    resetUnreadMode: () => removeUnreadClass(),
    handleNotificationDot: event => {
      if (window.$chatwoot.hideMessageBubble) {
        return;
      }

      const bubbleElement = document.querySelector('.woot-widget-bubble');
      if (
        event.unreadMessageCount > 0 &&
        !bubbleElement.classList.contains('unread-notification')
      ) {
        addClasses(bubbleElement, 'unread-notification');
      } else if (event.unreadMessageCount === 0) {
        removeClasses(bubbleElement, 'unread-notification');
      }
    },

    closeChat: () => {
      onBubbleClick({ toggleValue: false });
    },

    playAudio: () => {
      window.playAudioAlert();
    },
  },
  pushEvent: eventName => {
    IFrameHelper.sendMessage('push-event', { eventName });
  },

  onLoad: ({ widgetColor, tokens }) => {
    const iframe = IFrameHelper.getAppFrame();
    iframe.style.visibility = '';
    iframe.setAttribute('id', `chatwoot_live_chat_widget`);

    // O painel (iframe) já pintou com estes valores no 1º byte de HTML. Aqui
    // eles entram no documento do host, hospedados nos DOIS elementos que são
    // nossos — nunca no `:root` do site do cliente, que é documento alheio e
    // onde um `--w-brand` do próprio site nos sobrescreveria.
    // Degradação para aba aberta ANTES do deploy do 1.02: `chatwootWebChannel`
    // vem sem `tokens`. Antes deste bloco isso não importava, porque o inline
    // pintava a bolha de qualquer jeito; agora que o inline saiu, sem isto o
    // lançador ficaria SEM cor de fundo até o próximo reload.
    // Repassar `widgetColor` cru para `--w-brand` não é calcular contraste — é
    // usar a cor da inbox que o host já conhece. Quem decide a cor SOBRE ela
    // segue sendo o servidor; na ausência dele vale o fallback do `SDK_CSS`.
    const effectiveTokens =
      tokens && tokens['--w-brand']
        ? tokens
        : { ...tokens, '--w-brand': widgetColor };

    const applied = applyWidgetTokens(widgetHolder, effectiveTokens);
    IFrameHelper.appliedTokens = applied;

    if (IFrameHelper.getBubbleHolder().length) {
      return;
    }
    createBubbleHolder(window.$chatwoot.hideMessageBubble);
    applyWidgetTokens(bubbleHolder, effectiveTokens);
    onLocationChangeListener();

    let className = 'woot-widget-bubble';
    let closeBtnClassName = `woot-elements--${window.$chatwoot.position} woot-widget-bubble woot--close woot--hide`;

    if (isFlatWidgetStyle(window.$chatwoot.widgetStyle)) {
      className += ' woot-widget-bubble--flat';
      closeBtnClassName += ' woot-widget-bubble--flat';
    }

    // O que era `isWidgetColorLighter(widgetColor)` — brilho ponderado
    // 299/587/114 com limiar 225, que não é WCAG e não verifica se o resultado
    // atinge razão alguma. Agora a decisão já vem tomada do servidor: se o
    // texto sobre a marca é preto, a marca é "clara". Zero fórmula aqui.
    if (applied['--w-on-brand'] === '#000000') {
      className += ' woot-widget-bubble-color--lighter';
      closeBtnClassName += ' woot-widget-bubble-color--lighter';
    }

    const chatIcon = createBubbleIcon({
      className,
      path: bubbleSVG,
      target: chatBubble,
    });

    addClasses(closeBubble, closeBtnClassName);

    // NÃO existe mais `chatIcon.style.background = …` aqui, e a ausência é o
    // ponto do bloco 1.05. O estilo inline vencia a folha sem `!important`, o
    // que mascarava o `#2dc46f` cravado em `.woot-widget-bubble:hover` —
    // literal morto que ressuscitaria no instante em que o inline saísse.
    // Agora a cor vem de `background: var(--w-brand)` no `SDK_CSS`, herdando o
    // token que `applyWidgetTokens` acabou de escrever no `bubbleHolder`, e o
    // `:hover` usa a MESMA var. Uma fonte, os dois estados.

    bubbleHolder.appendChild(chatIcon);
    bubbleHolder.appendChild(closeBubble);
    onClickChatBubble();
  },
  toggleCloseButton: () => {
    let isMobile = false;
    if (window.matchMedia('(max-width: 668px)').matches) {
      isMobile = true;
    }
    IFrameHelper.sendMessage('toggle-close-button', { isMobile });
  },
};
