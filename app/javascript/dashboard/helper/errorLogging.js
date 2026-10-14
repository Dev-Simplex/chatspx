const teamAccessMessages = [
  'Esta conversa é de outro time. Só quem faz parte dele pode abri-la.',
  'You do not have permission to access this conversation.',
];

export const ignoreErrors = [
  'ResizeObserver loop completed with undelivered notifications',
  /^(?:AbortError: )?signal is aborted without reason$/,
  // Safari (iPhone) aborts pending requests when the page goes to background.
  /^(?:AbortError: )?Fetch is aborted$/,
  /^(?:Error: )?Esta conversa é de outro time\. Só quem faz parte dele pode abri-la\.$/,
  /^(?:Error: )?You do not have permission to access this conversation\.$/,
];

// No answer from the server, expired session, or the server being restarted or
// deployed: not product defects. 500, 403, 404 and 422 keep reaching the tracker.
const transientStatuses = [401, 502, 503, 504];
// Store actions often rethrow with `throw new Error(error)`, which keeps only the
// Axios text, or with the server message (Devise's expired-session 401).
const wrappedTransientMessages = [
  /^AxiosError: Network Error$/,
  /^AxiosError: Request failed with status code (?:401|502|503|504)$/,
  /^Você precisa entrar ou se cadastrar antes de continuar\.$/,
  /^You need to sign in or sign up before continuing\.$/,
];

const isTransientRequestError = error => {
  if (error?.isAxiosError) {
    return !error.response || transientStatuses.includes(error.response.status);
  }
  const message = typeof error === 'string' ? error : error?.message;
  return wrappedTransientMessages.some(pattern => pattern.test(message));
};

export const beforeSend = (event, hint) => {
  const error = hint?.originalException;
  if (isTransientRequestError(error)) return null;

  // A generic Axios 403 message cannot be filtered safely with ignoreErrors.
  // Only discard attachment requests denied by the conversation team guard.
  if (
    error?.response?.status === 403 &&
    error.config?.method === 'get' &&
    /\/conversations\/\d+\/attachments(?:\?.*)?$/.test(error.config?.url) &&
    teamAccessMessages.includes(error.response.data?.error)
  ) {
    return null;
  }

  return event;
};
