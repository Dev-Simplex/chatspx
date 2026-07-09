import { useFlowHistory } from '../useFlowHistory';

// Small helper for building distinct definition snapshots.
const def = overrides => ({ nodes: [], edges: [], ...overrides });

describe('useFlowHistory', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  describe('initial state', () => {
    it('starts clean with empty undo/redo stacks', () => {
      const history = useFlowHistory();
      expect(history.isDirty.value).toBe(false);
      expect(history.canUndo.value).toBe(false);
      expect(history.canRedo.value).toBe(false);
    });
  });

  describe('commit (baseline)', () => {
    it('sets the baseline and keeps the state clean', () => {
      const history = useFlowHistory();
      history.commit(def({ nodes: [{ id: 'n1' }] }));
      expect(history.isDirty.value).toBe(false);
      expect(history.canUndo.value).toBe(false);
      expect(history.canRedo.value).toBe(false);
    });
  });

  describe('record + debounce', () => {
    it('is a no-op when the definition did not actually change', () => {
      const history = useFlowHistory();
      const snapshot = def({ nodes: [{ id: 'n1' }] });
      history.commit(snapshot);
      history.record(snapshot);
      vi.advanceTimersByTime(500);
      expect(history.canUndo.value).toBe(false);
      expect(history.isDirty.value).toBe(false);
    });

    it('pushes one undo step only after the debounce flushes', () => {
      const history = useFlowHistory({ delay: 400 });
      history.commit(def());
      history.record(def({ nodes: [{ id: 'a' }] }));
      expect(history.canUndo.value).toBe(false); // still pending
      vi.advanceTimersByTime(400);
      expect(history.canUndo.value).toBe(true);
      expect(history.isDirty.value).toBe(true);
    });

    it('coalesces a burst of rapid edits into a single undo step', () => {
      const history = useFlowHistory({ delay: 400 });
      history.commit(def());
      history.record(def({ nodes: [{ id: 'a' }] }));
      vi.advanceTimersByTime(100);
      history.record(def({ nodes: [{ id: 'a' }, { id: 'b' }] }));
      vi.advanceTimersByTime(100);
      history.record(def({ nodes: [{ id: 'a' }, { id: 'b' }, { id: 'c' }] }));
      vi.advanceTimersByTime(400); // flush the whole burst at once

      expect(history.canUndo.value).toBe(true);
      // a single undo jumps straight back to the committed baseline
      expect(history.undo()).toEqual(def());
      expect(history.canUndo.value).toBe(false);
    });

    it('creates discrete steps for edits split by a flush', () => {
      const history = useFlowHistory({ delay: 400 });
      history.commit(def());
      history.record(def({ nodes: [{ id: 'a' }] }));
      vi.advanceTimersByTime(400); // flush burst 1
      history.record(def({ nodes: [{ id: 'a' }, { id: 'b' }] }));
      vi.advanceTimersByTime(400); // flush burst 2

      expect(history.undo()).toEqual(def({ nodes: [{ id: 'a' }] }));
      expect(history.undo()).toEqual(def());
      expect(history.canUndo.value).toBe(false);
    });
  });

  describe('undo / redo', () => {
    it('undo returns the previous snapshot and clears dirty at the baseline', () => {
      const history = useFlowHistory({ delay: 400 });
      history.commit(def());
      history.record(def({ nodes: [{ id: 'a' }] }));
      vi.advanceTimersByTime(400);

      const restored = history.undo();
      expect(restored).toEqual(def());
      expect(history.isDirty.value).toBe(false);
      expect(history.canUndo.value).toBe(false);
      expect(history.canRedo.value).toBe(true);
    });

    it('redo re-applies the undone snapshot', () => {
      const history = useFlowHistory({ delay: 400 });
      history.commit(def());
      const edited = def({ nodes: [{ id: 'a' }] });
      history.record(edited);
      vi.advanceTimersByTime(400);
      history.undo();

      const redone = history.redo();
      expect(redone).toEqual(edited);
      expect(history.isDirty.value).toBe(true);
      expect(history.canUndo.value).toBe(true);
      expect(history.canRedo.value).toBe(false);
    });

    it('undo returns null when there is nothing to undo', () => {
      const history = useFlowHistory();
      history.commit(def());
      expect(history.undo()).toBeNull();
    });

    it('redo returns null when there is nothing to redo', () => {
      const history = useFlowHistory();
      history.commit(def());
      expect(history.redo()).toBeNull();
    });

    it('undo flushes a still-pending burst before stepping back', () => {
      const history = useFlowHistory({ delay: 400 });
      history.commit(def());
      history.record(def({ nodes: [{ id: 'a' }] }));
      // intentionally do NOT advance timers — the burst is still pending
      const restored = history.undo();
      expect(restored).toEqual(def());
      expect(history.canRedo.value).toBe(true);
    });

    it('drops the redo stack once a new edit is recorded', () => {
      const history = useFlowHistory({ delay: 400 });
      history.commit(def());
      history.record(def({ nodes: [{ id: 'a' }] }));
      vi.advanceTimersByTime(400);
      history.undo();
      expect(history.canRedo.value).toBe(true);

      history.record(def({ nodes: [{ id: 'z' }] }));
      vi.advanceTimersByTime(400);
      expect(history.canRedo.value).toBe(false);
    });
  });

  describe('markSaved', () => {
    it('clears dirty while keeping the undo history intact', () => {
      const history = useFlowHistory({ delay: 400 });
      history.commit(def());
      const edited = def({ nodes: [{ id: 'a' }] });
      history.record(edited);
      vi.advanceTimersByTime(400);
      expect(history.isDirty.value).toBe(true);

      history.markSaved(edited);
      expect(history.isDirty.value).toBe(false);
      expect(history.canUndo.value).toBe(true); // history preserved
    });

    it('flushes a pending burst before marking the state saved', () => {
      const history = useFlowHistory({ delay: 400 });
      history.commit(def());
      const edited = def({ nodes: [{ id: 'a' }] });
      history.record(edited); // pending, not flushed
      history.markSaved(edited);
      expect(history.isDirty.value).toBe(false);
      expect(history.canUndo.value).toBe(true);
    });
  });

  describe('history limit', () => {
    it('caps the undo stack at the configured limit, dropping the oldest step', () => {
      const history = useFlowHistory({ delay: 400, limit: 2 });
      history.commit(def());
      history.record(def({ nodes: [{ id: '1' }] }));
      vi.advanceTimersByTime(400);
      history.record(def({ nodes: [{ id: '2' }] }));
      vi.advanceTimersByTime(400);
      history.record(def({ nodes: [{ id: '3' }] }));
      vi.advanceTimersByTime(400);

      // only the two most recent steps survive
      expect(history.undo()).toEqual(def({ nodes: [{ id: '2' }] }));
      expect(history.undo()).toEqual(def({ nodes: [{ id: '1' }] }));
      expect(history.undo()).toBeNull();
    });
  });
});
