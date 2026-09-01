import { describe, it, expect, vi } from 'vitest';
import { createSSEParser, parseEventData } from '../sseParser';

describe('createSSEParser', () => {
  it('emits a complete event only after the blank line', () => {
    const onEvent = vi.fn();
    const parser = createSSEParser(onEvent);

    parser.push('event: token\n');
    parser.push('data: {"delta":"oi"}\n');
    expect(onEvent).not.toHaveBeenCalled();

    parser.push('\n');
    expect(onEvent).toHaveBeenCalledTimes(1);
    expect(onEvent).toHaveBeenCalledWith(
      expect.objectContaining({ event: 'token', data: '{"delta":"oi"}' })
    );
  });

  it('preserves order across chunk boundaries that split a frame', () => {
    const events = [];
    const parser = createSSEParser(e => events.push(e));

    // The network can cut anywhere — mid field name, mid JSON.
    parser.push('event: tok');
    parser.push('en\ndata: {"delta":"a"}\n\nevent: token\nda');
    parser.push('ta: {"delta":"b"}\n\n');

    expect(events.map(e => e.data)).toEqual(['{"delta":"a"}', '{"delta":"b"}']);
  });

  it('joins multiple data lines with a newline', () => {
    const events = [];
    const parser = createSSEParser(e => events.push(e));
    parser.push('data: linha 1\ndata: linha 2\n\n');
    expect(events[0].data).toBe('linha 1\nlinha 2');
  });

  it('ignores comment/heartbeat lines', () => {
    const onEvent = vi.fn();
    const parser = createSSEParser(onEvent);
    parser.push(': keep-alive\n\n');
    expect(onEvent).not.toHaveBeenCalled();
  });

  it('captures id and retry fields', () => {
    const events = [];
    const parser = createSSEParser(e => events.push(e));
    parser.push('id: 7\nretry: 1500\nevent: token\ndata: x\n\n');
    expect(events[0]).toMatchObject({ id: '7', retry: 1500 });
  });

  it('carries the last id forward to following events', () => {
    const events = [];
    const parser = createSSEParser(e => events.push(e));
    parser.push('id: 1\ndata: a\n\ndata: b\n\n');
    expect(events[1].id).toBe('1');
  });

  it('normalizes CRLF line endings', () => {
    const events = [];
    const parser = createSSEParser(e => events.push(e));
    parser.push('event: done\r\ndata: {"finish_reason":"stop"}\r\n\r\n');
    expect(events[0].event).toBe('done');
  });

  it('flushes a trailing frame that never got its newline', () => {
    const events = [];
    const parser = createSSEParser(e => events.push(e));
    parser.push('event: done\ndata: {"finish_reason":"stop"}');
    expect(events).toHaveLength(0);
    parser.flush();
    expect(events).toHaveLength(1);
    expect(events[0].event).toBe('done');
  });

  it('defaults the event name to `message`', () => {
    const events = [];
    const parser = createSSEParser(e => events.push(e));
    parser.push('data: hello\n\n');
    expect(events[0].event).toBe('message');
  });
});

describe('parseEventData', () => {
  it('parses JSON payloads', () => {
    expect(parseEventData('{"delta":"x"}')).toEqual({ delta: 'x' });
  });

  it('returns null on malformed JSON instead of throwing', () => {
    expect(parseEventData('{oops')).toBeNull();
    expect(parseEventData('')).toBeNull();
  });
});
