import { addClasses, removeClasses, toggleClass } from './DOMHelpers';
import {
  applyInertBackground,
  releaseInertBackground,
} from './inertBackground';
import { isMobileViewport } from './viewport';
import { IFrameHelper } from './IFrameHelper';
import { isExpandedView } from './settingsHelper';
import {
  CHATWOOT_CLOSED,
  CHATWOOT_OPENED,
} from '../widget/constants/sdkEvents';
import { dispatchWindowEvent } from 'shared/helpers/CustomEventHelper';

export const bubbleSVG =
  'M240.808 240.808H122.123C56.6994 240.808 3.45695 187.562 3.45695 122.122C3.45695 56.7031 56.6994 3.45697 122.124 3.45697C187.566 3.45697 240.808 56.7031 240.808 122.122V240.808Z';

/**
 * BLOCO 3.19 — o ícone do lançador deixa de ser um `path` fixo.
 *
 * Três modos, e `default` é o padrão de fábrica de TODA inbox nova, em qualquer perfil
 * (decisão D5: o padrão por perfil caiu — foto genérica é pior que balão).
 *
 * Produtor: `widget_appearance.launcher_icon` (bloco 3.18, trilha o2-config-backend)
 * chegando por `channelConfig`. Enquanto 3.18 não entrega a chave, isto resolve para
 * `default` — que é o balão de hoje, byte por byte.
 */
export const LAUNCHER_ICON_MODES = ['default', 'image', 'agent_photo'];

const PHOTO_CLASS = 'woot-widget-bubble--has-photo';
const PHOTO_IMG_CLASS = 'woot-widget-bubble__photo';

/**
 * Normaliza `launcher_icon` contra o contrato, aceitando as duas formas que o schema
 * de 3.18 pode assumir: a string do modo, ou o objeto com modo e URL.
 *
 * Garantias, cada uma um jeito de o lançador sumir da página do cliente:
 *  - chave ausente, modo desconhecido ou `image` sem URL → `default` (nunca um lançador vazio);
 *  - `agent_photo` reusa o `avatarUrl` que o canal já entrega, sem upload novo;
 *  - `agent_photo` sem avatar → `default`.
 *
 * SOBRE O `label`, e é o que mudou no merge com o 1.06: este resolvedor NÃO traduz.
 * Ele só repassa um rótulo que o administrador tenha escrito explicitamente na tela
 * de aparência, nomeando a pessoa da foto. A forma genérica traduzida vem do painel, pela
 * ponte do 1.06, que tem 40 locales — uma tabela de idiomas aqui seria uma segunda
 * fonte de i18n, condenada a divergir da primeira.
 */
export const resolveLauncherIcon = (channelConfig = {}) => {
  const config = channelConfig || {};
  const appearance = config.widgetAppearance || {};
  const raw = appearance.launcher_icon ?? appearance.launcherIcon;
  const asObject = raw && typeof raw === 'object' ? raw : {};
  const requested = typeof raw === 'string' ? raw : asObject.mode;

  const explicit = asObject.label || appearance.launcher_icon_label;
  const label =
    typeof explicit === 'string' && explicit.trim() ? explicit.trim() : null;

  const mode = LAUNCHER_ICON_MODES.includes(requested) ? requested : 'default';

  if (mode === 'image') {
    const src = asObject.url || asObject.src || appearance.launcher_icon_url;
    return src ? { mode, src, label } : { mode: 'default', src: null, label };
  }

  if (mode === 'agent_photo') {
    const src = config.avatarUrl;
    return src ? { mode, src, label } : { mode: 'default', src: null, label };
  }

  return { mode: 'default', src: null, label };
};

/**
 * Asserção 5 — `preload` + `fetchpriority` para o lançador não piscar vazio.
 * A tag é idempotente: reabrir/reinicializar o widget não empilha `<link>`.
 */
export const preloadLauncherImage = src => {
  if (!src || typeof document === 'undefined') return null;

  const existing = document.querySelector(
    `link[rel="preload"][data-woot-launcher][href="${src}"]`
  );
  if (existing) return existing;

  const link = document.createElement('link');
  // `setAttribute` em vez das propriedades IDL de propósito: `link.as = 'image'` não
  // reflete em atributo em toda implementação, e um `<link preload>` sem `as` é
  // ignorado pelo navegador — o preload viraria enfeite e o lançador voltaria a piscar.
  link.setAttribute('rel', 'preload');
  link.setAttribute('as', 'image');
  link.setAttribute('href', src);
  link.setAttribute('fetchpriority', 'high');
  link.setAttribute('data-woot-launcher', 'true');
  document.head.appendChild(link);
  return link;
};

