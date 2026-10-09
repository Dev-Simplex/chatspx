// "visto por último hoje às 14:32" / "ontem às 09:10" / "em 03/10 às 18:00".
// Sem registro de presença: "Offline".
const pad = n => String(n).padStart(2, '0');

export const lastSeenText = (t, ts, now = new Date()) => {
  if (!ts) return t('INTERNAL_CHAT.PRESENCE.OFFLINE');
  const d = new Date(ts * 1000);
  const time = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  if (d.toDateString() === now.toDateString())
    return t('INTERNAL_CHAT.LAST_SEEN.TODAY', { time });
  if (d.toDateString() === yesterday.toDateString())
    return t('INTERNAL_CHAT.LAST_SEEN.YESTERDAY', { time });
  const date =
    d.getFullYear() === now.getFullYear()
      ? `${pad(d.getDate())}/${pad(d.getMonth() + 1)}`
      : `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()}`;
  return t('INTERNAL_CHAT.LAST_SEEN.DATE', { date, time });
};
