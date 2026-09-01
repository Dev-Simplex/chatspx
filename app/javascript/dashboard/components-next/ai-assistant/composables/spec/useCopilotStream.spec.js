import { describe, it, expect, beforeEach, vi } from 'vitest';
import { mount } from '@vue/test-utils';

/**
 * Transport double. Each test scripts what the "server" writes and we assert
 * on what the composable does with it — including the abort contract, which
 * is the difference between "the spinner went away" and "the job was killed".
 */
const hoisted = vi.hoisted(() => {
  class FakeHttpError extends Error {
    constructor(status) {
      super(`HTTP ${status}`);
      this.name = 'CopilotStreamHttpError';
      this.status = status;
    }
  }
  return { FakeHttpError, transport: { script: null, calls: [] } };
});

const { FakeHttpError, transport } = hoisted;

vi.mock('dashboard/api/captain/copilotStream', () => ({
  buildStreamUrl: ({ threadId }) => `/stream/${threadId}`,
  isFakeStreamEnabled: () => false,
  openFakeStream: vi.fn(),
  CopilotStreamHttpError: hoisted.FakeHttpError,
  openHttpStream: options => {
    hoisted.transport.calls.push(options);
    return hoisted.transport.script(options);
  },
}));

import { useCopilotStream, STREAM_STATUS } from '../useCopilotStream';

/** Mounts a throwaway component so onBeforeUnmount hooks have an owner. */
function withComposable() {
  let api = null;
  const wrapper = mount({
    setup() {
      api = useCopilotStream();
      return () => null;
    },
  });
  return { api, wrapper };
}

