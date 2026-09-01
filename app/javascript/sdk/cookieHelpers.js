import md5 from 'md5';
import Cookies from 'js-cookie';

const REQUIRED_USER_KEYS = ['avatar_url', 'email', 'name'];
const ALLOWED_USER_ATTRIBUTES = [...REQUIRED_USER_KEYS, 'identifier_hash'];
const CONVERSATION_COOKIE = 'cw_conversation';
const CONVERSATION_TOKEN_TTL = 365 * 24 * 60 * 60 * 1000;

const getConversationStorageKey = websiteToken =>
  `${CONVERSATION_COOKIE}_${websiteToken}`;

const getStoredConversationToken = websiteToken => {
  if (!websiteToken) return undefined;

  try {
    const storedValue = window.localStorage.getItem(
      getConversationStorageKey(websiteToken)
    );
    if (!storedValue) return undefined;

    const { token, expiresAt } = JSON.parse(storedValue);
    if (token && expiresAt > Date.now()) return token;

    window.localStorage.removeItem(getConversationStorageKey(websiteToken));
  } catch {
    return undefined;
  }

  return undefined;
};

export const getUserCookieName = () => {
  const SET_USER_COOKIE_PREFIX = 'cw_user_';
  const { websiteToken: websiteIdentifier } = window.$chatwoot;
  return `${SET_USER_COOKIE_PREFIX}${websiteIdentifier}`;
};

export const getUserString = ({ identifier = '', user }) => {
  const userStringWithSortedKeys = ALLOWED_USER_ATTRIBUTES.reduce(
    (acc, key) => `${acc}${key}${user[key] || ''}`,
    ''
  );
  return `${userStringWithSortedKeys}identifier${identifier}`;
};

export const computeHashForUserData = (...args) => md5(getUserString(...args));

export const hasUserKeys = user =>
  REQUIRED_USER_KEYS.reduce((acc, key) => acc || !!user[key], false);

export const setCookieWithDomain = (
  name,
  value,
  { expires = 365, baseDomain = undefined } = {}
) => {
  const cookieOptions = {
    expires,
    sameSite: 'Lax',
    domain: baseDomain,
  };

  // if type of value is object, stringify it
  // this is because js-cookies 3.0 removed builtin json support
  // ref: https://github.com/js-cookie/js-cookie/releases/tag/v3.0.0
  if (typeof value === 'object') {
    value = JSON.stringify(value);
  }

  Cookies.set(name, value, cookieOptions);
};

export const getConversationToken = websiteToken =>
  Cookies.get(CONVERSATION_COOKIE) || getStoredConversationToken(websiteToken);

export const setConversationToken = (
  token,
  { baseDomain = undefined, websiteToken } = {}
) => {
  setCookieWithDomain(CONVERSATION_COOKIE, token, { baseDomain });

  if (!websiteToken) return;

  try {
    window.localStorage.setItem(
      getConversationStorageKey(websiteToken),
      JSON.stringify({
        token,
        expiresAt: Date.now() + CONVERSATION_TOKEN_TTL,
      })
    );
  } catch {
    // Third-party storage can be unavailable in strict privacy modes.
  }
};

export const removeConversationToken = websiteToken => {
  Cookies.remove(CONVERSATION_COOKIE);
  if (!websiteToken) return;

  try {
    window.localStorage.removeItem(getConversationStorageKey(websiteToken));
  } catch {
    // Keep reset functional when browser storage is unavailable.
  }
};
