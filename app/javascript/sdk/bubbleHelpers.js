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
 * "botão" e o visitante não descobre que ali abre o chat. O `title` cravado em
 * inglês que existia aqui também não servia — em conta pt-BR ele lia
 * "Open chat window".
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

export const createBubbleIcon = ({ className, path, target }) => {
  let bubbleClassName = `${className} woot-elements--${window.$chatwoot.position}`;
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
  // `currentColor`, não um branco cravado: a cor do ícone passa a herdar o
  // `color` do lançador, que é `var(--w-on-brand)` — a decisão de contraste que
  // o servidor calculou por luminância WCAG. Com marca clara o ícone escurece
  // sozinho, em vez de ficar branco sobre claro a 3,07:1.
  bubblePath.setAttributeNS(null, 'fill', 'currentColor');

  bubbleIcon.appendChild(bubblePath);
  target.appendChild(bubbleIcon);

  if (isExpandedView(window.$chatwoot.type)) {
    const textNode = document.createElement('div');
    textNode.id = 'woot-widget--expanded__text';
    textNode.innerText = '';
    target.appendChild(textNode);
    bubbleClassName += ' woot-widget--expanded';
  }

  target.className = bubbleClassName;
  // Nome provisório, válido pelos milissegundos até o painel montar e a ponte
  // entregar a string traduzida (ver `setBubbleAccessibleName`). A opção pública
  // do cliente vence, e quando ela existe não há momento nenhum em inglês.
  // Não deixar `title` vazio é deliberado: um botão sem nome é pior para o
  // leitor de tela do que um botão com nome no idioma errado.
  target.title = window.$chatwoot.launcherTitle || 'Open chat window';
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
