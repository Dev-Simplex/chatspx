import { computed } from 'vue';

const MS_DAY = 24 * 60 * 60 * 1000;

const startOfDay = ts => {
  const d = new Date(ts * 1000);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
};

const dateLabel = (ts, t) => {
  const today = startOfDay(Date.now() / 1000);
  const itemDay = startOfDay(ts);
  const diff = (today - itemDay) / MS_DAY;

  if (diff === 0) return t('GALLERY.DATE.TODAY');
  if (diff === 1) return t('GALLERY.DATE.YESTERDAY');
  if (diff < 7) return t('GALLERY.DATE.THIS_WEEK');
  if (diff < 30) return t('GALLERY.DATE.THIS_MONTH');

  const d = new Date(ts * 1000);
  const sameYear = d.getFullYear() === new Date().getFullYear();
  const opts = sameYear
    ? { month: 'long' }
    : { month: 'long', year: 'numeric' };
  return d
    .toLocaleDateString('pt-BR', opts)
    .replace(/^\w/, c => c.toUpperCase());
};

export const formatTime = ts => {
  const d = new Date(ts * 1000);
  return d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
};

export const formatDateTime = ts => {
  const d = new Date(ts * 1000);
  return d.toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
};

export function useGroupedByDate(itemsRef, tFn) {
  return computed(() => {
    const items = itemsRef.value || [];
    if (!items.length) return [];

    const groups = new Map();
    items.forEach(item => {
      const ts = item.createdAt || 0;
      const key = startOfDay(ts);
      const label = dateLabel(ts, tFn);
      if (!groups.has(key)) {
        groups.set(key, { key, label, items: [] });
      }
      groups.get(key).items.push(item);
    });

    return Array.from(groups.values()).sort((a, b) => b.key - a.key);
  });
}
