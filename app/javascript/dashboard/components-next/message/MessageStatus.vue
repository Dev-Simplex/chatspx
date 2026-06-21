<script setup>
import { computed, ref } from 'vue';
import { useIntervalFn } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { MESSAGE_STATUS } from './constants';

import Icon from 'next/icon/Icon.vue';

const { status } = defineProps({
  status: {
    type: String,
    required: true,
    validator: value => Object.values(MESSAGE_STATUS).includes(value),
  },
});

const { t } = useI18n();

const progresIconSequence = [
  'i-lucide-clock-1',
  'i-lucide-clock-2',
  'i-lucide-clock-3',
  'i-lucide-clock-4',
  'i-lucide-clock-5',
  'i-lucide-clock-6',
  'i-lucide-clock-7',
  'i-lucide-clock-8',
  'i-lucide-clock-9',
  'i-lucide-clock-10',
  'i-lucide-clock-11',
  'i-lucide-clock-12',
];

const progessIcon = ref(progresIconSequence[0]);

const rotateIcon = () => {
  const currentIndex = progresIconSequence.indexOf(progessIcon.value);
  const nextIndex = (currentIndex + 1) % progresIconSequence.length;
  progessIcon.value = progresIconSequence[nextIndex];
};

useIntervalFn(rotateIcon, 500, {
  immediate: status === MESSAGE_STATUS.PROGRESS,
  immediateCallback: false,
});

const isProgress = computed(() => status === MESSAGE_STATUS.PROGRESS);
// Single tick for sent; double tick for delivered/read.
const isDouble = computed(
  () => status === MESSAGE_STATUS.DELIVERED || status === MESSAGE_STATUS.READ
);
const isRead = computed(() => status === MESSAGE_STATUS.READ);

const tooltipText = computed(() => {
  const statusTextMap = {
    [MESSAGE_STATUS.SENT]: t('CHAT_LIST.SENT'),
    [MESSAGE_STATUS.DELIVERED]: t('CHAT_LIST.DELIVERED'),
    [MESSAGE_STATUS.READ]: t('CHAT_LIST.MESSAGE_READ'),
    [MESSAGE_STATUS.PROGRESS]: t('CHAT_LIST.SENDING'),
  };

  return statusTextMap[status];
});
</script>

<template>
  <span v-tooltip.top-start="tooltipText" class="message-status">
    <!--
      Morph between the sending clock and the delivery ticks. `out-in` lets the
      clock fade/shrink out before the ticks pop/draw in, reading as a single
      ⏰→✓ transform rather than a hard swap. All timings come from the shared
      --motion-* tokens, so prefers-reduced-motion collapses them to a fade.
    -->
    <Transition name="ms-morph" mode="out-in">
      <Icon
        v-if="isProgress"
        key="progress"
        :icon="progessIcon"
        class="text-n-slate-10"
      />
      <span
        v-else
        :key="isRead ? 'read' : isDouble ? 'delivered' : 'sent'"
        class="ms-ticks"
        :class="{ 'ms-ticks--read': isRead }"
      >
        <!-- Base (grey) ticks. -->
        <svg
          class="ms-svg ms-svg--base"
          viewBox="0 0 18 12"
          fill="none"
          aria-hidden="true"
        >
          <path
            class="ms-check ms-check--front"
            d="M1 6.5 L4.6 10 L12 2"
            pathLength="1"
          />
          <path
            v-if="isDouble"
            class="ms-check ms-check--back"
            d="M6.4 6.5 L10 10 L17.4 2"
            pathLength="1"
          />
        </svg>
        <!--
          Blue overlay, revealed with a left→right clip-path wipe only when the
          message is read. The grey layer stays beneath so a missed frame still
          shows valid ticks (state never depends on the animation alone).
        -->
        <svg
          v-if="isRead"
          class="ms-svg ms-svg--read"
          viewBox="0 0 18 12"
          fill="none"
          aria-hidden="true"
        >
          <path class="ms-check" d="M1 6.5 L4.6 10 L12 2" pathLength="1" />
          <path class="ms-check" d="M6.4 6.5 L10 10 L17.4 2" pathLength="1" />
        </svg>
      </span>
    </Transition>
  </span>
</template>

<style scoped lang="scss">
.message-status {
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

// --- Morph transition (clock <-> ticks) -------------------------------------
.ms-morph-enter-active {
  transition:
    opacity var(--motion-fast, 160ms) var(--ease-out-expo, ease-out),
    transform var(--motion-base, 240ms) var(--ease-out-back, ease-out);
}
.ms-morph-leave-active {
  transition:
    opacity var(--motion-instant, 80ms) ease,
    transform var(--motion-fast, 160ms) var(--ease-in-out-quart, ease);
}
.ms-morph-enter-from {
  opacity: 0;
  transform: scale(0.6);
}
.ms-morph-leave-to {
  opacity: 0;
  transform: scale(0.85);
}

// --- Ticks ------------------------------------------------------------------
.ms-ticks {
  position: relative;
  display: inline-block;
  width: 16px;
  height: 12px;
  // Pop the bubble's status glyph when the ticks first appear.
  animation: ms-pop var(--motion-base, 240ms) var(--ease-out-back, ease-out);
}

.ms-svg {
  position: absolute;
  inset: 0;
  width: 16px;
  height: 12px;
  overflow: visible;
}

.ms-check {
  fill: none;
  stroke-width: 1.6;
  stroke-linecap: round;
  stroke-linejoin: round;
  // Draw each tick by sweeping its stroke in (pathLength normalised to 1).
  stroke-dasharray: 1;
  stroke-dashoffset: 1;
  animation: ms-draw var(--motion-base, 240ms) var(--ease-out-expo, ease-out)
    forwards;
}

.ms-svg--base .ms-check {
  stroke: var(--wa-check-delivered, #8696a0);
}

// Second tick (delivered/read) draws slightly after the first.
.ms-check--back {
  animation-delay: var(--motion-instant, 80ms);
}

// --- Read state: blue wipe over the grey ticks ------------------------------
.ms-svg--read .ms-check {
  stroke: var(--wa-check-read, #53bdeb);
  // Already drawn by the time we read — keep them solid under the wipe.
  stroke-dashoffset: 0;
  animation: none;
}
.ms-svg--read {
  animation: ms-wipe var(--motion-base, 240ms) var(--ease-in-out-quart, ease)
    forwards;
}

@keyframes ms-draw {
  to {
    stroke-dashoffset: 0;
  }
}

@keyframes ms-pop {
  0% {
    transform: scale(0.7);
  }
  60% {
    transform: scale(1.08);
  }
  100% {
    transform: scale(1);
  }
}

@keyframes ms-wipe {
  from {
    clip-path: inset(0 100% 0 0);
  }
  to {
    clip-path: inset(0 0 0 0);
  }
}

// Honour reduced motion: no pop/draw/wipe, just show the final ticks.
@media (prefers-reduced-motion: reduce) {
  .ms-ticks {
    animation: none;
  }
  .ms-check {
    stroke-dashoffset: 0;
    animation: none;
  }
  .ms-svg--read {
    animation: none;
    clip-path: none;
  }
}
</style>
