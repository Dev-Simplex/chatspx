// CHAT-177: regras de exibição compartilhadas pela tela de Metas.

export const METRICS = [
  'resolved_conversations',
  'first_response_time',
  'nps',
  'kanban_wins',
];

// Cor por quanto da meta foi atingido: batida (>= 100%), perto (>= 70%), abaixo.
export const TONES = {
  hit: {
    key: 'HIT',
    text: 'text-n-teal-11',
    bar: 'bg-n-teal-9',
    pill: 'bg-n-teal-3 text-n-teal-11',
  },
  near: {
    key: 'NEAR',
    text: 'text-n-amber-11',
    bar: 'bg-n-amber-9',
    pill: 'bg-n-amber-3 text-n-amber-11',
  },
  below: {
    key: 'BELOW',
    text: 'text-n-ruby-11',
    bar: 'bg-n-ruby-9',
    pill: 'bg-n-ruby-3 text-n-ruby-11',
  },
  onPace: {
    key: 'ON_PACE',
    text: 'text-n-blue-11',
    bar: 'bg-n-blue-9',
    pill: 'bg-n-blue-3 text-n-blue-11',
  },
  behind: {
    key: 'BEHIND',
    text: 'text-n-amber-11',
    bar: 'bg-n-amber-9',
    pill: 'bg-n-amber-3 text-n-amber-11',
  },
  start: {
    key: 'START',
    text: 'text-n-slate-12',
    bar: 'bg-n-slate-9',
    pill: 'bg-n-alpha-2 text-n-slate-11',
  },
  none: { key: null, text: 'text-n-slate-11', bar: 'bg-n-slate-6', pill: '' },
};

// Indicadores que somam ao longo do mês: só eles têm ritmo e projeção. Tempo e NPS são médias.
export const CUMULATIVE = ['resolved_conversations', 'kanban_wins'];
const LOWER_IS_BETTER = ['first_response_time'];
// Antes disso a projeção dá saltos (1 conversa no dia 1 viraria 3100%).
const PROJECTION_FROM_DAY = 5;
// Mesmo teto da nota geral no servidor (PerformanceGoals::Scoring::CAP).
const CAP = 1.5;

export const goalTone = attainment => {
  if (attainment == null) return TONES.none;
  if (attainment >= 1) return TONES.hit;
  if (attainment >= 0.7) return TONES.near;
  return TONES.below;
};

export const monthKey = date =>
  `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;

// Onde o mês corrente está (dia de hoje incluído). null para mês fechado.
export const monthProgress = (key, date) => {
  if (key !== monthKey(date)) return null;
  const days = new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate();
  const day = date.getDate();
  return { day, days, left: days - day, fraction: day / days };
};

// Quanto já devia ter sido feito até hoje para fechar a meta no último dia.
export const pace = (metric, data, progress) => {
  if (!progress || !CUMULATIVE.includes(metric)) return null;
  if (data?.goal == null || data?.actual == null) return null;
  const expected = Math.floor(data.goal * progress.fraction);
  return { expected, onPace: data.actual >= expected };
};

// Situação de um indicador: batida > (mês corrente) no ritmo/atrás > perto/abaixo.
export const metricTone = (metric, data, progress) => {
  const attainment = data?.attainment;
  if (attainment == null || attainment >= 1) return goalTone(attainment);
  const rhythm = pace(metric, data, progress);
  if (rhythm) return rhythm.onPace ? TONES.onPace : TONES.behind;
  return goalTone(attainment);
};

// Percentual que o indicador fecha o mês se mantiver o ritmo.
const projected = (metric, attainment, progress) =>
  CUMULATIVE.includes(metric) ? attainment / progress.fraction : attainment;

export const projectedOverall = (metrics, progress) => {
  if (!progress || progress.day < PROJECTION_FROM_DAY) return null;
  const values = Object.entries(metrics || {})
    .filter(([, data]) => data.attainment != null)
    .map(([metric, data]) =>
      Math.min(projected(metric, data.attainment, progress), CAP)
    );
  if (!values.length) return null;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
};

// Situação da linha: no mês corrente vale a projeção; nos primeiros dias, neutro.
export const overallTone = (row, progress) => {
  if (row?.overall == null || row.overall >= 1 || !progress) {
    return goalTone(row?.overall);
  }
  const projection = projectedOverall(row.metrics, progress);
  if (projection == null) return TONES.start;
  if (projection >= 1) return TONES.onPace;
  return goalTone(projection);
};

export const goalsHit = metrics => {
  const values = Object.values(metrics || {}).filter(m => m.attainment != null);
  return {
    hit: values.filter(m => m.attainment >= 1).length,
    total: values.length,
  };
};

// Distância até a meta na unidade do indicador: positiva = falta, negativa = passou.
export const gap = (metric, data) => {
  if (data?.goal == null || data?.actual == null) return null;
  const diff = LOWER_IS_BETTER.includes(metric)
    ? data.actual - data.goal
    : data.goal - data.actual;
  return Math.round(diff * 10) / 10;
};

// Intl direto: o `n()` do vue-i18n com opções soltas quebra sem numberFormats configurado.
export const formatMetric = (metric, value, locale) => {
  const formatted = new Intl.NumberFormat(locale.replace('_', '-'), {
    maximumFractionDigits: metric === 'first_response_time' ? 1 : 0,
  }).format(Number(value));
  return metric === 'first_response_time' ? `${formatted} min` : formatted;
};

export const percentLabel = attainment =>
  attainment == null ? null : `${Math.round(attainment * 100)}%`;

export const monthLabel = (key, locale) => {
  const [year, month] = key.split('-').map(Number);
  return new Intl.DateTimeFormat(locale.replace('_', '-'), {
    month: 'long',
    year: 'numeric',
  }).format(new Date(year, month - 1, 1));
};
