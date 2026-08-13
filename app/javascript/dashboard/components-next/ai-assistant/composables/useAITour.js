import { ref } from 'vue';
import { useShepherd } from 'vue-shepherd';
import { useI18n } from 'vue-i18n';
import { toast } from 'vue-sonner';
import { useTrack } from 'dashboard/composables';

/**
 * AI Copilot 4-step guided tour. Triggered after the agent applies their
 * first AI suggestion (not on first login). Persists completion/skip state
 * via localStorage, supports resume of a paused tour, and silently skips
 * steps whose anchor is missing from the DOM (e.g. the suggestion chip is
 * only mounted in Phase 5).
 *
 * a11y:
 *   - shepherd.js v15 ships keyboard navigation by default (Tab through CTAs,
 *     Enter to confirm, Esc to cancel, ArrowLeft/Right between steps).
 *   - The visible body text mentions the anchor location ("the sparkles
 *     button at the bottom-right of the composer") so screen reader users
 *     can locate the target without relying on the visual arrow.
 *   - Focus returns to the previously focused element when the tour ends
 *     (default shepherd behavior).
 *   - prefers-reduced-motion is respected by shepherd.js v15 internally.
 *
 * Storage keys:
 *   - chatspx_ai_tour_v1: 'completed' | 'skipped' (terminal states)
 *   - chatspx_ai_tour_step: integer 0..3 (last step completed, used to resume)
 */

const STORAGE_KEY_DONE = 'chatspx_ai_tour_v1';
const STORAGE_KEY_STEP = 'chatspx_ai_tour_step';

function safeGetItem(key) {
  try {
    if (typeof window === 'undefined' || !window.localStorage) return null;
    return window.localStorage.getItem(key);
  } catch {
    return null;
  }
}

function safeSetItem(key, value) {
  try {
    if (typeof window === 'undefined' || !window.localStorage) return;
    window.localStorage.setItem(key, value);
  } catch {
    /* ignore */
  }
}

function safeRemoveItem(key) {
  try {
    if (typeof window === 'undefined' || !window.localStorage) return;
    window.localStorage.removeItem(key);
  } catch {
    /* ignore */
  }
}

