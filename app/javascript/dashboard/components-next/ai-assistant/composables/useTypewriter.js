import { ref, onBeforeUnmount } from 'vue';
import { useReducedMotion } from 'dashboard/composables/useReducedMotion';

/**
 * Composable for streaming text into a reactive ref with a typewriter effect.
 *
 * Honors `prefers-reduced-motion` (renders the full text instantly), supports
 * cancellation via an external `AbortSignal`, and tokenizes either word-by-word
 * (default) or character-by-character. The internal scheduler uses
 * `requestAnimationFrame` so it stays in sync with the browser paint and
 * pauses automatically when the tab is hidden.
 *
 * @param {import('vue').Ref<string>} textRef - Ref containing the full text to stream.
 * @param {Object} [options]
 * @param {'word'|'char'} [options.mode='word'] - Tokenization strategy.
 * @param {number} [options.delay=35] - Minimum ms between tokens.
 * @param {AbortSignal} [options.signal] - Optional external abort signal.
 * @returns {{ displayed: import('vue').Ref<string>, isDone: import('vue').Ref<boolean>, start: () => void, cancel: () => void }}
 */
/** Acima desta fila de tokens pendentes o typewriter entra em catch-up. */
const CATCH_UP_THRESHOLD = 12;

export function useTypewriter(
  textRef,
  { mode = 'word', delay = 35, signal } = {}
) {
  const displayed = ref('');
  const isDone = ref(false);
  let rafId = null;
  let lastTick = 0;
  let cursor = 0;
  let tokens = [];
  // Texto da última tokenização — usado para detectar crescimento incremental
  // (streaming SSE) e continuar de onde parou em vez de reanimar do zero.
  let lastSource = '';

  const { prefersReducedMotion } = useReducedMotion();

  const win = typeof window !== 'undefined' ? window : null;
  const hasRaf = win && typeof win.requestAnimationFrame === 'function';

  function tokenize() {
    const text = textRef?.value ?? '';
    if (!text) return [];
    if (mode === 'word') {
      // Mantém os whitespaces como tokens próprios pra preservar
      // espaços/quebras-de-linha entre palavras.
      return text.split(/(\s+)/);
    }
    // Modo 'char': Array.from para suportar emojis multi-codepoint, ZWJ
    // sequences (ex: 👍🏻, 👨‍👩‍👧). Não usar text.split('') que quebra surrogate pairs.
    return Array.from(text);
  }

  function cancel() {
    if (
      rafId != null &&
      win &&
      typeof win.cancelAnimationFrame === 'function'
    ) {
      win.cancelAnimationFrame(rafId);
    }
    rafId = null;
  }

  function step(ts) {
    if (signal?.aborted) {
      cancel();
      return;
    }
    if (cursor >= tokens.length) {
      isDone.value = true;
      rafId = null;
      return;
    }
    if (ts - lastTick >= delay) {
      // Catch-up: sob streaming real o texto chega mais rápido do que um
      // token a cada `delay`. Se a fila cresce, consome vários por quadro —
      // a animação continua suave e o cursor não fica pra trás do servidor.
      const backlog = tokens.length - cursor;
      const perTick =
        backlog > CATCH_UP_THRESHOLD
          ? Math.ceil(backlog / CATCH_UP_THRESHOLD)
          : 1;
      for (let i = 0; i < perTick && cursor < tokens.length; i += 1) {
        displayed.value += tokens[cursor];
        cursor += 1;
      }
      lastTick = ts;
    }
    if (hasRaf) {
      rafId = win.requestAnimationFrame(step);
    }
  }

  /**
   * Re-tokeniza o texto atual preservando o que já foi exibido. Usado quando
   * o texto cresceu por acréscimo (stream), para nunca reanimar do começo
   * nem voltar atrás no que o agente já leu.
   */
  function resyncFromDisplayed() {
    tokens = tokenize();
    let consumed = '';
    let index = 0;
    while (index < tokens.length && consumed.length < displayed.value.length) {
      consumed += tokens[index];
      index += 1;
    }
    cursor = index;
    displayed.value = consumed;
  }

  function start() {
    const nextText = textRef?.value ?? '';
    // Crescimento incremental do mesmo texto = continuação do stream.
    const isAppend =
      Boolean(lastSource) &&
      Boolean(displayed.value) &&
      nextText.length > lastSource.length &&
      nextText.startsWith(lastSource);
    lastSource = nextText;

    if (isAppend) {
      cancel();
      isDone.value = false;
      if (prefersReducedMotion.value || !hasRaf) {
        displayed.value = nextText;
        cursor = tokenize().length;
        tokens = tokenize();
        isDone.value = true;
        return;
      }
      resyncFromDisplayed();
      lastTick = 0;
      rafId = win.requestAnimationFrame(step);
      return;
    }

    cancel();
    cursor = 0;
    displayed.value = '';
    isDone.value = false;
    tokens = tokenize();

    if (tokens.length === 0) {
      // Texto vazio NÃO é "terminou": é "ainda não chegou nada". Marcar
      // `isDone` aqui fazia a bolha anunciar "Resposta pronta" no `role=status`
      // em t=0, com o corpo vazio — o leitor de tela dava a resposta por
      // pronta antes do primeiro token. Fica falso até haver o que exibir.
      isDone.value = false;
      return;
    }

    if (prefersReducedMotion.value) {
      // Render instantâneo, respeita preferência do usuário
      displayed.value = textRef?.value ?? '';
      isDone.value = true;
      return;
    }

    if (signal?.aborted) {
      isDone.value = false;
      return;
    }

    lastTick = 0;
    if (hasRaf) {
      rafId = win.requestAnimationFrame(step);
    } else {
      // Fallback (SSR ou ambientes sem rAF): render instantâneo
      displayed.value = textRef?.value ?? '';
      isDone.value = true;
    }
  }

  if (signal && typeof signal.addEventListener === 'function') {
    signal.addEventListener('abort', cancel, { once: true });
  }

  onBeforeUnmount(cancel);

  return { displayed, isDone, start, cancel };
}
