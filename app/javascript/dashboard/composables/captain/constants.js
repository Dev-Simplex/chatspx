export const CAPTAIN_ERROR_TYPES = Object.freeze({
  ABORTED: 'aborted',
  API_ERROR: 'api_error',
  HTTP_PREFIX: 'http_',
  ABORT_ERROR: 'AbortError',
  CANCELED_ERROR: 'CanceledError',
  // === Phase 2.5: granular client-side error matrix ===
  RATE_LIMIT: 'rate_limit',
  CAPTAIN_UNSTABLE: 'captain_unstable',
  TIMEOUT: 'timeout',
  EMPTY_RESPONSE: 'empty_response',
  NETWORK: 'network',
  PRIVATE_MODE_BLOCKED: 'private_mode_blocked',
});

export const CAPTAIN_GENERATION_FAILURE_REASONS = Object.freeze({
  EMPTY_RESPONSE: 'empty_response',
  EXCEPTION: 'exception',
});

// Operations that rewrite the agent's draft message. Blocked in NOTE
// (private) mode to prevent accidental leak of internal notes to the LLM —
// defense-in-depth pair with the backend `private: false` filter.
export const CAPTAIN_REWRITE_OPS = Object.freeze([
  'improve',
  'fix_spelling_grammar',
  'casual',
  'professional',
  'expand',
  'shorten',
  'make_friendly',
  'make_formal',
  'simplify',
  'confident',
  'straightforward',
  'friendly',
  'sentiment',
]);

// Client-side hard timeout in ms — Captain p99 is ~6s, >10s is almost always
// a stuck request worth surfacing to the user.
export const CAPTAIN_REQUEST_TIMEOUT_MS = 10_000;