export function useAITour() {
  const { t } = useI18n();
  const isActive = ref(false);

  function isCompleted() {
    const v = safeGetItem(STORAGE_KEY_DONE);
    return v === 'completed' || v === 'skipped';
  }

  function markCompleted(method = 'completed') {
    safeSetItem(STORAGE_KEY_DONE, method);
    safeRemoveItem(STORAGE_KEY_STEP);
  }

  function saveStep(stepNumber) {
    safeSetItem(STORAGE_KEY_STEP, String(stepNumber));
  }

  function getResumeStep() {
    const raw = safeGetItem(STORAGE_KEY_STEP);
    const step = parseInt(raw, 10);
    if (Number.isInteger(step) && step >= 0 && step <= 3) return step;
    return 0;
  }

  function trackStep(stepIndex, durationMs) {
    useTrack('ai.tour.step', {
      step: stepIndex + 1,
      time_on_step_ms: durationMs,
    });
  }

  function buildSteps(tour) {
    const stepDefs = [
      {
        id: 'sparkles',
        anchor: '[data-ai-tour="sparkles-button"]',
        on: 'top',
        title: t('AI_ASSISTANT_PANEL.TOUR.STEP_1.TITLE'),
        body: t('AI_ASSISTANT_PANEL.TOUR.STEP_1.BODY'),
      },
      {
        id: 'dropdown-first-item',
        anchor: '[data-ai-tour="dropdown-first-item"]',
        on: 'right',
        title: t('AI_ASSISTANT_PANEL.TOUR.STEP_2.TITLE'),
        body: t('AI_ASSISTANT_PANEL.TOUR.STEP_2.BODY'),
      },
      {
        id: 'suggestion-chip',
        anchor: '[data-ai-tour="suggestion-chip"]',
        on: 'top',
        title: t('AI_ASSISTANT_PANEL.TOUR.STEP_3.TITLE'),
        body: t('AI_ASSISTANT_PANEL.TOUR.STEP_3.BODY'),
      },
      {
        id: 'copilot-launcher',
        anchor: '[data-ai-tour="copilot-launcher"]',
        on: 'left',
        title: t('AI_ASSISTANT_PANEL.TOUR.STEP_4.TITLE'),
        body: t('AI_ASSISTANT_PANEL.TOUR.STEP_4.BODY'),
      },
    ];

    return stepDefs.map((def, index) => {
      const isLast = index === stepDefs.length - 1;
      const stepNumber = index + 1;
      const total = stepDefs.length;
      const stepLabel = t('AI_ASSISTANT_PANEL.TOUR.STEP_LABEL', {
        current: stepNumber,
        total,
        title: def.title,
      });

      // Body keeps original microcopy; the sr-only span carries the
      // step label so a screen reader announces "Passo N de 4: <title>"
      // without bloating the visible card.
      const text = `
        <span class="sr-only" role="status" aria-live="polite">${stepLabel}</span>
        <p>${def.body}</p>
      `;

      const buttons = [];
      if (!isLast) {
        buttons.push({
          text: t('AI_ASSISTANT_PANEL.TOUR.SKIP'),
          classes: 'shepherd-button-secondary',
          action() {
            markCompleted('skipped');
            useTrack('ai.tour.skipped', { step_skipped_at: stepNumber });
            // Toast informa que o tour pode ser retomado depois — só dispara
            // no Skip explícito (não no Esc/X, que pausam para resume).
            try {
              toast(t('AI_ASSISTANT_PANEL.TOUR.SKIP_TOAST'));
            } catch {
              /* toast unavailable in tests */
            }
            this.cancel();
          },
        });
        buttons.push({
          text: t('AI_ASSISTANT_PANEL.TOUR.NEXT'),
          action() {
            saveStep(stepNumber);
            this.next();
          },
        });
      } else {
        buttons.push({
          text: t('AI_ASSISTANT_PANEL.TOUR.FINISH'),
          action() {
            this.complete();
          },
        });
      }

      let stepStartedAt = 0;

      return {
        id: def.id,
        title: def.title,
        text,
        attachTo: { element: def.anchor, on: def.on },
        buttons,
        beforeShowPromise: () => {
          // Defensive: silently skip when anchor doesn't exist (chip not
          // mounted yet, dropdown closed, etc). Returning a rejected
          // Promise from beforeShowPromise tells shepherd to advance.
          if (typeof document === 'undefined') return Promise.resolve();
          const el = document.querySelector(def.anchor);
          if (!el) {
            // Move to next step in the next tick. If we're already on the
            // last step, complete the tour.
            setTimeout(() => {
              if (!tour) return;
              if (isLast) {
                tour.complete();
              } else {
                tour.next();
              }
            }, 0);
            return Promise.reject(new Error('anchor-missing'));
          }
          return Promise.resolve();
        },
        when: {
          show() {
            stepStartedAt = Date.now();
          },
          hide() {
            if (stepStartedAt) {
              trackStep(index, Date.now() - stepStartedAt);
              stepStartedAt = 0;
            }
          },
        },
      };
    });
  }

  function startTour({ resume = true } = {}) {
    if (typeof window === 'undefined') return null;
    if (isCompleted()) return null;
    if (isActive.value) return null;

    const tour = useShepherd({
      defaultStepOptions: {
        cancelIcon: {
          enabled: true,
          label: t('AI_ASSISTANT_PANEL.TOUR.CLOSE'),
        },
        canClickTarget: false,
        classes: 'shepherd-spx',
        scrollTo: { behavior: 'smooth', block: 'center' },
        modalOverlayOpeningPadding: 4,
      },
      useModalOverlay: true,
      exitOnEsc: true,
      keyboardNavigation: true,
    });

    const steps = buildSteps(tour);
    steps.forEach(step => tour.addStep(step));

    tour.on('cancel', () => {
      isActive.value = false;
      // Cancel via Esc/X = pause (step persisted in STORAGE_KEY_STEP).
      // Cancel via "Skip" button already calls markCompleted('skipped').
      // We do NOT clear STORAGE_KEY_STEP here so the next call with
      // `resume: true` resumes from the same place.
    });
    tour.on('complete', () => {
      isActive.value = false;
      markCompleted('completed');
      useTrack('ai.tour.completed', {});
    });

    isActive.value = true;
    useTrack('ai.tour.started', { resumed: resume });
    tour.start();

    if (resume) {
      const startFromStep = getResumeStep();
      if (startFromStep > 0 && startFromStep < steps.length) {
        tour.show(startFromStep);
      }
    }

    return tour;
  }

  return { isActive, startTour, markCompleted, isCompleted };
}
