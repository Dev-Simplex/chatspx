import { ref } from 'vue';
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { useTypewriter } from '../useTypewriter';

// We mock requestAnimationFrame to step synchronously through frames with a
// controllable timestamp. Each call to flushFrames(n, advanceMs) walks N frames
// forward, advancing the simulated `performance.now()` by `advanceMs` per frame.
let pendingRafs = [];
let now = 0;

function installRaf() {
  pendingRafs = [];
  now = 0;
  window.requestAnimationFrame = cb => {
    pendingRafs.push(cb);
    return pendingRafs.length;
  };
  window.cancelAnimationFrame = id => {
    pendingRafs[id - 1] = null;
  };
}

function flushFrames(count = 1, advanceMs = 40) {
  for (let i = 0; i < count; i += 1) {
    now += advanceMs;
    // Skip cancelled (null) callbacks — cancelAnimationFrame leaves a hole
    // in the queue rather than re-indexing.
    let cb = pendingRafs.shift();
    while (cb === null && pendingRafs.length) {
      cb = pendingRafs.shift();
    }
    if (cb) cb(now);
  }
}

// Mock useReducedMotion to allow toggling per test
let mockReducedMotion = false;
vi.mock('dashboard/composables/useReducedMotion', () => ({
  useReducedMotion: () => ({
    prefersReducedMotion: { value: mockReducedMotion },
  }),
}));

// onBeforeUnmount needs an active component instance — stub it out so the
// composable can be exercised in plain JS land.
vi.mock('vue', async () => {
  const actual = await vi.importActual('vue');
  return { ...actual, onBeforeUnmount: () => {} };
});

describe('useTypewriter', () => {
  beforeEach(() => {
    installRaf();
    mockReducedMotion = false;
  });

  afterEach(() => {
    pendingRafs = [];
  });

  it('does NOT report done for empty text (nothing arrived yet)', () => {
    // Regressão C1: com `isDone` verdadeiro no texto vazio, a bolha anunciava
    // "Resposta pronta" no `role=status` em t=0, antes do primeiro token.
    const text = ref('');
    const { displayed, isDone, start } = useTypewriter(text);
    start();
    expect(isDone.value).toBe(false);
    expect(displayed.value).toBe('');
    expect(pendingRafs.length).toBe(0);
  });

  it('reports done only once the first tokens have been rendered', () => {
    const text = ref('');
    const { displayed, isDone, start } = useTypewriter(text, {
      mode: 'word',
      delay: 35,
    });
    start();
    expect(isDone.value).toBe(false);

    text.value = 'pronto';
    start();
    flushFrames(1, 40);
    expect(displayed.value).toBe('pronto');
    flushFrames(1, 40);
    expect(isDone.value).toBe(true);
  });

  it('streams word-by-word with default 35ms delay', () => {
    const text = ref('hello world there');
    const { displayed, isDone, start } = useTypewriter(text, {
      mode: 'word',
      delay: 35,
    });
    start();
    // Tokens: ['hello', ' ', 'world', ' ', 'there'] = 5 tokens
    expect(displayed.value).toBe('');
    flushFrames(1, 40);
    expect(displayed.value).toBe('hello');
    flushFrames(1, 40);
    expect(displayed.value).toBe('hello ');
    flushFrames(1, 40);
    expect(displayed.value).toBe('hello world');
    flushFrames(1, 40);
    expect(displayed.value).toBe('hello world ');
    flushFrames(1, 40);
    expect(displayed.value).toBe('hello world there');
    flushFrames(1, 40);
    expect(isDone.value).toBe(true);
  });

  it('streams char-by-char in char mode', () => {
    const text = ref('abc');
    const { displayed, isDone, start } = useTypewriter(text, {
      mode: 'char',
      delay: 10,
    });
    start();
    flushFrames(1, 15);
    expect(displayed.value).toBe('a');
    flushFrames(1, 15);
    expect(displayed.value).toBe('ab');
    flushFrames(1, 15);
    expect(displayed.value).toBe('abc');
    flushFrames(1, 15);
    expect(isDone.value).toBe(true);
  });

  it('renders instantly when prefers-reduced-motion is set', () => {
    mockReducedMotion = true;
    const text = ref('reduced motion text here');
    const { displayed, isDone, start } = useTypewriter(text);
    start();
    expect(displayed.value).toBe('reduced motion text here');
    expect(isDone.value).toBe(true);
    // No raf should have been scheduled
    expect(pendingRafs.length).toBe(0);
  });

  it('stops mid-stream when AbortSignal fires', () => {
    const controller = new AbortController();
    const text = ref('one two three four five');
    const { displayed, isDone, start } = useTypewriter(text, {
      mode: 'word',
      delay: 35,
      signal: controller.signal,
    });
    start();
    flushFrames(2, 40);
    expect(displayed.value.length).toBeGreaterThan(0);
    controller.abort();
    flushFrames(5, 40);
    // Once aborted, displayed should not progress further
    const frozen = displayed.value;
    flushFrames(5, 40);
    expect(displayed.value).toBe(frozen);
    expect(isDone.value).toBe(false);
  });

  it('cancel + restart resets state cleanly', () => {
    const text = ref('alpha beta gamma');
    const { displayed, isDone, start, cancel } = useTypewriter(text, {
      mode: 'word',
      delay: 35,
    });
    start();
    flushFrames(1, 40);
    expect(displayed.value).toBe('alpha');
    cancel();
    start();
    expect(displayed.value).toBe('');
    expect(isDone.value).toBe(false);
    flushFrames(1, 40);
    expect(displayed.value).toBe('alpha');
  });

  it('handles emoji multi-codepoint sequences without splitting them', () => {
    // Skin-tone modifier: thumbs-up + medium-light skin tone
    const emoji = '\u{1F44D}\u{1F3FB}';
    const text = ref(emoji);
    const { displayed, isDone, start } = useTypewriter(text, {
      mode: 'char',
      delay: 10,
    });
    start();
    // Array.from handles surrogate pairs correctly: 2 entries (base + tone)
    flushFrames(1, 15);
    flushFrames(1, 15);
    flushFrames(1, 15);
    expect(displayed.value).toBe(emoji);
    expect(isDone.value).toBe(true);
  });

  it('does not crash if cancel is called after raf is unscheduled', () => {
    const text = ref('hi there');
    const { start, cancel } = useTypewriter(text, { mode: 'word', delay: 35 });
    start();
    cancel();
    expect(() => cancel()).not.toThrow();
  });
});
