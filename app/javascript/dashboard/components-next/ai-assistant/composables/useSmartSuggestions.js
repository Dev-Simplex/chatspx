import { computed, onMounted, onBeforeUnmount, ref } from 'vue';
import { useDismissedSuggestions } from './useDismissedSuggestions';

/**
 * Reactive smart-suggestion resolver for the Copilot panel banner.
 *
 * Inspects the current conversation (length, last incoming/outgoing message,
 * and an optional sentiment hint persisted in `additional_attributes`) and
 * returns the most relevant non-dismissed banner, if any.
 *
 * Priority (highest → lowest):
 *   1. waiting     — customer waiting > WAITING_THRESHOLD_MIN since last
 *                    incoming message (and agent has not replied since)
 *   2. sentiment   — `additional_attributes.sentiment === 'negative'`
 *   3. long_thread — message count > LONG_THREAD_THRESHOLD
 *
 * Each suggestion can be dismissed per-conversation via `dismiss(id)`. The
 * dismissal is persisted by `useDismissedSuggestions` (7-day TTL).
 *
 * The composable installs a 30 s tick interval so the `waiting` minute count
 * re-evaluates without depending on store mutations. Cleanup happens on
 * `onBeforeUnmount` — the panel is mounted only when open, so the interval
 * is short-lived.
 */

const LONG_THREAD_THRESHOLD = 10;
const WAITING_THRESHOLD_MIN = 5;
const TICK_INTERVAL_MS = 30_000;

function resolveTimestampMs(value) {
  if (!value) return null;
  // Captain payloads send seconds-since-epoch; some surfaces use ms.
  // Anything before year 2001 (10^12 ms) is assumed seconds.
  const num = Number(value);
  if (!Number.isFinite(num) || num <= 0) return null;
  return num < 1e12 ? num * 1000 : num;
}

export function useSmartSuggestions(conversationRef) {
  const dismissed = useDismissedSuggestions();
  const tick = ref(0);
  let interval = null;

  onMounted(() => {
    if (typeof window === 'undefined' || typeof setInterval !== 'function') {
      return;
    }
    interval = setInterval(() => {
      tick.value += 1;
    }, TICK_INTERVAL_MS);
  });

  onBeforeUnmount(() => {
    if (interval) {
      clearInterval(interval);
      interval = null;
    }
  });

  const messageCount = computed(() => {
    const msgs = conversationRef.value?.messages;
    return Array.isArray(msgs) ? msgs.length : 0;
  });

  const lastIncomingAt = computed(() => {
    const msgs = conversationRef.value?.messages || [];
    for (let i = msgs.length - 1; i >= 0; i -= 1) {
      const m = msgs[i];
      if (m && m.message_type === 0) return resolveTimestampMs(m.created_at);
    }
    return null;
  });

  const lastOutgoingAt = computed(() => {
    const msgs = conversationRef.value?.messages || [];
    for (let i = msgs.length - 1; i >= 0; i -= 1) {
      const m = msgs[i];
      if (m && m.message_type === 1) return resolveTimestampMs(m.created_at);
    }
    return null;
  });

  const customerWaitingMinutes = computed(() => {
    // Reactive dependency on tick so this re-evaluates every 30 s.
    // eslint-disable-next-line no-unused-vars
    const _ = tick.value;
    if (!lastIncomingAt.value) return 0;
    if (lastOutgoingAt.value && lastOutgoingAt.value > lastIncomingAt.value) {
      return 0;
    }
    return Math.max(
      0,
      Math.floor((Date.now() - lastIncomingAt.value) / 60_000)
    );
  });

  const sentimentHint = computed(
    () => conversationRef.value?.additional_attributes?.sentiment || null
  );

  const activeSuggestion = computed(() => {
    // eslint-disable-next-line no-unused-vars
    const _ = tick.value;
    const convId = conversationRef.value?.id;
    if (!convId) return null;

    if (
      customerWaitingMinutes.value >= WAITING_THRESHOLD_MIN &&
      !dismissed.isDismissed(convId, 'waiting')
    ) {
      return {
        id: 'waiting',
        severity: 'urgent',
        icon: 'i-lucide-clock',
        textKey: 'CONVERSATION.AI_ASSISTANT_PANEL.SMART_BANNER.WAITING.BODY',
        textParams: { minutes: customerWaitingMinutes.value },
        ctaKey: 'CONVERSATION.AI_ASSISTANT_PANEL.SMART_BANNER.WAITING.CTA',
        action: 'reply_suggestion',
      };
    }

    if (
      sentimentHint.value === 'negative' &&
      !dismissed.isDismissed(convId, 'sentiment')
    ) {
      return {
        id: 'sentiment',
        severity: 'warning',
        icon: 'i-lucide-alert-triangle',
        textKey: 'CONVERSATION.AI_ASSISTANT_PANEL.SMART_BANNER.SENTIMENT.BODY',
        textParams: {},
        ctaKey: 'CONVERSATION.AI_ASSISTANT_PANEL.SMART_BANNER.SENTIMENT.CTA',
        action: 'reply_suggestion',
      };
    }

    if (
      messageCount.value > LONG_THREAD_THRESHOLD &&
      !dismissed.isDismissed(convId, 'long_thread')
    ) {
      return {
        id: 'long_thread',
        severity: 'info',
        icon: 'i-lucide-sparkles',
        textKey:
          'CONVERSATION.AI_ASSISTANT_PANEL.SMART_BANNER.LONG_THREAD.BODY',
        textParams: { count: messageCount.value },
        ctaKey: 'CONVERSATION.AI_ASSISTANT_PANEL.SMART_BANNER.LONG_THREAD.CTA',
        action: 'summarize',
      };
    }

    return null;
  });

  function dismiss(suggestionId) {
    const convId = conversationRef.value?.id;
    if (convId) dismissed.add(convId, suggestionId);
    // Force re-evaluation by bumping the tick so consumers re-read.
    tick.value += 1;
  }

  return {
    activeSuggestion,
    dismiss,
    customerWaitingMinutes,
    messageCount,
  };
}

export const SMART_SUGGESTIONS_THRESHOLDS = Object.freeze({
  LONG_THREAD_THRESHOLD,
  WAITING_THRESHOLD_MIN,
  TICK_INTERVAL_MS,
});
