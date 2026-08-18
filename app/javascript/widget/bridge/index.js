import { IFrameHelper } from 'widget/helpers/utils';
import { handlers } from './handlers';

/**
 * Porta única de entrada do bridge site → widget.
 *
 * Devolve `true` quando a mensagem foi atendida por um handler e `false` quando
 * foi descartada (prefixo errado, origem estranha, JSON quebrado ou evento sem
 * handler). O booleano existe para o teste poder afirmar o descarte — não há
 * efeito observável quando a mensagem é ignorada, e é exatamente isso que
 * precisa ser provado.
 */
export const handleFrameMessage = (event, ctx) => {
  if (!IFrameHelper.isAValidEvent(event)) return false;

  let message;
  try {
    message = IFrameHelper.getMessage(event);
  } catch (error) {
    // Payload com o prefixo certo e JSON quebrado: descarta em vez de estourar
    // dentro do listener (o erro cairia no window.onerror do site do cliente).
    return false;
  }

  const handler = handlers[message.event];
  if (typeof handler !== 'function') return false;

  handler(message, ctx);
  return true;
};

/** Registra o listener e devolve a função registrada, para teste e remoção. */
export const registerBridgeListeners = ctx => {
  const listener = event => handleFrameMessage(event, ctx);
  window.addEventListener('message', listener);
  return listener;
};

export { handlers };
