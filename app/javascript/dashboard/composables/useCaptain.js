import { computed } from 'vue';
import {
  useFunctionGetter,
  useMapGetter,
  useStore,
} from 'dashboard/composables/store.js';
import { useAccount } from 'dashboard/composables/useAccount';
import { useConfig } from 'dashboard/composables/useConfig';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import { useAlert, useTrack } from 'dashboard/composables';
import { toast as sonnerToast } from 'vue-sonner';
import { useI18n } from 'vue-i18n';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import TasksAPI from 'dashboard/api/captain/tasks';
import {
  CAPTAIN_ERROR_TYPES,
  CAPTAIN_REWRITE_OPS,
  CAPTAIN_REQUEST_TIMEOUT_MS,
} from 'dashboard/composables/captain/constants';
import { sanitizePII } from 'dashboard/components-next/ai-assistant/utils/sanitizePII';

const REPLY_EDITOR_NOTE_MODE = 'NOTE';

/**
 * Combines an external AbortSignal with a client-side timeout signal.
 * `AbortSignal.any` is in Chrome 116+/Firefox 124+, fallback uses two listeners.
 *
 * @param {AbortSignal|undefined} externalSignal
 * @param {number} timeoutMs
 * @returns {{ signal: AbortSignal, cleanup: () => void, timeoutController: AbortController }}
 */
function buildTimeoutSignal(externalSignal, timeoutMs) {
  const timeoutController = new AbortController();
  const timeoutId = setTimeout(() => {
    timeoutController.abort(new DOMException('Timeout', 'TimeoutError'));
  }, timeoutMs);

  const cleanup = () => clearTimeout(timeoutId);

  if (
    typeof AbortSignal !== 'undefined' &&
    typeof AbortSignal.any === 'function' &&
    externalSignal
  ) {
    return {
      signal: AbortSignal.any([externalSignal, timeoutController.signal]),
      cleanup,
      timeoutController,
    };
  }

  if (!externalSignal) {
    return { signal: timeoutController.signal, cleanup, timeoutController };
  }

  // Manual fallback: forward external abort into timeoutController so callers
  // see a single signal. Timeout abort already fires through timeoutController.
  if (externalSignal.aborted) {
    timeoutController.abort(externalSignal.reason);
  } else {
    externalSignal.addEventListener(
      'abort',
      () => timeoutController.abort(externalSignal.reason),
      { once: true }
    );
  }

  return { signal: timeoutController.signal, cleanup, timeoutController };
}

/**
 * Classifies an error into the v2 granular error matrix.
 * Falls through to legacy `http_<status>` / `api_error` for unknown statuses
 * so backward-compatible callers keep working.
 *
 * @param {*} error
 * @returns {string}
 */
function classifyCaptainError(error) {
  if (!error) return CAPTAIN_ERROR_TYPES.API_ERROR;
  if (
    error.name === CAPTAIN_ERROR_TYPES.ABORT_ERROR ||
    error.name === CAPTAIN_ERROR_TYPES.CANCELED_ERROR ||
    error.name === 'TimeoutError' // DOMException from buildTimeoutSignal
  ) {
    // TimeoutError from our client timeout: surface as TIMEOUT, not aborted.
    if (error.name === 'TimeoutError') return CAPTAIN_ERROR_TYPES.TIMEOUT;
    return CAPTAIN_ERROR_TYPES.ABORTED;
  }
  if (error.code === 'ERR_NETWORK') return CAPTAIN_ERROR_TYPES.NETWORK;
  if (error.code === 'ECONNABORTED') return CAPTAIN_ERROR_TYPES.TIMEOUT;
  const status = error?.response?.status;
  if (status === 429) return CAPTAIN_ERROR_TYPES.RATE_LIMIT;
  if (status === 502 || status === 503) {
    return CAPTAIN_ERROR_TYPES.CAPTAIN_UNSTABLE;
  }
  if (status === 504) return CAPTAIN_ERROR_TYPES.TIMEOUT;
  if (status) return `${CAPTAIN_ERROR_TYPES.HTTP_PREFIX}${status}`;
  return CAPTAIN_ERROR_TYPES.API_ERROR;
}

