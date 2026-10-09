// Datas relativas do chat: "hoje às 14:32" / "ontem às 09:10" / "03/10 às 18:00".
const pad = n => String(n).padStart(2, '0');

const parts = (ts, now) => {
  const d = new Date(ts * 1000);
  const time = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  if (d.toDateString() === now.toDateString()) return { kind: 'TODAY', time };
  if (d.toDateString() === yesterday.toDateString())
    return { kind: 'YESTERDAY', time };
  const date =
    d.getFullYear() === now.getFullYear()
      ? `${pad(d.getDate())}/${pad(d.getMonth() + 1)}`
      : `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()}`;
  return { kind: 'DATE', date, time };
};

// "visto por último hoje às 14:32"; sem registro de presença: "Offline".
export const lastSeenText = (t, ts, now = new Date()) => {
  if (!ts) return t('INTERNAL_CHAT.PRESENCE.OFFLINE');
  const p = parts(ts, now);
  return t(`INTERNAL_CHAT.LAST_SEEN.${p.kind}`, p);
};

// "hoje às 14:32" (sem o "visto por último").
export const whenText = (t, ts, now = new Date()) => {
  if (!ts) return '';
  const p = parts(ts, now);
  return t(`INTERNAL_CHAT.WHEN.${p.kind}`, p);
};
