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
import { isMobileViewport } from './viewport';
import { drenar } from './preBootQueue';
import { montarTeaser } from './teaser';
import { degradar, gravarAbordagem, lerAbordagem } from './tracking/approach';
import { dispatchWindowEvent } from 'shared/helpers/CustomEventHelper';
import { abordagemNovaNoAr } from 'shared/helpers/abordagemProativa';
import {
  CHATWOOT_ERROR,
  CHATWOOT_MESSAGE_SENT,
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
import { aplicarPadraoDoBanco, deslocamentoDoBanco } from './appearance';
import { SDK_APPEARANCE_OVERRIDES } from 'shared/constants/sharedFrameEvents';
import { popoutChatWindow } from '../widget/helpers/popoutHelper';
import { createTitleFlasher } from './titleFlasher';
import { loadCollector } from './tracking/loader';
// Bloco 5.10 — o gate de 5.09 e lido AQUI e passado para a ponte de tags. Aqui, e nao dentro
// da ponte: `entrypoints/sdk.js` ja importa este modulo, entao esta e a MESMA instancia que
// `$chatwoot.setConsent()` atualiza. A ponte mora noutro bundle e teria um segundo estado.
import { applyInboxConsentMode, isAllowed } from './tracking/consent';

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

// Uma hora a partir de agora. ERA `addHours(new Date(), 1)` do `date-fns`, e a
// troca nao e estilo: aquele import arrastava `toDate` + `toInteger` +
// `requiredArgs` para dentro do `sdk.js` — inclusive uma string de deprecacao em
// ingles de 180 caracteres que nenhum visitante jamais le. O arquivo tem teto
// (A13) e e baixado por 100% dos visitantes de todos os sites de todos os
// clientes; o delta medido esta no relatorio do o3-abordagem.
const UMA_HORA_MS = 36e5;

// Bloco 3.18 — AS CLASSES DO HOLDER, NUM LUGAR SO.
//
// Existiam duas necessidades de calcular isto: `createFrame`, no boot, quando o
// host so conhece o `chatwootSettings` do site; e o `loaded`, quando o
// `widgetAppearance` do servidor finalmente chega e a precedencia pode ser
// resolvida. Duas copias da mesma expressao divergiriam no primeiro campo novo
// — e a divergencia apareceria como "a tela diz esquerda e o widget fica a
// direita", que e literalmente o defeito que este bloco fecha.
const holderClassName = () => {
  const { position, hideMessageBubble, widgetStyle } = window.$chatwoot;
  let nome = `woot-widget-holder woot--hide woot-elements--${position}`;
  if (hideMessageBubble) nome += ' woot-widget--without-bubble';
  if (isFlatWidgetStyle(widgetStyle)) nome += ' woot-widget-holder--flat';
  return nome;
};

const updateCampaignReadStatus = baseDomain => {
  const expireBy = new Date(Date.now() + UMA_HORA_MS);
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

    addClasses(widgetHolder, holderClassName());
    widgetHolder.id = 'cw-widget-holder';
    widgetHolder.dataset.turboPermanent = true;
    widgetHolder.appendChild(iframe);
    body.appendChild(widgetHolder);
    IFrameHelper.initPostMessageCommunication();
    IFrameHelper.initWindowSizeListener();
    IFrameHelper.preventDefaultScroll();
  },
  getAppFrame: () => document.getElementById('chatwoot_live_chat_widget'),

  /**
   * Bloco 3.18 — O BANCO VIRA O PADRAO, e o site continua vencendo campo a campo.
   *
   * Roda no `loaded`, ANTES do `config-set` e do `onLoad`, e a ordem e o bloco:
   *
   *   · antes do `config-set` porque e ele que leva `position`, `darkMode`,
   *     `widgetStyle` e `hideMessageBubble` para dentro do painel — mandar
   *     primeiro e corrigir depois faria o painel montar com o valor errado e
   *     piscar para o valor certo;
   *   · antes do `onLoad` porque e la que o lancador nasce, com
   *     `woot-elements--${window.$chatwoot.position}` lido deste mesmo objeto.
   *
   * O `widgetHolder`, porem, JA existe: `createFrame` o criou no boot, quando o
   * host so conhecia `chatwootSettings`. Por isso as classes dele sao reescritas
   * aqui — sem isso `window.$chatwoot.position` diria "left" e o elemento
   * continuaria `woot-elements--right`, que e o pior estado possivel: duas
   * verdades, e a que o visitante ve e a errada.
   *
   * DEVOLVE `null` quando o servidor nao mandou `widgetAppearance` (aba aberta
   * antes do deploy, HTML antigo em cache). `null` e diferente de `[]`: `[]`
   * significa "medi e o site nao sobrescreve nada", e apaga um aviso velho na
   * tela; `null` significa "nao tenho como saber", e nao reporta coisa alguma.
   */
  applyAppearance: channelConfig => {
    const appearance = channelConfig?.widgetAppearance;
    if (!appearance) return null;

    const overrides = window.$chatwoot.appearanceOverrides || [];
    aplicarPadraoDoBanco({
      appearance,
      overrides,
      alvo: window.$chatwoot,
    });

    // `offset_x`/`offset_y` viram custom properties no `bubbleHolder`, e so nele:
    // custom property HERDA, e o lancador, o botao de fechar e o teaser sao todos
    // filhos dele. Escrever tambem no `widgetHolder` seria escrita morta — o
    // painel nao usa offset, e o schema e explicito sobre de quem e a distancia
    // da quina ("o LANCADOR fica a no maximo 200 px").
    //
    // O elemento ainda nao foi anexado ao `body` neste instante (quem o anexa e
    // `createBubbleHolder`, dentro do `onLoad`, logo abaixo). Nao importa: e o
    // mesmo objeto, e `style` inline sobrevive ao `appendChild`.
    const deslocamento = deslocamentoDoBanco(appearance);
    if (deslocamento) {
      Object.entries(deslocamento).forEach(([nome, valor]) => {
        bubbleHolder.style.setProperty(nome, valor);
      });
    }

    // ATRIBUICAO, nao `classList.add`: acrescentar `--left` a um holder que ja
    // tem `--right` deixaria as DUAS classes no elemento, e quem venceria
    // passaria a ser a ordem das regras no CSS. Reescrever pela MESMA funcao que
    // o `createFrame` usou tambem garante que nada mais suma: neste instante o
    // holder tem exatamente o que o boot lhe deu — `has-unread-view` e o toggle
    // de `woot--hide` so acontecem depois, por acao do visitante.
    widgetHolder.className = holderClassName();
    return overrides;
  },

  // Bloco 4.06 — o teaser. Fica aqui, e não no `entrypoints/sdk.js`, porque
  // depende do `bubbleHolder`, que só existe depois do `onLoad`.
  desmontarTeaser: null,

  // Bloco 4.05 — `canalDoBoot` é o `channelConfig` que atravessou a ponte.
  //
  // NÃO existe `window.chatwootWebChannel` neste documento. Aquele objeto é escrito por
  // `app/views/widgets/show.html.erb`, que é o documento do IFRAME; a página do site do
  // cliente nunca o teve. Enquanto esta linha lia o global, `abordagemNovaNoAr({})` era
  // falso em todo site real e o teaser NÃO era montado em lugar nenhum — junto com a
  // degradação do 4.19, o auto-open do 4.20 e a telemetria do 4.21, que pendem daqui.
  //
  // Os dois verificadores do 4.06 são cegos para isto, e vale saber por quê: o spec de
  // `approach` cria o global à mão antes de chamar este método, e o verificador em
  // Chromium mede CSS sobre HTML escrito dentro do próprio arquivo — ele nunca boota o
  // SDK. Nenhum dos dois responde "este objeto existe NESTE documento?".
  //
  // O canal chega em `IframeEventHelper.loadedEventConfig` (`config.channelConfig`) e
  // desce por `onLoad`, que é o único chamador daqui. O `||` do global fica como
  // degradação para o teste que ainda fixa a variável; em produção ele nunca resolve.
  montarTeaserSeConfigurado(holder, canalDoBoot) {
    const canal = canalDoBoot || window.chatwootWebChannel || {};
    const gatilhos = canal.widgetTriggers || {};

    // CONTRATO DO 4.04, ao pé da letra: `enabled` ausente significa que o SDK
    // NÃO DISPARA NADA. Ausência não é `true` — é silêncio, e silêncio aqui é
    // não incomodar o visitante de uma conta que nunca configurou isto.
    //
    // Bloco 4.22: a expressão saiu daqui e virou `abordagemNovaNoAr`, que a
    // supressão da campanha legada consome do OUTRO lado do iframe. Comportamento
    // idêntico ao de antes; o que muda é não haver mais duas cópias da condição
    // para divergirem. Ver o cabeçalho de `shared/helpers/abordagemProativa`.
    if (!abordagemNovaNoAr(canal)) return;

    // O nível vem resolvido do servidor (`resolved_widget_approach`), que já
    // aplica o padrão `bold` e já derruba `aggressive` para `bold` no mobile.
    // O host não recalcula política — consome a decisão, como no 1.03 com a cor.
    const abordagem = IFrameHelper.nivelDeAbordagem(gatilhos);
    IFrameHelper.abordagem = abordagem;
    const { baseDomain } = window.$chatwoot;

    IFrameHelper.desmontarTeaser = montarTeaser({
      holder,
      canal,
      nivel: abordagem.nivel,
      baseDomain,
      aoAbrir: () => {
        IFrameHelper.events.toggleBubble('open');
        IFrameHelper.registrarAbordagem('opened');
      },
      aoDispensar: () => IFrameHelper.registrarAbordagem('dismissed'),
      // Bloco 4.19: a conta sobe quando ABORDAMOS de fato, não quando a página
      // carrega. Quem nunca viu o teaser — banner de cookie na tela, visitante
      // que não rolou — não gasta um degrau da escada por uma abordagem que não
      // aconteceu. `false` no segundo campo é o ciclo recomeçando: ver a §4.19
      // do relatório para por que "já converteu" não sobrevive a uma abordagem
      // nova.
      aoExibir: () => {
        gravarAbordagem(abordagem.ordinal, false, baseDomain);
        IFrameHelper.registrarAbordagem('shown');
      },
    });
  },

  // Bloco 4.21 — a EXIBIÇÃO vira dado, e é ela que faz os três níveis medíveis.
  //
  // O host não fala com o servidor: ele empurra o fato pela ponte que já existe e
  // o iframe grava. Duas razões, e as duas são do teto de bytes (A13): o iframe
  // já tem `axios`, o token de sessão e o tratamento de erro — replicar isso aqui
  // custaria bytes a 100% dos visitantes de todos os sites; e o `X-Auth-Token`
  // mora no iframe, que é onde ele deve morar.
  //
  // Sem abordagem montada (`enabled !== true`), não há o que registrar: sai em
  // silêncio. Exibição SEM abertura também é registrada — sem denominador não há
  // medição, e é a `shown` que responde "de quantos".
  registrarAbordagem(etapa) {
    const abordagem = IFrameHelper.abordagem;
    if (!abordagem) return;

    IFrameHelper.sendMessage('approach-event', {
      etapa,
      approach: abordagem.nivel,
      approach_configured: abordagem.configurado,
      // A ordem desta abordagem na vida deste navegador. Ela é a chave natural
      // do fato: é o que vira `dedup_key` no servidor, e é por isso que o retry
      // de uma requisição não vira uma conversão contada duas vezes.
      ordinal: abordagem.ordinal,
    });
  },

  // O nível efetivo desta visita — o configurado (4.06) com a degradação por
  // familiaridade do 4.19 por cima. Ponto ÚNICO: o teaser (4.06) e o auto-open
  // (4.20) leem a mesma decisão, e por isso não podem divergir.
  //
  // No celular lê-se `approach_mobile` E SÓ ELE. Cair para `approach` seria a
  // brecha que o aceite do 4.20 manda conferir: o desktop pode ser `aggressive`,
  // o celular nunca. O servidor já fecha esse caminho em `resolved_widget_approach`
  // e o schema 3.20 o recusa com 422 — esta linha é a terceira ponta, de graça.
  nivelDeAbordagem(gatilhos) {
    // `isMobileViewport()` e nao um `matchMedia` proprio. O bloco 2.09 fez o widget ter UM
    // breakpoint (768) porque a base tinha tres numeros para a mesma pergunta; este uso nasceu
    // no 4.06, em paralelo, e trouxe o 667 de volta. Na faixa de 668 a 767 px o teaser decidia
    // "desktop" enquanto o CSS ja tratava como celular. O merge das trilhas foi quem revelou, e
    // o spec do 2.09 foi quem cobrou.
    const ehCelular = isMobileViewport();
    const configurado =
      (ehCelular ? gatilhos.approach_mobile : gatilhos.approach) || 'bold';
    const [abordagens] = lerAbordagem();

    return {
      configurado,
      // 1-based: a abordagem que está para acontecer, não a que já aconteceu.
      ordinal: abordagens + 1,
      nivel:
        gatilhos.degrade_on_return === false
          ? configurado
          : degradar(configurado, abordagens),
    };
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

      // Bloco 3.18 — a PRIMEIRA coisa depois da fila, porque tudo o que vem
      // abaixo (o `config-set` para o painel, o lancador do `onLoad`) le
      // `window.$chatwoot` e passaria a mentir se lesse antes.
      const appearanceOverrides = IFrameHelper.applyAppearance(
        message.config.channelConfig
      );

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

      // Bloco 3.18 — o RELATORIO da precedencia, que e a metade "e a tela avisa"
      // do aceite. O host e o unico lugar do produto que consegue ler o
      // `chatwootSettings` do site do cliente; sem esta mensagem a tela de
      // aparencia so poderia adivinhar, e ela adivinhava mostrando o valor do
      // banco como se fosse o que o visitante ve.
      //
      // Vai pela ponte, como o 4.21: o `sdk.js` tem teto de peso e e baixado por
      // 100% dos visitantes de todos os clientes, enquanto do outro lado do
      // iframe ja existem `axios`, o `X-Auth-Token` da sessao e o tratamento de
      // erro. Aqui se paga so o `postMessage`.
      if (appearanceOverrides) {
        IFrameHelper.sendMessage(SDK_APPEARANCE_OVERRIDES, {
          fields: appearanceOverrides,
        });
      }

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
      // Bloco 4.19 — CONVERTER ZERA O CONTADOR. Entra pela ponte que ja existe
      // em vez de um listener novo: `onEvent` ja e o caminho de todo evento que
      // o iframe manda ao host, e um `window.addEventListener` proprio custaria
      // bytes no arquivo com teto (A13) para escutar o que ja chega aqui.
      if (eventName === CHATWOOT_MESSAGE_SENT) {
        gravarAbordagem(0, true, window.$chatwoot.baseDomain);
      }
      // Bloco 5.10 — o mesmo evento que vai ao `window` do site alimenta a ponte de tags.
      // A traducao `chatwoot:*` -> `chatspx_*` mora em `tags.js` (artefato sob demanda), e
      // nao aqui, porque o mapa e o `SDK_EVENT_CONTRACT` inteiro e ele nao cabe no orcamento
      // de bytes do `sdk.js` (A13). Vai ANTES do `dispatchWindowEvent` para que uma tag do
      // cliente que lance nao impeca a nossa medicao — a reciproca ja e garantida por
      // `tags.js`, que nunca lanca.
      IFrameHelper.tags?.onWindowEvent(eventName, data);
      dispatchWindowEvent({ eventName, data });
    },

    // Bloco 5.16/5.05 — o fato ja registrado no servidor volta do iframe com o `event_id`,
    // e e aqui que ele encontra as tags do cliente.
    trackingEvent(message) {
      IFrameHelper.tags?.onTrackingEvent(message);
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

    // Bloco 5.09 — o modo de consentimento da inbox precisa ser APLICADO, nao so validado.
    // Sem esta linha `consentModeIsActive()` fica falso para sempre e `isAllowed` devolve
    // `true` para tudo: o gate existe e nao gateia nada. Fica FORA do `then` do coletor de
    // proposito — uma conta pode ter `consent_mode` sem ter pixel nenhum, e nesse caso o
    // coletor nunca e buscado.
    applyInboxConsentMode(tracking?.consent_mode);

    loadCollector({ baseUrl: window.$chatwoot.baseUrl, tracking }).then(
      collector => {
        collector?.attachOriginAttributes({
          tracking,
          sendMessage: IFrameHelper.sendMessage,
        });
        // Bloco 5.10 — a ponte de tags. Fica guardada porque os eventos chegam DEPOIS: o
        // `onEvent` e o `trackingEvent` consultam `IFrameHelper.tags`, que e `undefined`
        // enquanto o artefato nao chegou (ou quando a inbox nao tem tracking) — e `?.` ali e
        // o que faz "sem configuracao, nenhuma tag nossa" custar zero linha de decisao.
        IFrameHelper.tags = collector?.createTagsBridge({
          tracking,
          isAllowed,
        });
      }
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

    IFrameHelper.montarTeaserSeConfigurado(bubbleHolder, channelConfig);
  },
  toggleCloseButton: () => {
    // Bloco 2.09: o numero vem de `sdk/viewport.js`. Aqui havia um limite
    // proprio, e ele nao batia com o do CSS — em 668 px o CSS ja tratava como
    // desktop enquanto este JS avisava o widget que era celular.
    IFrameHelper.sendMessage('toggle-close-button', {
      isMobile: isMobileViewport(),
    });
  },
};
