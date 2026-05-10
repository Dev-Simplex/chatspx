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
      displayed.value += tokens[cursor];
      cursor += 1;
      lastTick = ts;
    }
    if (hasRaf) {
      rafId = win.requestAnimationFrame(step);
    }
  }

  function start() {
    cancel();
    cursor = 0;
    displayed.value = '';
    isDone.value = false;
    tokens = tokenize();

    if (tokens.length === 0) {
      isDone.value = true;
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
