<script setup>
import { computed } from 'vue';

/**
 * Circular upload-progress ring.
 * - Determinate: pass `value` (0-100) → the stroke sweeps to that fraction.
 * - Indeterminate: pass `value = null` → a comet tail spins (length unknown).
 *
 * Transform/opacity + stroke-dashoffset only, so it stays GPU-friendly. The
 * spin duration reads --motion-* so prefers-reduced-motion slows/settles it.
 */
const props = defineProps({
  // 0..100, or null/undefined for an indeterminate (spinning) ring.
  value: { type: Number, default: null },
  size: { type: Number, default: 40 },
  stroke: { type: Number, default: 3 },
});

const radius = computed(() => (props.size - props.stroke) / 2);
const circumference = computed(() => 2 * Math.PI * radius.value);
const center = computed(() => props.size / 2);

const isIndeterminate = computed(
  () => props.value === null || props.value === undefined
);

const clampedValue = computed(() =>
  Math.max(0, Math.min(100, props.value ?? 0))
);

// Determinate: leave a gap proportional to the remaining fraction.
const dashOffset = computed(
  () => circumference.value * (1 - clampedValue.value / 100)
);

// Indeterminate: a fixed-length comet (~25% of the circle) that spins.
const indeterminateDash = computed(
  () => `${circumference.value * 0.25} ${circumference.value * 0.75}`
);
</script>

<template>
  <span
    class="progress-ring"
    role="progressbar"
    :aria-valuenow="isIndeterminate ? undefined : clampedValue"
    aria-valuemin="0"
    aria-valuemax="100"
  >
    <svg
      :width="size"
      :height="size"
      :viewBox="`0 0 ${size} ${size}`"
      class="progress-ring__svg"
      :class="{ 'progress-ring__svg--spin': isIndeterminate }"
    >
      <circle
        class="progress-ring__track"
        :cx="center"
        :cy="center"
        :r="radius"
        :stroke-width="stroke"
        fill="none"
      />
      <circle
        class="progress-ring__bar"
        :cx="center"
        :cy="center"
        :r="radius"
        :stroke-width="stroke"
        fill="none"
        stroke-linecap="round"
        :stroke-dasharray="isIndeterminate ? indeterminateDash : circumference"
        :stroke-dashoffset="isIndeterminate ? 0 : dashOffset"
        :transform="`rotate(-90 ${center} ${center})`"
      />
    </svg>
    <span
      v-if="!isIndeterminate"
      class="progress-ring__label"
      :style="{ fontSize: `${Math.round(size * 0.26)}px` }"
    >
      {{ clampedValue }}
    </span>
  </span>
</template>

<style scoped lang="scss">
.progress-ring {
  position: relative;
  display: inline-grid;
  place-items: center;
  line-height: 0;
}

.progress-ring__svg {
  display: block;
}

.progress-ring__svg--spin {
  animation: progress-ring-spin var(--motion-drama, 520ms) linear infinite;
}

.progress-ring__track {
  stroke: rgba(255, 255, 255, 0.28);
}

.progress-ring__bar {
  stroke: #ffffff;
  transition: stroke-dashoffset var(--motion-fast, 160ms)
    var(--ease-out-expo, ease-out);
  // Subtle shimmer on the moving stroke.
  filter: drop-shadow(0 0 2px rgba(255, 255, 255, 0.55));
}

.progress-ring__label {
  position: absolute;
  inset: 0;
  display: grid;
  place-items: center;
  color: #ffffff;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
}

@keyframes progress-ring-spin {
  to {
    transform: rotate(360deg);
  }
}

@media (prefers-reduced-motion: reduce) {
  .progress-ring__svg--spin {
    animation-duration: 1.4s;
  }
}
</style>
