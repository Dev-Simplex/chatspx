import { describe, it, expect, beforeEach, vi } from 'vitest';
import { mount } from '@vue/test-utils';

const h = vi.hoisted(() => ({
  messagesResponse: null,
  createResponse: null,
  createCalls: [],
  getCalls: [],
}));

vi.mock('dashboard/api/captain/copilotMessages', () => ({
  default: {
    get: threadId => {
      h.getCalls.push(threadId);
      if (h.messagesResponse instanceof Error) {
        return Promise.reject(h.messagesResponse);
      }
      return Promise.resolve({ data: h.messagesResponse });
    },
  },
}));

vi.mock('dashboard/api/captain/copilotThreads', () => ({
  default: {
    create: payload => {
      h.createCalls.push(payload);
      return Promise.resolve({ data: h.createResponse });
    },
  },
}));

vi.mock('dashboard/api/captain/copilotStream', () => ({
  accountIdFromRoute: () => '3',
}));

import {
  useCopilotThread,
  normalizeMessage,
  storeThreadId,
  getStoredThreadId,
  forgetThreadId,
  clearThreadCache,
} from '../useCopilotThread';

function withThread() {
  let api = null;
  const wrapper = mount({
    setup() {
      api = useCopilotThread();
      return () => null;
    },
  });
  return { api, wrapper };
}

const record = (id, type, content) => ({
  id,
  message_type: type,
  message: { content },
  created_at: id,
});

describe('useCopilotThread', () => {
  beforeEach(() => {
    window.localStorage.clear();
    clearThreadCache();
    h.messagesResponse = [];
    h.createResponse = { id: 77 };
    h.createCalls = [];
    h.getCalls = [];
  });

  it('starts empty when the conversation has no thread yet', async () => {
    const { api } = withThread();
    await api.loadForConversation(681);
    expect(api.threadId.value).toBeNull();
    expect(api.messages.value).toEqual([]);
    expect(api.isLoadingThread.value).toBe(false);
    expect(h.getCalls).toHaveLength(0);
  });

  it('loads the persisted history for a known thread', async () => {
    storeThreadId(681, 55);
    h.messagesResponse = [
      record(1, 'user', 'qual a política?'),
      record(2, 'assistant', 'acima de 30 dias...'),
    ];

    const { api } = withThread();
    await api.loadForConversation(681);

    expect(api.threadId.value).toBe(55);
    expect(api.messages.value.map(m => m.type)).toEqual(['user', 'assistant']);
    expect(api.messages.value[1].text).toBe('acima de 30 dias...');
    expect(api.isLoadingThread.value).toBe(false);
  });

  it('keeps the history when the agent switches away and comes back', async () => {
    storeThreadId(681, 55);
    h.messagesResponse = [record(1, 'user', 'oi')];

    const first = withThread();
    await first.api.loadForConversation(681);
    expect(h.getCalls).toHaveLength(1);

    // Another conversation, then back — served from cache, no second request.
    const second = withThread();
    await second.api.loadForConversation(999);
    await second.api.loadForConversation(681);

    expect(h.getCalls).toHaveLength(1);
    expect(second.api.messages.value).toHaveLength(1);
  });

  it('drops a thread that no longer exists instead of hanging', async () => {
    storeThreadId(681, 55);
    const notFound = new Error('gone');
    notFound.response = { status: 404 };
    h.messagesResponse = notFound;

    const { api } = withThread();
    await api.loadForConversation(681);

    expect(api.isLoadingThread.value).toBe(false);
    expect(api.threadId.value).toBeNull();
    expect(getStoredThreadId(681)).toBeNull();
  });

  it('creates the thread on first use and remembers it', async () => {
    const { api } = withThread();
    const created = await api.ensureThread({
      conversationId: 681,
      assistantId: 7,
      message: 'primeira pergunta',
    });

    expect(created).toBe(77);
    expect(getStoredThreadId(681)).toBe(77);
    expect(h.createCalls[0]).toMatchObject({
      message: 'primeira pergunta',
      assistant_id: 7,
      conversation_id: 681,
      skip_response: true,
    });
  });

  it('does not create a second thread once one exists', async () => {
    const { api } = withThread();
    await api.ensureThread({
      conversationId: 681,
      assistantId: 7,
      message: 'a',
    });
    await api.ensureThread({
      conversationId: 681,
      assistantId: 7,
      message: 'b',
    });
    expect(h.createCalls).toHaveLength(1);
  });

  it('truncateFrom drops the message and everything after it', async () => {
    const { api } = withThread();
    api.appendMessage(681, { id: 'a', type: 'user', text: '1' });
    api.appendMessage(681, { id: 'b', type: 'assistant', text: '2' });
    api.appendMessage(681, { id: 'c', type: 'user', text: '3' });

    api.truncateFrom(681, 'b');
    expect(api.messages.value.map(m => m.id)).toEqual(['a']);
  });

  it('reset forgets the thread so a new one is created', async () => {
    storeThreadId(681, 55);
    const { api } = withThread();
    await api.loadForConversation(681);
    api.reset(681);

    expect(api.threadId.value).toBeNull();
    expect(api.messages.value).toEqual([]);
    expect(getStoredThreadId(681)).toBeNull();
  });
});

describe('normalizeMessage', () => {
  it('maps a persisted record to the panel shape', () => {
    expect(normalizeMessage(record(9, 'assistant', 'texto'))).toMatchObject({
      id: 9,
      type: 'assistant',
      text: 'texto',
      persisted: true,
    });
  });

  it('hides `assistant_thinking` rows', () => {
    expect(normalizeMessage(record(9, 'assistant_thinking', '...'))).toBeNull();
  });
});

describe('thread id storage', () => {
  beforeEach(() => window.localStorage.clear());

  it('round-trips and forgets', () => {
    storeThreadId(1, 10);
    expect(getStoredThreadId(1)).toBe(10);
    forgetThreadId(1);
    expect(getStoredThreadId(1)).toBeNull();
  });

  it('survives a corrupted payload', () => {
    window.localStorage.setItem('chatspx_copilot_thread_map', 'not json');
    expect(getStoredThreadId(1)).toBeNull();
    storeThreadId(1, 3);
    expect(getStoredThreadId(1)).toBe(3);
  });
});
