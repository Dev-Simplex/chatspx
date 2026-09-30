const teamAccessMessages = [
  'Esta conversa é de outro time. Só quem faz parte dele pode abri-la.',
  'You do not have permission to access this conversation.',
];

export const ignoreErrors = [
  'ResizeObserver loop completed with undelivered notifications',
  /^(?:AbortError: )?signal is aborted without reason$/,
  /^(?:Error: )?Esta conversa é de outro time\. Só quem faz parte dele pode abri-la\.$/,
  /^(?:Error: )?You do not have permission to access this conversation\.$/,
];

export const beforeSend = (event, hint) => {
  const error = hint?.originalException;
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
