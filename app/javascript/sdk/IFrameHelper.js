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
  resolveLauncherIcon,
  bubbleSVG,
  chatBubble,
  closeBubble,
  bubbleHolder,
  onClickChatBubble,
  onBubbleClick,
  setBubbleText,
  setBubbleAccessibleName,
  addUnreadClass,
  removeUnreadClass,
} from './bubbleHelpers';
import { WIDGET_TOKEN_NAMES } from '../widget/helpers/IframeEventHelper';
import { drenar } from './preBootQueue';
import { montarTeaser } from './teaser';
import { dispatchWindowEvent } from 'shared/helpers/CustomEventHelper';
import {
  CHATWOOT_ERROR,
  CHATWOOT_POSTBACK,
  CHATWOOT_READY,
  CHATWOOT_RESET_COMPLETED,
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
import { createTitleFlasher } from './titleFlasher';
import { loadCollector } from './tracking/loader';

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

  // Bloco 4.06 — o teaser. Fica aqui, e não no `entrypoints/sdk.js`, porque
  // depende do `bubbleHolder`, que só existe depois do `onLoad`.
  desmontarTeaser: null,

  montarTeaserSeConfigurado(holder) {
    const canal = window.chatwootWebChannel || {};
    const gatilhos = canal.widgetTriggers || {};

    // CONTRATO DO 4.04, ao pé da letra: `enabled` ausente significa que o SDK
    // NÃO DISPARA NADA. Ausência não é `true` — é silêncio, e silêncio aqui é
    // não incomodar o visitante de uma conta que nunca configurou isto.
    if (gatilhos.enabled !== true) return;

    // O nível vem resolvido do servidor (`resolved_widget_approach`), que já
    // aplica o padrão `bold` e já derruba `aggressive` para `bold` no mobile.
    // O host não recalcula política — consome a decisão, como no 1.03 com a cor.
    const nivel = IFrameHelper.nivelDeAbordagem(gatilhos);

    IFrameHelper.desmontarTeaser = montarTeaser({
      holder,
      canal,
      nivel,
      baseDomain: window.$chatwoot.baseDomain,
      aoAbrir: () => IFrameHelper.events.toggleBubble('open'),
    });
  },

  // O nível efetivo desta visita. Em 4.06 é o configurado; o bloco 4.19
  // acrescenta a degradação por familiaridade por cima deste ponto único.
  nivelDeAbordagem(gatilhos) {
    const ehCelular = window.matchMedia('(max-width: 667px)').matches;
    const configurado = ehCelular
      ? gatilhos.approach_mobile || gatilhos.approach
      : gatilhos.approach;
    return configurado || 'bold';
  },
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
  // Origem confiável do lado do SITE: aqui ela é exata — a única janela de quem
  // temos que aceitar mensagem é o iframe que nós mesmos criamos, e a origem
  // dele é a do próprio `src`. Sem esta comparação, qualquer frame ou aba com
  // referência a esta janela conseguia dirigir o widget por `postMessage`.
  isTrustedFrameOrigin: origin => {
    const element = IFrameHelper.getAppFrame();
    if (!element?.src) return false;
    try {
      return origin === new URL(element.src).origin;
    } catch (error) {
      return false;
    }
  },
  onPostMessage: e => {
    if (
      typeof e.data !== 'string' ||
      e.data.indexOf('chatwoot-widget:') !== 0
    ) {
      return;
    }
    if (!IFrameHelper.isTrustedFrameOrigin(e.origin)) {
      return;
    }
    let message;
    try {
      message = JSON.parse(e.data.replace('chatwoot-widget:', ''));
    } catch (error) {
      // JSON quebrado com o prefixo certo: descartar em silêncio é melhor que
      // deixar a exceção subir para o window.onerror da página do cliente.
      return;
    }
    if (typeof IFrameHelper.events[message.event] === 'function') {
      IFrameHelper.events[message.event](message);
    }
  },
  initPostMessageCommunication: () => {
    // `window.onmessage =` sequestrava o handler de mensagem do site do cliente
    // (uma única propriedade, um único dono). `addEventListener` convive.
    window.addEventListener('message', IFrameHelper.onPostMessage);
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

  /**
   * Bloco 4.11 — o som e OPT-IN por inbox, e o piscar do titulo e ligado.
   *
   * O som toca hoje por padrao: qualquer visitante que interaja com a pagina
   * faz o SDK baixar o mp3, e toda mensagem de agente toca. A decisao de
   * produto e o contrario — som desligado por default, opcao por inbox — e a
   * politica mora AQUI, no lado que toca, e nao so no widget que pede: se um
   * dia alguem esquecer o guard do outro lado, o som continua desligado.
   */
  notificationSoundEnabled: false,
  titleFlasher: createTitleFlasher(),

  isNotificationSoundEnabled: channelConfig =>
    Array.isArray(channelConfig?.enabledFeatures) &&
    channelConfig.enabledFeatures.includes('notification_sound'),

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
      // Bloco 1.23 — a partir daqui existe quem escute do outro lado da ponte.
      // Tudo o que o site chamou antes do painel montar sai agora, na ordem de
      // chegada. Antes disto, essas mensagens eram postadas para um iframe sem
      // ouvinte e sumiam em silêncio.
      const drenados = drenar();
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
        // O ícone do lançador (3.19) sai de `widget_appearance`, que viaja dentro
        // do `channelConfig`. Não é cor: é modo, URL e rótulo. Quem pinta continua
        // sendo `tokens`, acima — uma fonte só para a cor do lançador.
        channelConfig: message.config.channelConfig,
      });
      IFrameHelper.toggleCloseButton();

      // RE-HIDRATAÇÃO, não fila. Serve ao caso em que o iframe recarrega com o
      // SDK já identificado (`reset()`, navegação que recria o frame): o painel
      // novo precisa saber quem é o visitante.
      //
      // Duas correções do bloco 1.23 aqui:
      //
      // 1. NÃO REENVIA O QUE A FILA ACABOU DE ENVIAR. Sem esta guarda, um
      //    `setUser` chamado antes do boot sairia DUAS vezes — que é exatamente
      //    a armadilha da segunda fila descrita na §12.1 do PLANO-MESTRE.
      // 2. O FORMATO ESTAVA ERRADO. Esta linha mandava `window.$chatwoot.user`
      //    cru, enquanto `setUser` manda `{ identifier, user }`. O painel recebia
      //    um payload sem `identifier` — o mesmo evento com dois formatos,
      //    dependendo de quem o emitiu.
      if (window.$chatwoot.user && !drenados.includes('setUser')) {
        IFrameHelper.sendMessage('set-user', {
          identifier: window.$chatwoot.identifier,
          user: window.$chatwoot.user,
        });
      }

      window.playAudioAlert = () => {};

      IFrameHelper.notificationSoundEnabled =
        IFrameHelper.isNotificationSoundEnabled(message.config?.channelConfig);

      // O mp3 so e baixado quando a inbox pediu som: sem opt-in nao ha nem
      // listener nem request — o visitante nao paga bytes por um recurso que
      // ninguem ligou.
      if (IFrameHelper.notificationSoundEnabled) {
        initOnEvents.forEach(e => {
          document.addEventListener(e, IFrameHelper.setupAudioListeners, false);
        });
      }

      IFrameHelper.titleFlasher.attach();

      // T-I4.5 (bloco 5.04) — o `reset()` era MUDO.
      //
      // O que existia era só a supressão: `resetTriggered` impedia o segundo
      // `chatwoot:ready`, e o site que chamou `reset()` não recebia sinal
      // nenhum de que a operação terminou. Quem precisava encadear alguma coisa
      // depois do reset (identificar o novo visitante, por exemplo) só tinha
      // `setTimeout` para adivinhar quando.
      //
      // Agora o reset ANUNCIA a conclusão, e a flag é limpa. Limpar importa:
      // sem isso ela ficava `true` para sempre depois do primeiro reset, e
      // qualquer recarga posterior do iframe deixava de emitir `chatwoot:ready`
      // — a supressão valia uma vez e durava a vida da página.
      if (window.$chatwoot.resetTriggered) {
        window.$chatwoot.resetTriggered = false;
        dispatchWindowEvent({ eventName: CHATWOOT_RESET_COMPLETED });
      } else {
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
      // O nome acessível do lançador vem traduzido do painel (bloco 1.06). Cai
      // no rótulo do texto expandido quando o painel é de uma versão anterior e
      // ainda não manda `ariaLabel`.
      //
      // `launcherIconLabel` (3.19) entra entre a opção pública e o genérico do
      // painel: é o nome que o admin escreveu para a foto do lançador, e é mais
      // específico que "Abrir o chat" — mas menos que o que o cliente escreveu no
      // próprio snippet. Sem ele nesta cadeia, a ponte apagaria o nome da pessoa
      // milissegundos depois de o lançador aparecer com a foto dela.
      setBubbleAccessibleName(
        window.$chatwoot.launcherTitle ||
          IFrameHelper.launcherIconLabel ||
          message.ariaLabel ||
          message.label
      );
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

    resetUnreadMode: () => {
      IFrameHelper.titleFlasher.stop();
      removeUnreadClass();
    },
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

    playAudio: message => {
      // O piscar do titulo NAO depende do som: ele e o aviso de quem esta com
      // a aba em segundo plano, e vale mesmo com o som desligado.
      IFrameHelper.titleFlasher.start(message?.title);

      if (!IFrameHelper.notificationSoundEnabled) return;
      window.playAudioAlert();
    },
  },
  pushEvent: eventName => {
    IFrameHelper.sendMessage('push-event', { eventName });
  },

  onLoad: ({ widgetColor, tokens, channelConfig }) => {
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

    // Bloco 5.08 (T-C2.1) — a única linha deste bloco fora de `sdk/tracking/`.
    // Só busca o coletor quando a inbox tem tracking configurado (T-C2.8); sem config, nem
    // a requisição acontece. A entrega usa dois eventos que o bridge do widget já trata.
    const tracking = channelConfig?.widgetTracking;
    loadCollector({ baseUrl: window.$chatwoot.baseUrl, tracking }).then(
      collector =>
        collector?.attachOriginAttributes({
          tracking,
          sendMessage: IFrameHelper.sendMessage,
        })
    );

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

    // Bloco 3.19. Sem `widget_appearance.launcher_icon` (3.18 ainda não entregou),
    // isto resolve para `default` — o balão de hoje.
    const launcherIcon = resolveLauncherIcon(channelConfig);

    // O rótulo configurado na tela de aparência precisa sobreviver à ponte do 1.06:
    // sem guardá-lo aqui, o `setBubbleLabel` que chega logo depois substituiria
    // "Falar com a Marina" pelo genérico "Abrir o chat". Guardado ao lado de
    // `appliedTokens`, que o 1.03 já pendura no mesmo objeto.
    IFrameHelper.launcherIconLabel = launcherIcon.label;

    const chatIcon = createBubbleIcon({
      className,
      path: bubbleSVG,
      target: chatBubble,
      launcherIcon,
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

    IFrameHelper.montarTeaserSeConfigurado(bubbleHolder);
  },
  toggleCloseButton: () => {
    let isMobile = false;
    if (window.matchMedia('(max-width: 668px)').matches) {
      isMobile = true;
    }
    IFrameHelper.sendMessage('toggle-close-button', { isMobile });
  },
};