export function useCaptain() {
  const store = useStore();
  const { t } = useI18n();
  const { isCloudFeatureEnabled, currentAccount } = useAccount();
  const { isEnterprise } = useConfig();
  const uiFlags = useMapGetter('accounts/getUIFlags');
  const currentChat = useMapGetter('getSelectedChat');
  const replyMode = useMapGetter('draftMessages/getReplyEditorMode');
  const conversationId = computed(() => currentChat.value?.id);
  const draftKey = computed(
    () => `draft-${conversationId.value}-${replyMode.value}`
  );
  const draftMessage = useFunctionGetter('draftMessages/get', draftKey);

  // === Feature Flags ===
  const captainEnabled = computed(() => {
    return isCloudFeatureEnabled(FEATURE_FLAGS.CAPTAIN);
  });

  const captainTasksEnabled = computed(() => {
    return isCloudFeatureEnabled(FEATURE_FLAGS.CAPTAIN_TASKS);
  });

  // === Limits (Enterprise) ===
  const captainLimits = computed(() => {
    return currentAccount.value?.limits?.captain;
  });

  const documentLimits = computed(() => {
    if (captainLimits.value?.documents) {
      return useCamelCase(captainLimits.value.documents);
    }
    return null;
  });

  const responseLimits = computed(() => {
    if (captainLimits.value?.responses) {
      return useCamelCase(captainLimits.value.responses);
    }
    return null;
  });

  const isFetchingLimits = computed(() => uiFlags.value.isFetchingLimits);

  const fetchLimits = () => {
    if (isEnterprise) {
      store.dispatch('accounts/limits');
    }
  };

  // === Error Handling ===
  /**
   * Handles API errors and displays appropriate error messages.
   * Silently returns for aborted requests so context-switch / user cancel
   * stays invisible.
   * @param {Error} error
   */
  const handleAPIError = error => {
    if (
      error.name === CAPTAIN_ERROR_TYPES.ABORT_ERROR ||
      error.name === CAPTAIN_ERROR_TYPES.CANCELED_ERROR
    ) {
      return;
    }
    const errorMessage =
      error.response?.data?.error ||
      t('INTEGRATION_SETTINGS.OPEN_AI.GENERATE_ERROR');
    useAlert(errorMessage);
  };

  /**
   * Public alias kept for backward compatibility — same as `classifyCaptainError`.
   * @param {Error} error
   * @returns {string}
   */
  const getErrorType = error => classifyCaptainError(error);

  // === Telemetry helpers ===
  /**
   * Wraps a Captain API call with timeout, telemetry and granular error
   * classification. Returns a normalized `{ message, errorType, latencyMs }`
   * shape — `errorType === null` on success.
   *
   * @param {string} eventName — Captain task name for telemetry
   * @param {Function} apiCall — receives the merged AbortSignal
   * @param {AbortSignal} [externalSignal]
   * @returns {Promise<{ data?: any, errorType: string|null, latencyMs: number }>}
   */
  const callWithTelemetry = async (eventName, apiCall, externalSignal) => {
    const { signal, cleanup } = buildTimeoutSignal(
      externalSignal,
      CAPTAIN_REQUEST_TIMEOUT_MS
    );
    const t0 =
      typeof performance !== 'undefined' && performance.now
        ? performance.now()
        : Date.now();
    try {
      const result = await apiCall(signal);
      const latencyMs = Math.round(
        (typeof performance !== 'undefined' && performance.now
          ? performance.now()
          : Date.now()) - t0
      );
      const message = result?.data?.message;
      const isEmpty = message === '' || message == null;

      if (isEmpty) {
        useTrack('ai.captain.error', {
          code: CAPTAIN_ERROR_TYPES.EMPTY_RESPONSE,
          event: eventName,
          latency_ms: latencyMs,
        });
        return {
          data: result?.data,
          errorType: CAPTAIN_ERROR_TYPES.EMPTY_RESPONSE,
          latencyMs,
        };
      }

      useTrack('ai.captain.responded', {
        event: eventName,
        latency_ms: latencyMs,
        streamed: false,
      });
      return { data: result.data, errorType: null, latencyMs };
    } catch (error) {
      const errorType = classifyCaptainError(error);
      const latencyMs = Math.round(
        (typeof performance !== 'undefined' && performance.now
          ? performance.now()
          : Date.now()) - t0
      );
      if (errorType !== CAPTAIN_ERROR_TYPES.ABORTED) {
        useTrack('ai.captain.error', {
          code: errorType,
          event: eventName,
          latency_ms: latencyMs,
        });
        handleAPIError(error);
      }
      return { error, errorType, latencyMs };
    } finally {
      cleanup();
    }
  };

  /**
   * Defense-in-depth: blocks AI rewrite operations when the composer is in
   * NOTE (private) mode to prevent the internal note from being sent to
   * Captain. Backend service also filters `private: true` messages from
   * the LLM context — both layers must hold.
   * @param {string} type
   * @returns {boolean}
   */
  const isBlockedByPrivateMode = type => {
    return (
      replyMode.value === REPLY_EDITOR_NOTE_MODE &&
      CAPTAIN_REWRITE_OPS.includes(type)
    );
  };

  // === Task Methods ===
  /**
   * Rewrites content with a specific operation. Sanitizes PII before sending.
   */
  const rewriteContent = async (content, operation, options = {}) => {
    const rawContent = content || draftMessage.value || '';
    const { clean, redactions } = sanitizePII(rawContent);
    if (redactions.length) {
      useTrack('ai.pii.redacted', {
        count: redactions.length,
        types: [...new Set(redactions.map(r => r.name))],
        event: 'rewrite',
      });
    }

    const { data, errorType } = await callWithTelemetry(
      `rewrite.${operation}`,
      sig =>
        TasksAPI.rewrite(
          {
            content: clean,
            operation,
            conversationId: conversationId.value,
          },
          sig
        ),
      options.signal
    );

    if (!data) return { message: '', errorType };
    return {
      message: data.message,
      followUpContext: data.follow_up_context,
      errorType,
    };
  };

  /**
   * Summarizes the active conversation.
   */
  const summarizeConversation = async (options = {}) => {
    const { data, errorType } = await callWithTelemetry(
      'summarize',
      sig => TasksAPI.summarize(conversationId.value, sig),
      options.signal
    );
    if (!data) return { message: '', errorType };
    return {
      message: data.message,
      followUpContext: data.follow_up_context,
      errorType,
    };
  };

  /**
   * Gets a reply suggestion for the current conversation.
   */
  const getReplySuggestion = async (options = {}) => {
    const { data, errorType } = await callWithTelemetry(
      'reply_suggestion',
      sig => TasksAPI.replySuggestion(conversationId.value, sig),
      options.signal
    );
    if (!data) return { message: '', errorType };
    return {
      message: data.message,
      followUpContext: data.follow_up_context,
      errorType,
    };
  };

  /**
   * Analyzes the customer's emotional tone in the conversation.
   */
  const analyzeSentiment = async (options = {}) => {
    const { data, errorType } = await callWithTelemetry(
      'sentiment_analysis',
      sig => TasksAPI.sentimentAnalysis(conversationId.value, sig),
      options.signal
    );
    if (!data) return { message: '', errorType };
    return {
      message: data.message,
      followUpContext: data.follow_up_context,
      errorType,
    };
  };

  /**
   * Sends a follow-up message to refine a previous AI task result.
   */
  const followUp = async ({ followUpContext, message, signal }) => {
    const { clean, redactions } = sanitizePII(message);
    if (redactions.length) {
      useTrack('ai.pii.redacted', {
        count: redactions.length,
        types: [...new Set(redactions.map(r => r.name))],
        event: 'follow_up',
      });
    }

    const { data, errorType } = await callWithTelemetry(
      'follow_up',
      sig =>
        TasksAPI.followUp(
          {
            followUpContext,
            message: clean,
            conversationId: conversationId.value,
          },
          sig
        ),
      signal
    );

    if (!data) {
      return { message: '', followUpContext, errorType };
    }
    return {
      message: data.message,
      followUpContext: data.follow_up_context,
      errorType,
    };
  };

  /**
   * Routes an AI event to the correct task method. Enforces the private-mode
   * guard for rewrite-style operations.
   */
  const processEvent = async (type = 'improve', content = '', options = {}) => {
    if (isBlockedByPrivateMode(type)) {
      useTrack('ai.private_mode.blocked', { type });
      sonnerToast.error(
        t('CONVERSATION.AI_ASSISTANT_PANEL.TOAST.PRIVATE_MODE_BLOCKED'),
        { important: true }
      );
      return {
        message: '',
        errorType: CAPTAIN_ERROR_TYPES.PRIVATE_MODE_BLOCKED,
      };
    }

    if (type === 'summarize') {
      return summarizeConversation(options);
    }
    if (type === 'reply_suggestion') {
      return getReplySuggestion(options);
    }
    if (type === 'sentiment') {
      return analyzeSentiment(options);
    }
    return rewriteContent(content, type, options);
  };

  return {
    // Feature flags
    captainEnabled,
    captainTasksEnabled,

    // Limits (Enterprise)
    captainLimits,
    documentLimits,
    responseLimits,
    fetchLimits,
    isFetchingLimits,

    // Conversation context
    draftMessage,
    currentChat,

    // Error helpers (exported for tests / direct callers)
    getErrorType,
    classifyCaptainError,

    // Task methods
    rewriteContent,
    summarizeConversation,
    getReplySuggestion,
    analyzeSentiment,
    followUp,
    processEvent,
  };
}
