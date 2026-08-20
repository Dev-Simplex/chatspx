import { IFrameHelper } from 'widget/helpers/utils';
import { handlers } from './handlers';
import { registerCloseOnEscape } from './closeOnEscape';

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

/**
 * A fiação completa do widget: a ponte site -> widget e o `Esc` (bloco 2.11).
 *
 * Os dois entram pela MESMA porta de propósito. Registrar o `Esc` direto no
 * `App.vue` funcionaria, mas deixaria a ligação verificável só montando o app
 * inteiro — e ligação não testada é como recurso desligado: ninguém percebe.
 * Aqui um teste chama esta função e prova os dois comportamentos.
 *
 * Devolve uma função que desfaz tudo o que foi registrado.
 */
export const registerWidgetListeners = ctx => {
  const messageListener = registerBridgeListeners(ctx);
  const removeCloseOnEscape = registerCloseOnEscape();

  return () => {
    window.removeEventListener('message', messageListener);
    removeCloseOnEscape();
  };
};

export { handlers };
