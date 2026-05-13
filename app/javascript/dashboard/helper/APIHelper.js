import Auth from '../api/auth';

const parseErrorCode = error => Promise.reject(error);

// Guard: reports endpoints live in /api/v2 only. The v1 routes were removed
// in chatwoot#843; any caller hitting /api/v1/.../reports/* will get a 404.
// In development we warn so the wrong call site is caught early.
const V1_REPORTS_PATTERN = /\/api\/v1\/.*\/reports(\/|$|\?)/;

const warnOnV1ReportsCall = config => {
  if (process.env.NODE_ENV !== 'production') {
    const url = config?.url || '';
    if (V1_REPORTS_PATTERN.test(url)) {
      // eslint-disable-next-line no-console
      console.warn(
        `[ChatSPX] Deprecated /api/v1 reports endpoint requested: ${url}. ` +
          'Use ReportsAPI (v2) instead — v1 reports routes were removed.'
      );
    }
  }
  return config;
};

export default axios => {
  const { apiHost = '' } = window.chatwootConfig || {};
  const wootApi = axios.create({ baseURL: `${apiHost}/` });
  // Add Auth Headers to requests if logged in
  if (Auth.hasAuthCookie()) {
    const {
      'access-token': accessToken,
      'token-type': tokenType,
      client,
      expiry,
      uid,
    } = Auth.getAuthData();
    Object.assign(wootApi.defaults.headers.common, {
      'access-token': accessToken,
      'token-type': tokenType,
      client,
      expiry,
      uid,
    });
  }
  // Request interceptor — dev-only guard for v1 reports endpoints
  wootApi.interceptors.request.use(warnOnV1ReportsCall);
  // Response parsing interceptor
  wootApi.interceptors.response.use(
    response => response,
    error => parseErrorCode(error)
  );
  return wootApi;
};
