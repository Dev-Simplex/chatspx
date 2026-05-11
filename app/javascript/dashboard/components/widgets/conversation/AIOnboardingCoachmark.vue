<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  useTemplateRef,
} from 'vue';
import { useReducedMotion } from 'dashboard/composables/useReducedMotion';

const props = defineProps({
  /**
   * Reactive ref/templateRef pointing to the DOM element the coachmark
   * should attach to (the sparkles button). When the prop changes the
   * coachmark recalculates its position automatically.
   */
  anchorRef: {
    type: [Object, null],
    default: null,
  },
});

const emit = defineEmits(['confirm', 'dismiss']);

const COACHMARK_ID = 'ai-onboarding-coachmark';
const AUTO_DISMISS_MS = 8000;

const { prefersReducedMotion } = useReducedMotion();

const cardRef = useTemplateRef('cardRef');
const confirmButtonRef = useTemplateRef('confirmButtonRef');

const position = ref({ top: 0, left: 0, ready: false });

let autoDismissTimer = null;
let resizeObserver = null;
let previousFocus = null;

function getAnchorEl() {
  // anchorRef can be a templateRef (Vue 3) wrapping a DOM element,
  // a raw DOM node, or null while the component mounts.
  const anchor = props.anchorRef;
  if (!anchor) return null;
  if (anchor instanceof Element) return anchor;
  // Vue 3 templateRef: { value: el }
  if (anchor.value instanceof Element) return anchor.value;
  // Sometimes wrapping component → use $el
  if (anchor.$el instanceof Element) return anchor.$el;
  return null;
}

function recalcPosition() {
  const anchorEl = getAnchorEl();
  if (!anchorEl) return;
  const rect = anchorEl.getBoundingClientRect();
  const card = cardRef.value;
  const cardWidth = card?.offsetWidth || 288; // w-72 = 18rem ≈ 288px
  const cardHeight = card?.offsetHeight || 160;
  const margin = 12;

  // Place the card above the sparkles button by default, right-aligned.
  let top = rect.top - cardHeight - margin;
  let left = rect.right - cardWidth;

  // Clamp horizontally inside the viewport.
  const minLeft = 8;
  const maxLeft = window.innerWidth - cardWidth - 8;
  if (left < minLeft) left = minLeft;
  if (left > maxLeft) left = Math.max(minLeft, maxLeft);

  // If we ran out of room above, flip below the anchor.
  if (top < 8) {
    top = rect.bottom + margin;
  }

  position.value = { top, left, ready: true };
}

function focusConfirmButton() {
  nextTick(() => {
    confirmButtonRef.value?.focus();
  });
}

function returnFocusToAnchor() {
  const anchorEl = getAnchorEl();
  if (anchorEl && typeof anchorEl.focus === 'function') {
    anchorEl.focus();
  } else if (previousFocus && typeof previousFocus.focus === 'function') {
    previousFocus.focus();
  }
}

function clearAutoDismiss() {
  if (autoDismissTimer) {
    window.clearTimeout(autoDismissTimer);
    autoDismissTimer = null;
  }
}

function handleAutoDismiss() {
  clearAutoDismiss();
  emit('dismiss', 'auto');
  returnFocusToAnchor();
}

function handleConfirm() {
  clearAutoDismiss();
  emit('confirm');
  returnFocusToAnchor();
}

function handleDismiss(reason = 'manual') {
  clearAutoDismiss();
  emit('dismiss', reason);
  returnFocusToAnchor();
}

function handleKeydown(event) {
  if (event.key === 'Escape') {
    event.stopPropagation();
    handleDismiss('escape');
  }
}

function handleClickOutside(event) {
  const card = cardRef.value;
  const anchorEl = getAnchorEl();
  const target = event.target;
  if (!card) return;
  if (card.contains(target)) return;
  // clicking the anchor itself shouldn't dismiss — let the anchor handle.
  if (anchorEl && anchorEl.contains(target)) return;
  handleDismiss('outside');
}

const cardStyle = computed(() => {
  if (!position.value.ready) {
    return { visibility: 'hidden' };
  }
  return {
    top: `${position.value.top}px`,
    left: `${position.value.left}px`,
  };
});

