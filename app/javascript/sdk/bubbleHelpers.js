import { addClasses, removeClasses, toggleClass } from './DOMHelpers';
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
 * Nome acessível do lançador, traduzido (asserção 9).
 * Até aqui o botão nascia com um title cravado em inglês, igual para toda conta e
 * para todo idioma. É esse literal que este bloco mata — e o teste varre o arquivo
 * inteiro atrás dele, por isso ele não aparece nem em comentário.
 *
 * O SDK roda na página do cliente, fora do bundle de i18n do widget — por isso a
 * tabela vive aqui, com as duas formas que o plano nomeia: com o nome de alguém
 * ("Falar com a Marina") e a genérica ("Abrir chat").
 */
const LAUNCHER_LABELS = {
  pt_BR: { named: 'Falar com {name}', generic: 'Abrir chat' },
  pt: { named: 'Falar com {name}', generic: 'Abrir chat' },
  es: { named: 'Hablar con {name}', generic: 'Abrir chat' },
  en: { named: 'Chat with {name}', generic: 'Open chat' },
};

export const launcherLabel = ({ locale, name } = {}) => {
  const pack =
    LAUNCHER_LABELS[locale] ||
    LAUNCHER_LABELS[String(locale || '').split(/[_-]/)[0]] ||
    LAUNCHER_LABELS.en;

  const trimmed = typeof name === 'string' ? name.trim() : '';
  return trimmed ? pack.named.replace('{name}', trimmed) : pack.generic;
};

/**
 * Normaliza `launcher_icon` contra o contrato, aceitando as duas formas que o schema
 * de 3.18 pode assumir: a string do modo, ou o objeto com modo e URL.
 *
 * Garantias, cada uma um jeito de o lançador sumir da página do cliente:
 *  - chave ausente, modo desconhecido ou `image` sem URL → `default` (nunca um lançador vazio);
 *  - `agent_photo` reusa o `avatarUrl` que o canal já entrega, sem upload novo;
 *  - `agent_photo` sem avatar → `default`.
 */
export const resolveLauncherIcon = (channelConfig = {}) => {
  const config = channelConfig || {};
  const appearance = config.widgetAppearance || {};
  const raw = appearance.launcher_icon ?? appearance.launcherIcon;
  const asObject = raw && typeof raw === 'object' ? raw : {};
  const requested = typeof raw === 'string' ? raw : asObject.mode;

  const label = launcherLabel({
    locale: config.locale,
    name: asObject.label || appearance.launcher_icon_label,
  });

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
  // O literal continua ATRIBUTO de propósito: `.woot-widget-bubble-color--lighter path`
  // pinta por CSS, e CSS vence atributo de apresentação. Um `style` inline aqui mataria
  // silenciosamente a variante clara. A troca por token é do bloco 1.05, que abre esta
  // mesma linha — este bloco só a parametriza para o merge não brigar.
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

export const createBubbleIcon = ({
  className,
  path,
  target,
  launcherIcon = { mode: 'default', src: null, label: null },
  iconFill = '#FFFFFF',
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

  // Asserção 9: nome acessível traduzido, nunca mais o title cravado em inglês.
  const accessibleName = label || launcherLabel({});
  target.title = accessibleName;
  target.setAttribute('aria-label', accessibleName);

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
    dispatchWindowEvent({ eventName: CHATWOOT_OPENED });
  } else {
    dispatchWindowEvent({ eventName: CHATWOOT_CLOSED });
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
