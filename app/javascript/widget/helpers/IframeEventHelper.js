// Os nomes dos tokens que atravessam a ponte para o host.
//
// Bloco 1.03 do PLANO-MESTRE (§2.2 · W1.3) · plano 22 §A.2.
//
// O launcher NÃO vive neste documento: ele é criado pelo SDK no `document` do
// site do cliente, e por isso não alcança o `:root` do iframe. São dois pontos
// de injeção. A regra da onda é que eles tenham UMA fonte — e a fonte é o
// servidor (`WidgetTokens`, bloco 1.02), não uma segunda cópia da fórmula de
// contraste escrita em JS.
//
// A lista é fechada de propósito: só nome conhecido atravessa, e do outro lado
// o `IFrameHelper` valida o VALOR antes de escrever em `style`. Um `postMessage`
// é superfície de entrada.
export const WIDGET_TOKEN_NAMES = [
  '--w-brand',
  '--w-brand-hover',
  '--w-brand-active',
  '--w-on-brand',
  '--w-brand-readable',
  '--w-brand-readable-dark',
  '--w-focus-ring-color',
];

// Fallback para o HTML antigo em cache: uma aba aberta antes do deploy tem
// `chatwootWebChannel` sem `tokens`. Nesse caso lemos as variáveis do `:root`
// que ESTE painel está pintando — que é literalmente a mesma fonte, só que
// lida do outro lado. O launcher nunca fica sem cor por causa de cache.
const tokensFromRoot = () => {
  if (typeof getComputedStyle !== 'function') return {};
  const root = getComputedStyle(document.documentElement);
  return WIDGET_TOKEN_NAMES.reduce((acc, name) => {
    const value = root.getPropertyValue(name).trim();
    if (value) acc[name] = value;
    return acc;
  }, {});
};

export const widgetTokens = () => {
  const fromServer = window.chatwootWebChannel?.tokens;
  if (fromServer && Object.keys(fromServer).length) return fromServer;
  return tokensFromRoot();
};

export const loadedEventConfig = () => {
  return {
    event: 'loaded',
    config: {
      authToken: window.authToken,
      channelConfig: window.chatwootWebChannel,
      // Campo novo num payload existente — o contrato do postMessage não muda.
      tokens: widgetTokens(),
    },
  };
};

export const getExtraSpaceToScroll = () => {
  // This function calculates the extra space needed for the view to
  // accommodate the height of close button + height of
  // read messages button. So that scrollbar won't appear
  const unreadMessageWrap = document.querySelector('.unread-messages');
  const unreadCloseWrap = document.querySelector('.close-unread-wrap');
  const readViewWrap = document.querySelector('.open-read-view-wrap');

  if (!unreadMessageWrap) return 0;

  // 24px to compensate the paddings
  let extraHeight = 48 + unreadMessageWrap.scrollHeight;
  if (unreadCloseWrap) extraHeight += unreadCloseWrap.scrollHeight;
  if (readViewWrap) extraHeight += readViewWrap.scrollHeight;

  return extraHeight;
};

export const shouldTriggerMessageUpdateEvent = message => {
  const { previous_changes: previousChanges } = message;

  if (!previousChanges) {
    return false;
  }
  const hasNotifiableAttributeChanges =
    Object.keys(previousChanges).includes('content_attributes');
  if (!hasNotifiableAttributeChanges) {
    return false;
  }

  const hasSubmittedValueChanges = Object.keys(
    previousChanges.content_attributes[1] || {}
  ).includes('submitted_values');

  return hasSubmittedValueChanges;
};
