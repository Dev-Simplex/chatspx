import { useStageColor } from '../useStageColor';

const HOUR = 3600 * 1000;
const MINUTE = 60 * 1000;

describe('useStageColor — waitSignal / waitSortKey', () => {
  const { waitSignal, waitSortKey } = useStageColor();
  const now = 1_700_000_000_000;

  beforeEach(() => {
    vi.spyOn(Date, 'now').mockReturnValue(now);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  const isoAgo = ms => new Date(now - ms).toISOString();

  describe('awaiting (waiting_since present)', () => {
    it('escalates the level by wait length', () => {
      expect(waitSignal(isoAgo(5 * MINUTE), null)).toMatchObject({
        kind: 'awaiting',
        level: 1,
      });
      expect(waitSignal(isoAgo(31 * MINUTE), null)).toMatchObject({
        kind: 'awaiting',
        level: 2,
      });
      expect(waitSignal(isoAgo(3 * HOUR), null)).toMatchObject({
        kind: 'awaiting',
        level: 3,
      });
      expect(waitSignal(isoAgo(9 * HOUR), null)).toMatchObject({
        kind: 'awaiting',
        level: 4,
      });
    });

    it('reports non-negative seconds and accepts unix seconds', () => {
      const unixSeconds = (now - 2 * HOUR) / 1000;
      const sig = waitSignal(unixSeconds, null);
      expect(sig.kind).toBe('awaiting');
      expect(sig.seconds).toBeCloseTo(7200, 0);
    });

    it('clamps a future waiting_since to zero seconds', () => {
      const sig = waitSignal(isoAgo(-HOUR), null);
      expect(sig.seconds).toBe(0);
      expect(sig.level).toBe(1);
    });
  });

  describe('stalled (no waiting_since, idle last activity)', () => {
    it('tiers by idle time and is none when fresh', () => {
      expect(waitSignal(null, isoAgo(2 * HOUR))).toMatchObject({
        kind: 'none',
        level: 0,
      });
      expect(waitSignal(null, isoAgo(9 * HOUR))).toMatchObject({
        kind: 'stalled',
        level: 1,
      });
      expect(waitSignal(null, isoAgo(25 * HOUR))).toMatchObject({
        kind: 'stalled',
        level: 2,
      });
      expect(waitSignal(null, isoAgo(80 * HOUR))).toMatchObject({
        kind: 'stalled',
        level: 3,
      });
    });
  });

  describe('null-safety', () => {
    it('returns none for missing/garbage inputs', () => {
      expect(waitSignal(null, null)).toEqual({
        kind: 'none',
        level: 0,
        seconds: 0,
      });
      expect(waitSignal('not-a-date', 'nope')).toEqual({
        kind: 'none',
        level: 0,
        seconds: 0,
      });
    });

    it('treats the numeric 0 "no-wait" sentinel as none (not 1970 epoch)', () => {
      expect(waitSignal(0, null)).toEqual({
        kind: 'none',
        level: 0,
        seconds: 0,
      });
      expect(waitSignal(null, 0)).toEqual({
        kind: 'none',
        level: 0,
        seconds: 0,
      });
      expect(waitSortKey(0, 0)).toBe(0);
    });
  });

  describe('waitSortKey banding', () => {
    it('orders awaiting > stalled > none, longest first within a band', () => {
      const awaitingShort = waitSortKey(isoAgo(MINUTE), null);
      const awaitingLong = waitSortKey(isoAgo(10 * HOUR), null);
      const stalled = waitSortKey(null, isoAgo(30 * HOUR));
      const none = waitSortKey(null, isoAgo(HOUR));

      expect(awaitingLong).toBeGreaterThan(awaitingShort);
      expect(awaitingShort).toBeGreaterThan(stalled);
      expect(stalled).toBeGreaterThan(none);
      expect(none).toBe(0);
    });
  });
});
