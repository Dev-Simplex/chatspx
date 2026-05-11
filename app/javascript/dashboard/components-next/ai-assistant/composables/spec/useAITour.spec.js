import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

// vue-shepherd / shepherd.js is heavy and not the unit under test here —
// we mock it so we can assert on the persistence + branching logic of
// `useAITour` without spinning the real tour DOM up.
const tourInstances = [];

vi.mock('vue-shepherd', () => {
  return {
    useShepherd: vi.fn(() => {
      const tour = {
        addStep: vi.fn(),
        start: vi.fn(),
        next: vi.fn(),
        show: vi.fn(),
        complete: vi.fn(),
        cancel: vi.fn(),
        on: vi.fn(),
      };
      tourInstances.push(tour);
      return tour;
    }),
  };
});

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => {
      if (params) return `${key}:${JSON.stringify(params)}`;
      return key;
    },
  }),
}));

vi.mock('dashboard/composables', () => ({
  useTrack: vi.fn(),
}));

const sonnerToast = vi.fn();
vi.mock('vue-sonner', () => ({
  toast: (...args) => sonnerToast(...args),
}));

import { useAITour } from '../useAITour';

const STORAGE_KEY_DONE = 'chatspx_ai_tour_v1';
const STORAGE_KEY_STEP = 'chatspx_ai_tour_step';

describe('useAITour', () => {
  beforeEach(() => {
    tourInstances.length = 0;
    window.localStorage.clear();
    sonnerToast.mockClear();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('persistence', () => {
    it('isCompleted returns false when storage is empty', () => {
      const { isCompleted } = useAITour();
      expect(isCompleted()).toBe(false);
    });

    it('isCompleted returns true when storage flagged as completed', () => {
      window.localStorage.setItem(STORAGE_KEY_DONE, 'completed');
      const { isCompleted } = useAITour();
      expect(isCompleted()).toBe(true);
    });

    it('isCompleted returns true when storage flagged as skipped', () => {
      window.localStorage.setItem(STORAGE_KEY_DONE, 'skipped');
      const { isCompleted } = useAITour();
      expect(isCompleted()).toBe(true);
    });

    it('markCompleted persists the method and clears step', () => {
      window.localStorage.setItem(STORAGE_KEY_STEP, '2');
      const { markCompleted, isCompleted } = useAITour();

      markCompleted('skipped');

      expect(window.localStorage.getItem(STORAGE_KEY_DONE)).toBe('skipped');
      expect(window.localStorage.getItem(STORAGE_KEY_STEP)).toBeNull();
      expect(isCompleted()).toBe(true);
    });
  });

  describe('startTour', () => {
    it('returns null when tour was already completed', () => {
      window.localStorage.setItem(STORAGE_KEY_DONE, 'completed');
      const { startTour, isActive } = useAITour();

      const tour = startTour({ resume: false });

      expect(tour).toBeNull();
      expect(isActive.value).toBe(false);
      expect(tourInstances).toHaveLength(0);
    });

    it('returns null when tour was already skipped', () => {
      window.localStorage.setItem(STORAGE_KEY_DONE, 'skipped');
      const { startTour } = useAITour();

      expect(startTour({ resume: false })).toBeNull();
    });

    it('creates a tour with 4 steps and starts it when fresh', () => {
      const { startTour, isActive } = useAITour();

      const tour = startTour({ resume: false });

      expect(tour).not.toBeNull();
      expect(tourInstances).toHaveLength(1);
      expect(tour.addStep).toHaveBeenCalledTimes(4);
      expect(tour.start).toHaveBeenCalledTimes(1);
      expect(isActive.value).toBe(true);
    });

    it('does not jump ahead when resume=false even if a step was saved', () => {
      window.localStorage.setItem(STORAGE_KEY_STEP, '2');
      const { startTour } = useAITour();

      const tour = startTour({ resume: false });

      expect(tour.show).not.toHaveBeenCalled();
    });

    it('jumps to saved step when resume=true', () => {
      window.localStorage.setItem(STORAGE_KEY_STEP, '2');
      const { startTour } = useAITour();

      const tour = startTour({ resume: true });

      expect(tour.show).toHaveBeenCalledWith(2);
    });

    it('does not call show when no step is saved on resume', () => {
      const { startTour } = useAITour();

      const tour = startTour({ resume: true });

      expect(tour.show).not.toHaveBeenCalled();
    });

    it('does not start a second tour if one is already active', () => {
      const { startTour } = useAITour();

      const first = startTour({ resume: false });
      const second = startTour({ resume: false });

      expect(first).not.toBeNull();
      expect(second).toBeNull();
      expect(tourInstances).toHaveLength(1);
    });
  });

  describe('cancel handling', () => {
    it('marks completed only when triggered via Skip button', () => {
      const { startTour } = useAITour();
      const tour = startTour({ resume: false });

      // Find the Skip button on the first step (skipped via action()).
      const firstStep = tour.addStep.mock.calls[0][0];
      const skipButton = firstStep.buttons.find(
        b => b.classes === 'shepherd-button-secondary'
      );

      // The button.action is bound to the tour via `this`; mimic that.
      skipButton.action.call({
        cancel: () => tour.cancel(),
      });

      expect(window.localStorage.getItem(STORAGE_KEY_DONE)).toBe('skipped');
    });

    it('shows a vue-sonner toast informing the agent how to resume', () => {
      const { startTour } = useAITour();
      const tour = startTour({ resume: false });

      const firstStep = tour.addStep.mock.calls[0][0];
      const skipButton = firstStep.buttons.find(
        b => b.classes === 'shepherd-button-secondary'
      );

      skipButton.action.call({ cancel: () => tour.cancel() });

      expect(sonnerToast).toHaveBeenCalledTimes(1);
      // The toast key is the i18n SKIP_TOAST key (the test mock returns the
      // key as-is) — confirms the right copy is wired up.
      expect(sonnerToast).toHaveBeenCalledWith(
        'CONVERSATION.AI_ASSISTANT_PANEL.TOUR.SKIP_TOAST'
      );
    });

    it('saves step when Next is pressed', () => {
      const { startTour } = useAITour();
      const tour = startTour({ resume: false });

      const firstStep = tour.addStep.mock.calls[0][0];
      const nextButton = firstStep.buttons.find(
        b => b.classes !== 'shepherd-button-secondary'
      );

      nextButton.action.call({ next: () => tour.next() });

      expect(window.localStorage.getItem(STORAGE_KEY_STEP)).toBe('1');
    });
  });

  describe('last step', () => {
    it('only renders a Finish button on the last step', () => {
      const { startTour } = useAITour();
      const tour = startTour({ resume: false });

      const lastStep =
        tour.addStep.mock.calls[tour.addStep.mock.calls.length - 1][0];

      expect(lastStep.buttons).toHaveLength(1);
      expect(lastStep.buttons[0].classes).toBeUndefined();
    });
  });
});