const frame = (event, data) =>
  `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;

describe('useCopilotStream', () => {
  beforeEach(() => {
    transport.script = null;
    transport.calls = [];
  });

  it('accumulates tokens in the order the server wrote them', async () => {
    transport.script = async ({ onChunk }) => {
      onChunk(frame('token', { delta: 'Bom ' }));
      onChunk(frame('token', { delta: 'dia' }));
      onChunk(frame('token', { delta: ', Marina' }));
      onChunk(frame('done', { message_id: 42, finish_reason: 'stop' }));
    };

    const { api } = withComposable();
    const seen = [];
    const result = await api.start({
      threadId: 9,
      message: 'oi',
      onToken: delta => seen.push(delta),
    });

    expect(seen).toEqual(['Bom ', 'dia', ', Marina']);
    expect(result.status).toBe(STREAM_STATUS.DONE);
    expect(result.text).toBe('Bom dia, Marina');
    expect(result.messageId).toBe(42);
    expect(api.streamedText.value).toBe('Bom dia, Marina');
  });

  it('exposes the text as it grows, not only at the end', async () => {
    const snapshots = [];
    const { api } = withComposable();

    transport.script = async ({ onChunk }) => {
      onChunk(frame('token', { delta: 'um ' }));
      snapshots.push(api.streamedText.value);
      onChunk(frame('token', { delta: 'dois ' }));
      snapshots.push(api.streamedText.value);
      onChunk(frame('token', { delta: 'tres' }));
      snapshots.push(api.streamedText.value);
      onChunk(frame('done', { finish_reason: 'stop' }));
    };

    await api.start({ threadId: 1, message: 'x' });

    // Strictly growing prefixes — this is what "progressive" means.
    expect(snapshots).toEqual(['um ', 'um dois ', 'um dois tres']);
  });

  it('stop() aborts the connection for real (server sees the disconnect)', async () => {
    let capturedSignal = null;
    transport.script = ({ onChunk, signal }) => {
      capturedSignal = signal;
      onChunk(frame('token', { delta: 'parcial' }));
      return new Promise(resolve => {
        signal.addEventListener('abort', () => resolve(), { once: true });
      });
    };

    const { api } = withComposable();
    const pending = api.start({ threadId: 3, message: 'x' });
    await Promise.resolve();

    api.stop('user');
    const result = await pending;

    expect(capturedSignal.aborted).toBe(true);
    expect(result.status).toBe(STREAM_STATUS.CANCELLED);
    expect(result.text).toBe('parcial');
    expect(api.isStreaming.value).toBe(false);
  });

  it('surfaces a server `error` frame with its code', async () => {
    transport.script = async ({ onChunk }) => {
      onChunk(
        frame('error', { code: 'unauthorized', message: 'invalid api key' })
      );
    };

    const { api } = withComposable();
    const result = await api.start({ threadId: 4, message: 'x' });

    expect(result.status).toBe(STREAM_STATUS.ERROR);
    expect(result.error.code).toBe('unauthorized');
    expect(api.streamError.value.code).toBe('unauthorized');
  });

  it('maps HTTP 401 to `unauthorized` and does NOT retry it', async () => {
    transport.script = async () => {
      throw new FakeHttpError(401);
    };

    const { api } = withComposable();
    const result = await api.start({ threadId: 5, message: 'x' });

    expect(result.status).toBe(STREAM_STATUS.ERROR);
    expect(result.error.code).toBe('unauthorized');
    expect(transport.calls).toHaveLength(1);
  });

  it('maps HTTP 429 / 503 to rate_limit / captain_unstable', async () => {
    transport.script = async () => {
      throw new FakeHttpError(429);
    };
    const first = withComposable();
    expect((await first.api.start({ threadId: 6 })).error.code).toBe(
      'rate_limit'
    );

    transport.script = async () => {
      throw new FakeHttpError(503);
    };
    const second = withComposable();
    expect((await second.api.start({ threadId: 7 })).error.code).toBe(
      'captain_unstable'
    );
  });

  it('retries a dropped connection and gives up as `network`', async () => {
    transport.script = async () => {
      throw new TypeError('Failed to fetch');
    };

    const { api } = withComposable();
    const result = await api.start({ threadId: 8, message: 'x' });

    // 1 initial attempt + 2 reconnects.
    expect(transport.calls).toHaveLength(3);
    expect(result.status).toBe(STREAM_STATUS.ERROR);
    expect(result.error.code).toBe('network');
  }, 10000);

  it('does not duplicate text when the server replays after a drop', async () => {
    let attempt = 0;
    transport.script = async ({ onChunk }) => {
      attempt += 1;
      if (attempt === 1) {
        onChunk(frame('token', { delta: 'meia ' }));
        throw new TypeError('Failed to fetch');
      }
      onChunk(frame('token', { delta: 'meia ' }));
      onChunk(frame('token', { delta: 'resposta' }));
      onChunk(frame('done', { finish_reason: 'stop' }));
    };

    const { api } = withComposable();
    const result = await api.start({ threadId: 10, message: 'x' });

    expect(result.status).toBe(STREAM_STATUS.DONE);
    expect(result.text).toBe('meia resposta');
  }, 10000);

  it('drops frames already seen when the server numbers them', async () => {
    let attempt = 0;
    transport.script = async ({ onChunk, lastEventId }) => {
      attempt += 1;
      if (attempt === 1) {
        onChunk(`id: 1\nevent: token\ndata: {"delta":"A"}\n\n`);
        onChunk(`id: 2\nevent: token\ndata: {"delta":"B"}\n\n`);
        throw new TypeError('Failed to fetch');
      }
      expect(lastEventId).toBe('2');
      // A server that ignores Last-Event-ID replays everything.
      onChunk(`id: 1\nevent: token\ndata: {"delta":"A"}\n\n`);
      onChunk(`id: 2\nevent: token\ndata: {"delta":"B"}\n\n`);
      onChunk(`id: 3\nevent: token\ndata: {"delta":"C"}\n\n`);
      onChunk(frame('done', { finish_reason: 'stop' }));
    };

    const { api } = withComposable();
    const result = await api.start({ threadId: 11, message: 'x' });

    expect(result.text).toBe('ABC');
  }, 10000);

  it('keeps isStreaming false once it settles (no infinite spinner)', async () => {
    transport.script = async () => {
      throw new FakeHttpError(500);
    };
    const { api } = withComposable();
    expect(api.isStreaming.value).toBe(false);
    await api.start({ threadId: 12, message: 'x' });
    expect(api.isStreaming.value).toBe(false);
  });
});
