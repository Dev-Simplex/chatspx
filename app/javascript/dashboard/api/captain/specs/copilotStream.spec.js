import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import {
  buildStreamUrl,
  openFakeStream,
  isFakeStreamEnabled,
  FAKE_STREAM_STORAGE_KEY,
  authHeaders,
  openHttpStream,
  CopilotStreamHttpError,
} from '../copilotStream';
import { useCopilotStream } from 'dashboard/components-next/ai-assistant/composables/useCopilotStream';

/**
 * Proof of streaming.
 *
 * The point of these tests is not that the final text is right — it is that
 * the text ARRIVES IN PIECES, spread over time. A panel that renders the whole
 * answer at once would pass a naive "the text is correct" assertion and still
 * be the broken behaviour we are replacing.
 */

describe('buildStreamUrl', () => {
  it('targets the captain-scoped thread route', () => {
    expect(buildStreamUrl({ accountId: 3, threadId: 55 })).toBe(
      '/api/v1/accounts/3/captain/copilot_threads/55/stream'
    );
  });
});

describe('authHeaders', () => {
  afterEach(() => {
    delete window.axios;
  });

  it('reuses the axios devise-token-auth headers when present', () => {
    window.axios = {
      defaults: {
        headers: {
          common: {
            'access-token': 'tok',
            'token-type': 'Bearer',
            client: 'cli',
            expiry: '123',
            uid: 'a@b.com',
          },
        },
      },
    };
    expect(authHeaders()).toMatchObject({
      'access-token': 'tok',
      client: 'cli',
      uid: 'a@b.com',
    });
  });
});

describe('openFakeStream (local token emitter)', () => {
  it('emits many token frames before the done frame', async () => {
    const frames = [];
    await openFakeStream({
      onEvent: e => frames.push(e),
      delayMs: 1,
      chunks: ['uma frase curta ', 'e mais outra'],
    });

    const tokens = frames.filter(f => f.event === 'token');
    const done = frames.filter(f => f.event === 'done');
    expect(tokens.length).toBeGreaterThan(4);
    expect(done).toHaveLength(1);
    expect(frames.at(-1).event).toBe('done');
  });

  it('stops emitting when the signal is aborted', async () => {
    const controller = new AbortController();
    const frames = [];
    const pending = openFakeStream({
      onEvent: e => {
        frames.push(e);
        if (frames.length === 1) controller.abort();
      },
      signal: controller.signal,
      delayMs: 5,
      chunks: ['a ', 'b ', 'c ', 'd ', 'e '],
    });
    await pending;

    expect(frames.some(f => f.event === 'done')).toBe(false);
    expect(frames.length).toBeLessThan(5);
  });

  it('can emit an error frame instead', async () => {
    const frames = [];
    await openFakeStream({
      onEvent: e => frames.push(e),
      delayMs: 1,
      fakeError: 'unauthorized',
    });
    expect(frames).toHaveLength(1);
    expect(frames[0].event).toBe('error');
    expect(JSON.parse(frames[0].data).code).toBe('unauthorized');
  });
});

describe('useCopilotStream against the fake emitter (end to end)', () => {
  beforeEach(() => {
    window.localStorage.setItem(FAKE_STREAM_STORAGE_KEY, '1');
  });

  afterEach(() => {
    window.localStorage.removeItem(FAKE_STREAM_STORAGE_KEY);
  });

  it('is enabled by the localStorage switch', () => {
    expect(isFakeStreamEnabled()).toBe(true);
  });

  it('delivers the answer in growing pieces, not in one shot', async () => {
    let api = null;
    mount({
      setup() {
        api = useCopilotStream();
        return () => null;
      },
    });

    const snapshots = [];
    const startedAt = Date.now();
    const result = await api.start({
      threadId: 1,
      message: 'o que devo fazer agora?',
      onToken: () => snapshots.push(api.streamedText.value),
    });
    const elapsed = Date.now() - startedAt;

    // Many partial renders...
    expect(snapshots.length).toBeGreaterThan(10);
    // ...each one strictly longer than the previous (never rewritten, never
    // reordered)...
    snapshots.forEach((text, index) => {
      if (index === 0) return;
      expect(text.startsWith(snapshots[index - 1])).toBe(true);
      expect(text.length).toBeGreaterThan(snapshots[index - 1].length);
    });
    // ...and the first render happens long before the last: this is what
    // rules out "arrived all at once".
    expect(snapshots[0].length).toBeLessThan(result.text.length / 2);
    expect(elapsed).toBeGreaterThan(50);
    expect(result.status).toBe('done');
    expect(result.text).toBe(snapshots.at(-1));
  }, 15000);
});

describe('openHttpStream', () => {
  const originalFetch = global.fetch;

  afterEach(() => {
    global.fetch = originalFetch;
  });

  it('throws CopilotStreamHttpError carrying the status', async () => {
    global.fetch = vi.fn(async () => ({
      ok: false,
      status: 401,
      text: async () => '{"error":"unauthorized"}',
    }));

    await expect(
      openHttpStream({ url: '/x', body: {}, onChunk: () => {} })
    ).rejects.toMatchObject({
      name: 'CopilotStreamHttpError',
      status: 401,
    });
  });

  it('pumps ReadableStream chunks into onChunk in order', async () => {
    const encoder = new TextEncoder();
    const parts = ['event: token\n', 'data: {"delta":"a"}\n\n'];
    let index = 0;
    global.fetch = vi.fn(async () => ({
      ok: true,
      body: {
        getReader: () => ({
          read: async () => {
            if (index >= parts.length) return { done: true };
            const value = encoder.encode(parts[index]);
            index += 1;
            return { value, done: false };
          },
          releaseLock: () => {},
        }),
      },
    }));

    const chunks = [];
    await openHttpStream({
      url: '/x',
      body: { message: 'oi' },
      onChunk: chunk => chunks.push(chunk),
    });

    expect(chunks).toEqual(parts);
  });

  it('sends Accept: text/event-stream and the Last-Event-ID on retry', async () => {
    let captured = null;
    global.fetch = vi.fn(async (url, options) => {
      captured = options;
      return { ok: true, body: null, text: async () => '' };
    });

    await openHttpStream({
      url: '/x',
      body: {},
      lastEventId: '12',
      onChunk: () => {},
    });

    expect(captured.headers.Accept).toBe('text/event-stream');
    expect(captured.headers['Last-Event-ID']).toBe('12');
    expect(captured.method).toBe('POST');
  });
});

describe('CopilotStreamHttpError', () => {
  it('keeps the status and body for classification', () => {
    const error = new CopilotStreamHttpError(503, 'upstream down');
    expect(error.status).toBe(503);
    expect(error.body).toBe('upstream down');
  });
});
