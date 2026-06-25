import { getters } from '../../conversationStats';

describe('#getters', () => {
  it('getCurrentPage', () => {
    const state = {
      mineCount: 1,
      unAssignedCount: 1,
      allCount: 2,
    };
    expect(getters.getStats(state)).toEqual({
      mineCount: 1,
      unAssignedCount: 1,
      allCount: 2,
    });
  });

  describe('getUnAssignedCount', () => {
    it('returns the numeric unassigned count', () => {
      expect(getters.getUnAssignedCount({ unAssignedCount: 5 })).toBe(5);
    });

    it('falls back to 0 when the count is missing/undefined (avoids NaN badge)', () => {
      expect(getters.getUnAssignedCount({})).toBe(0);
      expect(getters.getUnAssignedCount({ unAssignedCount: undefined })).toBe(
        0
      );
    });
  });

  describe('getAwaitingCount', () => {
    it('returns the numeric awaiting count for the sidebar badge', () => {
      expect(getters.getAwaitingCount({ awaitingCount: 7 })).toBe(7);
    });

    it('falls back to 0 when the count is missing/undefined (avoids NaN badge)', () => {
      expect(getters.getAwaitingCount({})).toBe(0);
      expect(getters.getAwaitingCount({ awaitingCount: undefined })).toBe(0);
    });
  });
});