const enterActiveClass = computed(() =>
  prefersReducedMotion.value
    ? 'transition-opacity duration-[80ms] ease-out'
    : 'transition-all duration-200 ease-out'
);
const enterFromClass = computed(() =>
  prefersReducedMotion.value ? 'opacity-0' : 'opacity-0 translate-y-2'
);
const enterToClass = computed(() =>
  prefersReducedMotion.value ? 'opacity-100' : 'opacity-100 translate-y-0'
);
const leaveActiveClass = 'transition-opacity duration-150 ease-in';
const leaveFromClass = 'opacity-100';
const leaveToClass = 'opacity-0';

onMounted(() => {
  previousFocus = document.activeElement;

  nextTick(() => {
    recalcPosition();
    focusConfirmButton();
  });

  window.addEventListener('resize', recalcPosition);
  window.addEventListener('scroll', recalcPosition, true);
  document.addEventListener('keydown', handleKeydown, true);
  document.addEventListener('mousedown', handleClickOutside, true);

  if ('ResizeObserver' in window) {
    resizeObserver = new ResizeObserver(() => recalcPosition());
    const anchorEl = getAnchorEl();
    if (anchorEl) resizeObserver.observe(anchorEl);
  }

  autoDismissTimer = window.setTimeout(handleAutoDismiss, AUTO_DISMISS_MS);
});

onBeforeUnmount(() => {
  clearAutoDismiss();
  window.removeEventListener('resize', recalcPosition);
  window.removeEventListener('scroll', recalcPosition, true);
  document.removeEventListener('keydown', handleKeydown, true);
  document.removeEventListener('mousedown', handleClickOutside, true);
  if (resizeObserver) {
    resizeObserver.disconnect();
    resizeObserver = null;
  }
});

defineExpose({ id: COACHMARK_ID });
</script>

<template>
  <Teleport to="body">
    <Transition
      appear
      :enter-active-class="enterActiveClass"
      :enter-from-class="enterFromClass"
      :enter-to-class="enterToClass"
      :leave-active-class="leaveActiveClass"
      :leave-from-class="leaveFromClass"
      :leave-to-class="leaveToClass"
    >
      <div
        :id="COACHMARK_ID"
        ref="cardRef"
        role="dialog"
        aria-modal="false"
        aria-labelledby="ai-onboarding-coachmark-title"
        aria-describedby="ai-onboarding-coachmark-body"
        data-testid="ai-onboarding-coachmark"
        class="fixed z-[60] w-72 rounded-xl border border-purple-200 bg-white p-4 shadow-xl dark:border-purple-700/40 dark:bg-slate-800"
        :style="cardStyle"
      >
        <span
          class="inline-block rounded bg-purple-600 px-2 py-0.5 text-xs font-semibold uppercase tracking-wide text-white"
        >
          {{ $t('COPILOT_ONBOARDING.BADGE') }}
        </span>
        <h3
          id="ai-onboarding-coachmark-title"
          class="mt-2 text-sm font-semibold text-slate-900 dark:text-slate-100"
        >
          {{ $t('COPILOT_ONBOARDING.TITLE') }}
        </h3>
        <p
          id="ai-onboarding-coachmark-body"
          class="mt-1 text-sm leading-relaxed text-slate-600 dark:text-slate-300"
        >
          {{ $t('COPILOT_ONBOARDING.BODY') }}
        </p>

        <div class="mt-4 flex items-center justify-end gap-2">
          <button
            type="button"
            class="rounded-md px-3 py-1.5 text-sm font-medium text-slate-600 transition-colors hover:bg-slate-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-purple-400 dark:text-slate-300 dark:hover:bg-slate-700"
            @click="handleDismiss('later')"
          >
            {{ $t('COPILOT_ONBOARDING.DISMISS') }}
          </button>
          <button
            ref="confirmButtonRef"
            type="button"
            class="rounded-md bg-purple-600 px-3 py-1.5 text-sm font-semibold text-white transition-colors hover:bg-purple-700 focus:outline-none focus-visible:ring-2 focus-visible:ring-purple-300 focus-visible:ring-offset-2"
            @click="handleConfirm"
          >
            {{ $t('COPILOT_ONBOARDING.CONFIRM') }}
          </button>
        </div>

        <span
          aria-hidden="true"
          class="absolute -bottom-2 right-6 h-3 w-3 rotate-45 border-b border-r border-purple-200 bg-white dark:border-purple-700/40 dark:bg-slate-800"
        />
      </div>
    </Transition>
  </Teleport>
</template>
