// Formatacao dos relatorios em linguagem de gente: "8 min 17 s" (e nao "8 Min 17 Sec"), no maximo duas
// unidades, e variacoes grandes em "vezes" (e nao "5422%").

const MINUTE = 60;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

// "95,5%" (virgula decimal, no maximo uma casa) e nao "95.45%".
export const formatPercent = value =>
  `${Number(value || 0).toLocaleString(undefined, { maximumFractionDigits: 1 })}%`;

// t: o `t` do vue-i18n. Chaves em REPORT.TIME.
export const formatDuration = (seconds, t) => {
  const total = Math.round(Number(seconds) || 0);
  if (total <= 0) return t('REPORT.TIME.ZERO');
  if (total < MINUTE) return t('REPORT.TIME.SECONDS', { s: total });

  if (total < HOUR) {
    const min = Math.floor(total / MINUTE);
    const s = total % MINUTE;
    // Acima de 10 minutos, os segundos so atrapalham a leitura.
    return s && min < 10
      ? t('REPORT.TIME.MINUTES_SECONDS', { min, s })
      : t('REPORT.TIME.MINUTES', { min });
  }

  if (total < DAY) {
    const h = Math.floor(total / HOUR);
    const min = Math.floor((total % HOUR) / MINUTE);
    return min
      ? t('REPORT.TIME.HOURS_MINUTES', { h, min })
      : t('REPORT.TIME.HOURS', { h });
  }

  const d = Math.floor(total / DAY);
  const h = Math.floor((total % DAY) / HOUR);
  return h
    ? t('REPORT.TIME.DAYS_HOURS', { d, h }, d)
    : t('REPORT.TIME.DAYS', { d }, d);
};

// +150% = "2,5 vezes"; acima de 10 vezes, sem casa decimal.
export const timesFromPct = pct => {
  const times = (Math.abs(pct) + 100) / 100;
  return times.toLocaleString(undefined, {
    maximumFractionDigits: times >= 10 ? 0 : 1,
  });
};

// Variacao percentual por extenso. Acima de +100% vira "N vezes" — ninguem le "5422%".
// Devolve { text, direction: 'up' | 'down' | 'same' }.
export const formatChange = (pct, t) => {
  const value = Math.round(Number(pct) || 0);
  if (value === 0) return { text: t('REPORT.CHANGE.SAME'), direction: 'same' };
  if (value >= 100) {
    return {
      text: t('REPORT.CHANGE.TIMES_MORE', { times: timesFromPct(value) }),
      direction: 'up',
    };
  }
  return value > 0
    ? { text: t('REPORT.CHANGE.MORE', { pct: value }), direction: 'up' }
    : { text: t('REPORT.CHANGE.LESS', { pct: -value }), direction: 'down' };
};

// O sistema grava o nome do time em minusculas (e o funil de um setor herda esse nome): "rh" vira "Rh",
// "demonstracao app store" vira "Demonstracao App Store". So sobe a inicial de cada palavra.
export const teamDisplayName = name =>
  (name || '').replace(
    /(^|[\s(])(\p{Ll})/gu,
    (_, space, letter) => `${space}${letter.toUpperCase()}`
  );
