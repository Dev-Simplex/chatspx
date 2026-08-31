<script setup>
defineProps({
  state: {
    type: String,
    default: 'idle',
    validator: v => ['idle', 'thinking', 'responding'].includes(v),
  },
  size: {
    type: String,
    default: 'md',
    validator: v => ['sm', 'md', 'lg', 'xl'].includes(v),
  },
});

const SIZE_MAP = { sm: 24, md: 32, lg: 48, xl: 64 };
</script>

<template>
  <div
    class="relative inline-flex items-center justify-center flex-shrink-0 rounded-full bg-gradient-to-br from-n-teal-9 to-n-blue-9"
    :class="{
      'animate-pulse': state === 'idle',
      'animate-bounce': state === 'responding',
    }"
    :style="{
      width: SIZE_MAP[size] + 'px',
      height: SIZE_MAP[size] + 'px',
    }"
  >
    <!-- Outer ring (spins when thinking) -->
    <svg
      class="absolute inset-0 w-full h-full"
      :class="{ 'animate-spin': state === 'thinking' }"
      viewBox="0 0 100 100"
    >
      <circle
        cx="50"
        cy="50"
        r="47"
        fill="none"
        stroke="white"
        stroke-opacity="0.3"
        stroke-width="2"
        stroke-dasharray="8 6"
      />
    </svg>

    <!-- Face -->
    <svg
      class="relative"
      viewBox="0 0 100 100"
      :width="SIZE_MAP[size] * 0.6"
      :height="SIZE_MAP[size] * 0.6"
    >
      <!-- Left eye -->
      <circle cx="35" cy="40" r="6" fill="white">
        <animate
          v-if="state === 'thinking'"
          attributeName="ry"
          values="6;1;6"
          dur="1.2s"
          repeatCount="indefinite"
        />
      </circle>
      <!-- Right eye -->
      <circle cx="65" cy="40" r="6" fill="white">
        <animate
          v-if="state === 'thinking'"
          attributeName="ry"
          values="6;1;6"
          dur="1.2s"
          repeatCount="indefinite"
        />
      </circle>
      <!-- Mouth -->
      <path
        d="M 32 62 Q 50 76 68 62"
        fill="none"
        stroke="white"
        stroke-width="4"
        stroke-linecap="round"
      />
    </svg>
  </div>
</template>
