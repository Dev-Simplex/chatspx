// Tudo pelo barrel `date-fns`, e nao por `date-fns/format` (bloco 2.18): os
// dois caminhos resolvem para ARQUIVOS DIFERENTES do mesmo pacote (`/format/`
// e `/esm/format/`), e o bundle acabava com duas copias da biblioteca inteira
// no mesmo grafo — 176.811 B crus de pura duplicata, medidos.
import {
  endOfDay,
  format,
  fromUnixTime,
  getUnixTime,
  isToday,
  isYesterday,
  startOfDay,
} from 'date-fns';
import { ptBR } from 'date-fns/locale';

export const formatUnixDate = (date, dateFormat = 'MMM dd, yyyy') => {
  const unixDate = fromUnixTime(date);
  return format(unixDate, dateFormat);
};

export const formatDate = ({ date, todayText, yesterdayText }) => {
  const dateValue = new Date(date);
  if (isToday(dateValue)) return todayText;
  if (isYesterday(dateValue)) return yesterdayText;

  // Formata a data em português brasileiro
  return format(dateValue, "d 'de' MMMM 'de' yyyy", { locale: ptBR });
};

export const isTimeAfter = (h1, m1, h2, m2) => {
  if (h1 < h2) {
    return false;
  }

  if (h1 === h2) {
    return m1 >= m2;
  }

  return true;
};

/** Get start of day as a UNIX timestamp */
export const getUnixStartOfDay = date => getUnixTime(startOfDay(date));

/** Get end of day as a UNIX timestamp */
export const getUnixEndOfDay = date => getUnixTime(endOfDay(date));

export const generateRelativeTime = (value, unit, languageCode) => {
  const code = languageCode?.replace(/_/g, '-'); // Hacky fix we need to handle it from source
  const rtf = new Intl.RelativeTimeFormat(code, {
    numeric: 'auto',
  });
  return rtf.format(value, unit);
};
