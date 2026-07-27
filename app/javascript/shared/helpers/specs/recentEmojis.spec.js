import {
  getRecentEmojis,
  addRecentEmoji,
  MAX_RECENT_EMOJIS,
  RECENT_EMOJIS_STORAGE_KEY,
} from '../recentEmojis';

describe('recentEmojis', () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  describe('#getRecentEmojis', () => {
    it('returns an empty list when nothing was stored', () => {
      expect(getRecentEmojis()).toEqual([]);
    });

    it('returns an empty list when the stored value is not an array', () => {
      window.localStorage.setItem(
        RECENT_EMOJIS_STORAGE_KEY,
        JSON.stringify({ not: 'an array' })
      );
      expect(getRecentEmojis()).toEqual([]);
    });

    it('discards entries that are not usable emojis', () => {
      window.localStorage.setItem(
        RECENT_EMOJIS_STORAGE_KEY,
        JSON.stringify(['😄', '', null, 42, '🎉'])
      );
      expect(getRecentEmojis()).toEqual(['😄', '🎉']);
    });
  });

  describe('#addRecentEmoji', () => {
    it('stores the emoji and returns the updated list', () => {
      expect(addRecentEmoji('😄')).toEqual(['😄']);
      expect(getRecentEmojis()).toEqual(['😄']);
    });

    it('keeps the most recent emoji first', () => {
      addRecentEmoji('😄');
      addRecentEmoji('🎉');
      expect(getRecentEmojis()).toEqual(['🎉', '😄']);
    });

    it('moves an already used emoji to the top instead of duplicating it', () => {
      addRecentEmoji('😄');
      addRecentEmoji('🎉');
      addRecentEmoji('😄');
      expect(getRecentEmojis()).toEqual(['😄', '🎉']);
    });

    it('caps the list at MAX_RECENT_EMOJIS, dropping the oldest', () => {
      const emojis = Array.from(
        { length: MAX_RECENT_EMOJIS + 5 },
        (_, index) => `e${index}`
      );
      emojis.forEach(emoji => addRecentEmoji(emoji));

      const stored = getRecentEmojis();
      expect(stored).toHaveLength(MAX_RECENT_EMOJIS);
      expect(stored[0]).toEqual(emojis[emojis.length - 1]);
      expect(stored).not.toContain('e0');
    });

    it('ignores the empty value sent by the picker remove button', () => {
      addRecentEmoji('😄');
      expect(addRecentEmoji('')).toEqual(['😄']);
      expect(getRecentEmojis()).toEqual(['😄']);
    });

    it('ignores non string values', () => {
      expect(addRecentEmoji(undefined)).toEqual([]);
      expect(getRecentEmojis()).toEqual([]);
    });

    it('does not throw when the storage write fails', () => {
      const setItem = vi
        .spyOn(Storage.prototype, 'setItem')
        .mockImplementation(() => {
          throw new Error('QuotaExceededError');
        });

      expect(() => addRecentEmoji('😄')).not.toThrow();
      setItem.mockRestore();
    });
  });
});
