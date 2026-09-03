/**
 * O piscar do titulo da aba (bloco 4.11 / W4.6).
 *
 * Quando chega mensagem e a aba do site esta em segundo plano, o unico canal
 * que o visitante ainda ve e o titulo da aba. O piscar existe para isso — e
 * so para isso:
 *
 *  · **so com a aba oculta.** Piscar com a pessoa olhando e ruido;
 *  · **para no `visibilitychange`**, no instante em que ela volta;
 *  · **dura 60 s** e para sozinho: um titulo piscando para sempre e o que faz
 *    a pessoa fechar a aba;
 *  · **nao reentra.** Mensagem nova enquanto ja pisca nao inicia um segundo
 *    ciclo com um segundo `setInterval` — era assim que o titulo original se
 *    perdia e a aba ficava com o texto do alerta para sempre.
 *
 * Numeros de `22-plano-widget.md` W4.6: 650 ms de intervalo, 60 s de duracao.
 */
const INTERVAL_MS = 650;
const DURATION_MS = 60_000;

export const createTitleFlasher = ({
  intervalMs = INTERVAL_MS,
  durationMs = DURATION_MS,
  doc = typeof document === 'undefined' ? null : document,
} = {}) => {
  let intervalId = null;
  let timeoutId = null;
  let originalTitle = '';
  let alternado = false;

  const isRunning = () => intervalId !== null;

  const stop = () => {
    if (!isRunning()) return;
    clearInterval(intervalId);
    clearTimeout(timeoutId);
    intervalId = null;
    timeoutId = null;
    alternado = false;
    // Restaurar SEMPRE, e a partir do que foi guardado no start: reconstruir o
    // titulo a partir do que esta na aba deixaria o texto do alerta grudado.
    doc.title = originalTitle;
  };

  const start = alertText => {
    if (!doc || !alertText) return false;
    // Aba visivel: nao ha nada a anunciar.
    if (!doc.hidden) return false;
    // Ja piscando: a mensagem nova nao reinicia o ciclo nem duplica o timer.
    if (isRunning()) return false;

    originalTitle = doc.title;
    intervalId = setInterval(() => {
      alternado = !alternado;
      doc.title = alternado ? alertText : originalTitle;
    }, intervalMs);
    timeoutId = setTimeout(stop, durationMs);
    return true;
  };

  const onVisibilityChange = () => {
    if (!doc.hidden) stop();
  };

  const attach = () =>
    doc?.addEventListener('visibilitychange', onVisibilityChange);
  const detach = () =>
    doc?.removeEventListener('visibilitychange', onVisibilityChange);

  return { start, stop, attach, detach, isRunning, onVisibilityChange };
};
