import { lastSeenText, whenText } from '../lastSeen';

const t = (key, params = {}) =>
  `${key}${Object.keys(params).length ? ` ${JSON.stringify(params)}` : ''}`;
const at = (y, mo, d, h, mi) =>
  Math.floor(new Date(y, mo - 1, d, h, mi).getTime() / 1000);
const now = new Date(2026, 9, 9, 15, 0);

describe('lastSeenText', () => {
  it('sem registro diz Offline', () => {
    expect(lastSeenText(t, null, now)).toBe('INTERNAL_CHAT.PRESENCE.OFFLINE');
  });
  it('hoje, ontem e data', () => {
    expect(lastSeenText(t, at(2026, 10, 9, 14, 32), now)).toBe(
      'INTERNAL_CHAT.LAST_SEEN.TODAY {"kind":"TODAY","time":"14:32"}'
    );
    expect(lastSeenText(t, at(2026, 10, 8, 9, 5), now)).toBe(
      'INTERNAL_CHAT.LAST_SEEN.YESTERDAY {"kind":"YESTERDAY","time":"09:05"}'
    );
    expect(lastSeenText(t, at(2026, 10, 3, 18, 0), now)).toBe(
      'INTERNAL_CHAT.LAST_SEEN.DATE {"kind":"DATE","date":"03/10","time":"18:00"}'
    );
    expect(lastSeenText(t, at(2025, 12, 31, 8, 0), now)).toBe(
      'INTERNAL_CHAT.LAST_SEEN.DATE {"kind":"DATE","date":"31/12/2025","time":"08:00"}'
    );
  });

  it('whenText sem o prefixo', () => {
    expect(whenText(t, at(2026, 10, 9, 14, 32), now)).toBe(
      'INTERNAL_CHAT.WHEN.TODAY {"kind":"TODAY","time":"14:32"}'
    );
    expect(whenText(t, null, now)).toBe('');
  });
});