const buildBubbleSvgNode = (path, fill) => {
  const bubbleIcon = document.createElementNS(
    'http://www.w3.org/2000/svg',
    'svg'
  );
  bubbleIcon.setAttributeNS(null, 'id', 'woot-widget-bubble-icon');
  bubbleIcon.setAttributeNS(null, 'width', '24');
  bubbleIcon.setAttributeNS(null, 'height', '24');
  bubbleIcon.setAttributeNS(null, 'viewBox', '0 0 240 240');
  bubbleIcon.setAttributeNS(null, 'fill', 'none');
  bubbleIcon.setAttribute('xmlns', 'http://www.w3.org/2000/svg');

  const bubblePath = document.createElementNS(
    'http://www.w3.org/2000/svg',
    'path'
  );
  bubblePath.setAttributeNS(null, 'd', path);
  // VALOR do 1.05, FORMA do 3.19, e as duas coisas importam por motivos diferentes.
  //
  // VALOR — `currentColor`, não um branco cravado: a cor do ícone herda o `color`
  // do lançador, que é `var(--w-on-brand)`, a decisão de contraste que o servidor
  // calculou por luminância WCAG. Com marca clara o ícone escurece sozinho, em vez
  // de ficar branco sobre claro a 3,07:1. Manter o `#FFFFFF` do 3.19 aqui teria
  // desfeito o 1.05 em silêncio — sem erro, sem teste vermelho.
  //
  // FORMA — continua ATRIBUTO de apresentação, nunca `style` inline. O 1.05 apagou
  // as regras `.woot-widget-bubble-color--lighter path`, então o motivo original
  // ("CSS vence atributo") já não se aplica; o motivo que ficou é outro e continua
  // valendo: `style` inline é a única coisa que uma folha sem `!important` não
  // consegue sobrescrever. Enquanto for atributo, qualquer regra futura sobre `path`
  // ainda alcança o ícone. Há teste travando isso.
  //
  // O parâmetro existe porque o caminho de `onerror` (asserção 6) reconstrói este
  // mesmo nó, e os dois construtores têm de pintar igual.
  bubblePath.setAttributeNS(null, 'fill', fill);

  bubbleIcon.appendChild(bubblePath);
  return bubbleIcon;
};

/**
 * Asserção 6 — `onerror` volta ao `bubbleSVG`.
 * 404 na foto NUNCA pode deixar o site do cliente sem canal de contato.
 */
const buildLauncherImage = ({ src, target, path, fill }) => {
  const img = document.createElement('img');
  img.className = PHOTO_IMG_CLASS;
  img.src = src;
  // Decorativa: o nome acessível vive no <button>, não na imagem. Um `alt` com texto
  // aqui faria o leitor de tela anunciar a mesma coisa duas vezes.
  img.alt = '';
  img.setAttribute('aria-hidden', 'true');
  img.setAttribute('fetchpriority', 'high');
  img.setAttribute('decoding', 'async');
  img.setAttribute('draggable', 'false');

  img.onerror = () => {
    img.onerror = null;
    img.remove();
    removeClasses(target, PHOTO_CLASS);
    target.insertBefore(buildBubbleSvgNode(path, fill), target.firstChild);
  };

  return img;
};

export const body = document.getElementsByTagName('body')[0];
export const widgetHolder = document.createElement('div');

export const bubbleHolder = document.createElement('div');
export const chatBubble = document.createElement('button');
export const closeBubble = document.createElement('button');
export const notificationBubble = document.createElement('span');

export const setBubbleText = bubbleText => {
  if (isExpandedView(window.$chatwoot.type)) {
    const textNode = document.getElementById('woot-widget--expanded__text');
    textNode.innerText = bubbleText;
  }
};

/**
 * Nome acessível do lançador, que vive no documento do HOST.
 *
 * O lançador é um `<button>` só com ícone: sem nome, o leitor de tela anuncia
 * "botão" e o visitante não descobre que ali abre o chat.
 *
 * A tradução não pode nascer neste arquivo: o SDK roda fora do bundle do widget
 * e não alcança o i18n do Vue. Ela chega pela ponte que já existe para o texto
 * do modo expandido (`setBubbleLabel`), com a string vinda do painel, que tem os
 * 40 locales. `window.$chatwoot.launcherTitle` (opção pública do cliente)
 * continua tendo precedência, como no texto expandido.
 */
export const setBubbleAccessibleName = name => {
  if (!name) return;
  [chatBubble, closeBubble].forEach(bubble => {
    bubble.title = name;
    bubble.setAttribute('aria-label', name);
  });
};

