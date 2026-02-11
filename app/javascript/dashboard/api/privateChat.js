/* global axios */

const getBaseUrl = accountId =>
  `/api/v1/accounts/${accountId}/private_chat`;

export const unlock = (accountId, password) =>
  axios.post(`${getBaseUrl(accountId)}/unlock`, { password });

export const getMessages = (accountId, token, params = {}) =>
  axios.get(`${getBaseUrl(accountId)}/messages`, {
    params,
    headers: { Authorization: `Bearer ${token}` },
  });

export const createMessage = (accountId, token, payload) =>
  axios.post(`${getBaseUrl(accountId)}/messages`, payload, {
    headers: { Authorization: `Bearer ${token}` },
  });

export const clearMessages = (accountId, token) =>
  axios.post(`${getBaseUrl(accountId)}/clear`, {}, {
    headers: { Authorization: `Bearer ${token}` },
  });
