<script setup>
/**
 * Indeterminate "worm" loader — a comet-like stroke travels a looping squiggle
 * that runs off the track and back. Used as the big upload spinner on the
 * attachment preview modal's dark overlay.
 *
 * Animates only `stroke-dashoffset` (a single property) so it stays paint/GPU
 * cheap, and honours prefers-reduced-motion by slowing right down. The exact
 * % (when known) is rendered by the caller next to this icon — the worm itself
 * is purely indeterminate.
 */
defineProps({
  size: { type: Number, default: 96 },
});
</script>

<template>
  <svg
    class="worm-loader"
    :width="size"
    :height="size"
    viewBox="0 0 128 128"
    role="img"
    aria-hidden="true"
    xmlns="http://www.w3.org/2000/svg"
  >
    <defs>
      <linearGradient id="worm-loader-grad" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stop-color="hsl(193,90%,55%)" />
        <stop offset="100%" stop-color="hsl(223,90%,55%)" />
      </linearGradient>
    </defs>
    <circle
      class="worm-loader__ring"
      r="56"
      cx="64"
      cy="64"
      fill="none"
      stroke-width="16"
      stroke-linecap="round"
    />
    <path
      class="worm-loader__worm"
      d="M92,15.492S78.194,4.967,66.743,16.887c-17.231,17.938-28.26,96.974-28.26,96.974L119.85,59.892l-99-31.588,57.528,89.832L97.8,19.349,13.636,88.51l89.012,16.015S81.908,38.332,66.1,22.337C50.114,6.156,36,15.492,36,15.492a56,56,0,1,0,56,0Z"
      fill="none"
      stroke="url(#worm-loader-grad)"
      stroke-width="16"
      stroke-linecap="round"
      stroke-linejoin="round"
      stroke-dasharray="44 1111"
      stroke-dashoffset="10"
    />
  </svg>
</template>

<style scoped lang="scss">
.worm-loader {
  display: block;
}

.worm-loader__ring {
  // Faint track that still reads against the dark modal overlay.
  stroke: rgba(255, 255, 255, 0.16);
}

.worm-loader__worm {
  animation: worm-loader-travel 3s linear infinite;
  // Soft glow so the comet pops against the backdrop.
  filter: drop-shadow(0 0 3px hsla(203, 90%, 55%, 0.5));
}

// One full dash period (dash 44 + gap 1111 = 1155) shifts the comet exactly
// once around the squiggle → the loop is seamless.
@keyframes worm-loader-travel {
  from {
    stroke-dashoffset: 10;
  }
  to {
    stroke-dashoffset: -1145;
  }
}

@media (prefers-reduced-motion: reduce) {
  .worm-loader__worm {
    animation-duration: 7s;
  }
}
</style>
