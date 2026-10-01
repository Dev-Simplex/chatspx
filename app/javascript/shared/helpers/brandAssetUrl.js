export const brandAssetUrl = (url, gitSha) =>
  url && gitSha
    ? `${url}${url.includes('?') ? '&' : '?'}v=${gitSha.slice(0, 10)}`
    : url;
