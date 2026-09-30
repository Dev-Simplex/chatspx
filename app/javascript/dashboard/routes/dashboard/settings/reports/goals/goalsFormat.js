// CHAT-177: regras de exibição compartilhadas pela tela de Metas.

export const METRICS = [
  'resolved_conversations',
  'first_response_time',
  'nps',
  'kanban_wins',
];

// Cor por quanto da meta foi atingido: batida (>= 100%), perto (>= 70%), abaixo.
const TONES = {
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
  none: { key: null, text: 'text-n-slate-11', bar: 'bg-n-slate-6', pill: '' },
};

export const goalTone = attainment => {
  if (attainment == null) return TONES.none;
  if (attainment >= 1) return TONES.hit;
  if (attainment >= 0.7) return TONES.near;
  return TONES.below;
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

export const monthKey = date =>
  `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;

export const monthLabel = (key, locale) => {
  const [year, month] = key.split('-').map(Number);
  return new Intl.DateTimeFormat(locale.replace('_', '-'), {
    month: 'long',
    year: 'numeric',
  }).format(new Date(year, month - 1, 1));
};