export const createBubbleIcon = ({
  className,
  path,
  target,
  launcherIcon = { mode: 'default', src: null, label: null },
  // Default do 1.05, não o `#FFFFFF` que o 3.19 trazia: o branco cravado é
  // exatamente o defeito que o 1.05 matou. Ver o comentário longo em
  // `buildBubbleSvgNode`.
  iconFill = 'currentColor',
}) => {
  let bubbleClassName = `${className} woot-elements--${window.$chatwoot.position}`;

  const { mode, src, label } = launcherIcon || {};
  const usesPhoto = (mode === 'image' || mode === 'agent_photo') && !!src;

  if (usesPhoto) {
    preloadLauncherImage(src);
    target.appendChild(
      buildLauncherImage({ src, target, path, fill: iconFill })
    );
    bubbleClassName += ` ${PHOTO_CLASS}`;
  } else {
    target.appendChild(buildBubbleSvgNode(path, iconFill));
  }

  if (isExpandedView(window.$chatwoot.type)) {
    const textNode = document.createElement('div');
    textNode.id = 'woot-widget--expanded__text';
    textNode.innerText = '';
    target.appendChild(textNode);
    bubbleClassName += ' woot-widget--expanded';
  }

  target.className = bubbleClassName;
  // Nome provisório, válido pelos milissegundos até o painel montar e a ponte
  // entregar a string traduzida (ver `setBubbleAccessibleName`). Verificado que a
  // ponte SEMPRE dispara: `bridge/handlers.js` chama `setBubbleLabel` em
  // `config-set` e em `set-locale` — o inglês daqui nunca é o estado final.
  // Não deixar `title` vazio é deliberado: um botão sem nome é pior para o
  // leitor de tela do que um botão com nome no idioma errado.
  //
  // Precedência, do mais específico para o mais genérico:
  //   1. `launcherTitle` — a opção pública que o cliente escreve no snippet;
  //   2. `label` — o rótulo que o admin escreveu na tela de aparência (3.19), que
  //      é onde mora a forma que nomeia a pessoa da foto: só quem configurou o
  //      lançador sabe o nome da pessoa na foto;
  //   3. o provisório, substituído pela ponte (40 locales) em milissegundos.
  target.title = window.$chatwoot.launcherTitle || label || 'Open chat window';
  target.setAttribute('aria-label', target.title);
  return target;
};

export const createBubbleHolder = hideMessageBubble => {
  if (hideMessageBubble) {
    addClasses(bubbleHolder, 'woot-hidden');
  }
  addClasses(bubbleHolder, 'woot--bubble-holder');
  bubbleHolder.id = 'cw-bubble-holder';
  bubbleHolder.dataset.turboPermanent = true;
  body.appendChild(bubbleHolder);
};

const handleBubbleToggle = newIsOpen => {
  IFrameHelper.events.onBubbleToggle(newIsOpen);

  if (newIsOpen) {
    // Bloco 2.11: em celular o painel e tela cheia, e sem `inert` o Tab e o
    // leitor de tela continuam caminhando pela pagina do cliente ATRAS dele.
    // Em desktop o widget e flutuante e o resto da pagina segue utilizavel de
    // proposito — marcar tudo ali roubaria a pagina de quem so quer ler.
    if (isMobileViewport()) applyInertBackground();
    dispatchWindowEvent({ eventName: CHATWOOT_OPENED });
  } else {
    releaseInertBackground();
    dispatchWindowEvent({ eventName: CHATWOOT_CLOSED });
    // O foco volta ao lancador. JA EXISTIA nesta base — o bloco 2.11 verifica,
    // nao reimplementa: `toggleClass` roda ANTES daqui, entao o botao ja perdeu
    // `woot--hide` e e focavel quando `.focus()` acontece.
    chatBubble.focus();
  }
};

export const onBubbleClick = (props = {}) => {
  const { toggleValue } = props;
  const { isOpen } = window.$chatwoot;
  if (isOpen === toggleValue) return;

  const newIsOpen = toggleValue === undefined ? !isOpen : toggleValue;
  window.$chatwoot.isOpen = newIsOpen;

  toggleClass(chatBubble, 'woot--hide');
  toggleClass(closeBubble, 'woot--hide');
  toggleClass(widgetHolder, 'woot--hide');

  handleBubbleToggle(newIsOpen);
};

export const onClickChatBubble = () => {
  bubbleHolder.addEventListener('click', onBubbleClick);
};

export const addUnreadClass = () => {
  const holderEl = document.querySelector('.woot-widget-holder');
  addClasses(holderEl, 'has-unread-view');
};

export const removeUnreadClass = () => {
  const holderEl = document.querySelector('.woot-widget-holder');
  removeClasses(holderEl, 'has-unread-view');
};
