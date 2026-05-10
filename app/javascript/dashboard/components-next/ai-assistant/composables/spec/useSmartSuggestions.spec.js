import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { ref, defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';

import { useSmartSuggestions } from '../useSmartSuggestions';

// `useDismissedSuggestions` is exercised via real localStorage in this test
// suite — no need to mock it, the storage is cleared between tests below.

const NOW = new Date('2026-01-15T12:00:00Z').getTime();

function buildConversation({ id = 1, messages = [], sentiment = null } = {}) {
  return ref({
    id,
    messages,
    additional_attributes: sentiment ? { sentiment } : {},
  });
}

function makeMessage({ type = 0, ageMs = 0 } = {}) {
  return {
    message_type: type,
    created_at: Math.floor((NOW - ageMs) / 1000), // seconds
  };
}

function mountWithComposable(conversationRef, capture) {
  const Probe = defineComponent({
    setup() {
      const composable = useSmartSuggestions(conversationRef);
      capture(composable);
      return () => h('div');
    },
  });
  return mount(Probe);
}

describe('useSmartSuggestions', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(NOW);
    window.localStorage.clear();
  });

  afterEach(() => {
    vi.useRealTimers();
    window.localStorage.clear();
  });

  it('returns null when conversation has no messages and no triggers', () => {
    const conv = buildConversation({ messages: [] });
    let captured;
    const wrapper = mountWithComposable(conv, c => {
      captured = c;
    });
    expect(captured.activeSuggestion.value).toBeNull();
    wrapper.unmount();
  });

  it('does not surface long_thread for 9 messages (just below threshold)', () => {
    const messages = Array.from({ length: 9 }, () => makeMessage());
    const conv = buildConversation({ messages });
    let captured;
    const wrapper = mountWithComposable(conv, c => {
      captured = c;
    });
    expect(captured.activeSuggestion.value).toBeNull();
    wrapper.unmount();
  });

  it('does not surface long_thread for exactly 10 messages (boundary)', () => {
    const messages = Array.from({ length: 10 }, () => makeMessage());
    const conv = buildConversation({ messages });
    let captured;
    const wrapper = mountWithComposable(conv, c => {
      captured = c;
    });
    expect(captured.activeSuggestion.value).toBeNull();
    wrapper.unmount();
  });

  it('surfaces long_thread for 11 messages', () => {
    const messages = Array.from({ length: 11 }, () => makeMessage());
    const conv = buildConversation({ messages });
    let captured;
    const wrapper = mountWithComposable(conv, c => {
      captured = c;
    });
    expect(captured.activeSuggestion.value).toMatchObject({
      id: 'long_thread',
      severity: 'info',
      action: 'summarize',
    });
    expect(captured.activeSuggestion.value.textParams.count).toBe(11);
    wrapper.unmount();
  });

  it('long_thread persists for 23 messages', () => {
    const messages = Array.from({ length: 23 }, () => makeMessage());
    const conv = buildConversation({ messages });
    let captured;
    const wrapper = mountWithComposable(conv, c => {
      captured = c;
    });
    expect(captured.activeSuggestion.value.id).toBe('long_thread');
    expect(captured.activeSuggestion.value.textParams.count).toBe(23);
    wrapper.unmount();
  });

  it('handles 1000 messages without throwing or stalling', () => {
    const messages = Array.from({ length: 1000 }, () => makeMessage());
    const conv = buildConversation({ messages });
    let captured;
    const wrapper = mountWithComposable(conv, c => {
      captured = c;
    });
    expect(captured.activeSuggestion.value.id).toBe('long_thread');
    expect(captured.messageCount.value).toBe(1000);
    wrapper.unmount();
  });

  it('dismiss() hides the long_thread banner for the same conversation', () => {
    const messages = Array.from({ length: 11 }, () => makeMessage());
    const conv = buildConversation({ id: 42, messages });
    let captured;
    const wrapper = mountWithComposable(conv, c => {
      captured = c;
    });
    expect(captured.activeSuggestion.value.id).toBe('long_thread');
    captured.dismiss('long_thread');
    expect(captured.activeSuggestion.value).toBeNull();
    wrapper.unmount();
  });

  it('surfaces sentiment banner when conversation has negative sentiment', () => {
    const messages = Array.from({ length: 5 }, () => makeMessage());
    const conv = buildConversation({
      messages,
      sentiment: 'negative',
    });
    let captured;
    const wrapper = mountWithComposable(conv, c => {
      captured = c;
    });
    expect(captured.activeSuggestion.value).toMatchObject({
      id: 'sentiment',
      severity: 'warning',
      action: 'reply_suggestion',
    });
    wrapper.unmount();
  });

  it('waiting banner surfaces when last incoming is older than threshold', () => {
    // Single incoming message 6 minutes old.
    const messages = [makeMessage({ type: 0, ageMs: 6 * 60 * 1000 })];
    const conv = buildConversation({ messages });
    let captured;
    const wrapper = mountWithComposable(conv, c => {
      captured = c;
    });
    expect(captured.activeSuggestion.value).toMatchObject({
      id: 'waiting',
      severity: 'urgent',
      action: 'reply_suggestion',
    });
    expect(captured.activeSuggestion.value.textParams.minutes).toBe(6);
    wrapper.unmount();
  });

  it('waiting banner is suppressed if agent already replied after the customer', () => {
    // Customer message 6min ago, agent reply 1min ago.
    const messages = [
      makeMessage({ type: 0, ageMs: 6 * 60 * 1000 }),
      makeMessage({ type: 1, ageMs: 1 * 60 * 1000 }),
    ];
    const conv = buildConversation({ messages });
    let captured;
    const wrapper = mountWithComposable(conv, c => {
      captured = c;
    });
    // Waiting must be null; since there are 2 messages no other trigger.
    expect(captured.activeSuggestion.value).toBeNull();
    wrapper.unmount();
  });

  it('waiting takes priority over long_thread + sentiment', () => {
    // 12 incoming messages oldest 6min ago, sentiment negative.
    const messages = [
      makeMessage({ type: 0, ageMs: 6 * 60 * 1000 }),
      ...Array.from({ length: 11 }, () => makeMessage({ ageMs: 0 })),
    ];
    // Re-set last incoming to be 6min old by overriding the LAST incoming
    // explicitly (the array's last incoming is what counts).
    messages[messages.length - 1] = makeMessage({
      type: 0,
      ageMs: 6 * 60 * 1000,
    });
    const conv = buildConversation({ messages, sentiment: 'negative' });
    let captured;
    const wrapper = mountWithComposable(conv, c => {
      captured = c;
    });
    expect(captured.activeSuggestion.value.id).toBe('waiting');
    wrapper.unmount();
  });

  it('falls back to next-priority banner when waiting is dismissed', () => {
    const messages = [
      // 12 incoming messages, last is 6min old → waiting + long_thread
      ...Array.from({ length: 11 }, () => makeMessage({ type: 0, ageMs: 0 })),
      makeMessage({ type: 0, ageMs: 6 * 60 * 1000 }),
    ];
    const conv = buildConversation({ id: 7, messages });
    let captured;
    const wrapper = mountWithComposable(conv, c => {
      captured = c;
    });
    expect(captured.activeSuggestion.value.id).toBe('waiting');
    captured.dismiss('waiting');
    expect(captured.activeSuggestion.value.id).toBe('long_thread');
    wrapper.unmount();
  });
});
