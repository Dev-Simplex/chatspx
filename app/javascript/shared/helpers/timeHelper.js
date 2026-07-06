import {
  format,
  isSameYear,
  fromUnixTime,
  formatDistanceToNow,
  differenceInDays,
} from 'date-fns';
import { ptBR } from 'date-fns/locale';

/**
 * Formats a Unix timestamp into a human-readable time format.
 * @param {number} time - Unix timestamp.
 * @param {string} [dateFormat='h:mm a'] - Desired format of the time.
 * @returns {string} Formatted time string.
 */
export const messageStamp = (time, dateFormat = 'h:mm a') => {
  const unixTime = fromUnixTime(time);
  return format(unixTime, dateFormat);
};

/**
 * Provides a formatted timestamp, adjusting the format based on the current year.
 * @param {number} time - Unix timestamp.
 * @param {string} [dateFormat='MMM d, yyyy'] - Desired date format.
 * @returns {string} Formatted date string.
 */
export const messageTimestamp = (time, dateFormat = 'MMM d, yyyy') => {
  const messageTime = fromUnixTime(time);
  const now = new Date();
  const messageDate = format(messageTime, dateFormat);
  if (!isSameYear(messageTime, now)) {
    return format(messageTime, 'LLL d y, h:mm a');
  }
  return messageDate;
};

/**
 * Converts a Unix timestamp to a relative time string (e.g., há 3 horas).
 * @param {number} time - Unix timestamp.
 * @returns {string} Relative time string.
 */
export const dynamicTime = time => {
  const unixTime = fromUnixTime(time);
  return formatDistanceToNow(unixTime, { addSuffix: true, locale: ptBR });
};

/**
 * Formats a Unix timestamp into a specified date format.
 * @param {number} time - Unix timestamp.
 * @param {string} [dateFormat='MMM d, yyyy'] - Desired date format.
 * @returns {string} Formatted date string.
 */
export const dateFormat = (time, df = 'MMM d, yyyy') => {
  const unixTime = fromUnixTime(time);
  return format(unixTime, df);
};

/**
 * Timestamp compacto e INDEPENDENTE de locale para o card de conversa
 * (agora, 5m, 2h, 3d, e data para itens antigos). Necessário porque o
 * `dynamicTime` gera texto verboso em pt-BR ("há menos de um minuto") que
 * estoura o espaco reservado do card e sobrepoe o nome do contato.
 * @param {number} time - Unix timestamp em segundos.
 * @returns {string} Ex.: 'agora', '5m', '2h', '3d', '12/05/24'.
 */
export const shortTimeAgo = time => {
  const diffSeconds = Math.floor(Date.now() / 1000 - Number(time));
  if (!Number.isFinite(diffSeconds) || diffSeconds < 60) return 'agora';
  if (diffSeconds < 3600) return `${Math.floor(diffSeconds / 60)}m`;
  if (diffSeconds < 86400) return `${Math.floor(diffSeconds / 3600)}h`;
  if (diffSeconds < 2592000) return `${Math.floor(diffSeconds / 86400)}d`;
  return dateFormat(time, 'dd/MM/yy');
};

/**
 * Converts a detailed time description into a shorter format, optionally appending 'ago'.
 * @param {string} time - Detailed time description (e.g., 'a minute ago').
 * @param {boolean} [withAgo=false] - Whether to append 'ago' to the result.
 * @returns {string} Shortened time description.
 */
export const shortTimestamp = (time, withAgo = false) => {
  // This function takes a time string and converts it to a short time string
  // with the following format: 1m, 1h, 1d, 1mo, 1y
  // The function also takes an optional boolean parameter withAgo
  // which will add the word "ago" to the end of the time string
  const suffix = withAgo ? ' ago' : '';
  const timeMappings = {
    'less than a minute ago': 'now',
    'in less than a minute': 'now',
    'a minute ago': `1m${suffix}`,
    'an hour ago': `1h${suffix}`,
    'a day ago': `1d${suffix}`,
    'a month ago': `1mo${suffix}`,
    'a year ago': `1y${suffix}`,
  };
  // Check if the time string is one of the specific cases
  if (timeMappings[time]) {
    return timeMappings[time];
  }
  const convertToShortTime = time
    .replace(/about|over|almost|/g, '')
    .replace(' minute ago', `m${suffix}`)
    .replace(' minutes ago', `m${suffix}`)
    .replace(' hour ago', `h${suffix}`)
    .replace(' hours ago', `h${suffix}`)
    .replace(' day ago', `d${suffix}`)
    .replace(' days ago', `d${suffix}`)
    .replace(' month ago', `mo${suffix}`)
    .replace(' months ago', `mo${suffix}`)
    .replace(' year ago', `y${suffix}`)
    .replace(' years ago', `y${suffix}`);
  return convertToShortTime;
};

/**
 * Calculates the difference in days between now and a given timestamp.
 * @param {Date} now - Current date/time.
 * @param {number} timestampInSeconds - Unix timestamp in seconds.
 * @returns {number} Number of days difference.
 */
export const getDayDifferenceFromNow = (now, timestampInSeconds) => {
  const date = new Date(timestampInSeconds * 1000);
  return differenceInDays(now, date);
};

/**
 * Checks if more than 24 hours have passed since a given timestamp.
 * Useful for determining if retry/refresh actions should be disabled.
 * @param {number} timestamp - Unix timestamp.
 * @returns {boolean} True if more than 24 hours have passed.
 */
export const hasOneDayPassed = timestamp => {
  if (!timestamp) return true; // Defensive check
  return getDayDifferenceFromNow(new Date(), timestamp) >= 1;
};
