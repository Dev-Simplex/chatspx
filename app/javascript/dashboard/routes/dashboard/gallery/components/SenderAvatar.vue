<script setup>
import { computed } from 'vue';

const props = defineProps({
  sender: { type: Object, default: null },
  size: { type: Number, default: 24 },
});

const initials = computed(() => {
  const name = props.sender?.name || '?';
  return name
    .split(/\s+/)
    .map(w => w[0])
    .filter(Boolean)
    .slice(0, 2)
    .join('')
    .toUpperCase();
});

const bgColor = computed(() => {
  const name = props.sender?.name || '';
  let hash = 0;
  for (let i = 0; i < name.length; i += 1) {
    hash = (hash * 31 + name.charCodeAt(i)) % 360000;
  }
  const hue = Math.abs(hash) % 360;
  return `hsl(${hue}, 55%, 45%)`;
});

const thumbnail = computed(
  () => props.sender?.thumbnail || props.sender?.avatar_url
);
</script>

<template>
  <div
    class="rounded-full flex items-center justify-center flex-shrink-0 text-white font-semibold overflow-hidden ring-2 ring-white/90 dark:ring-n-solid-1"
    :style="{
      width: `${size}px`,
      height: `${size}px`,
      backgroundColor: thumbnail ? 'transparent' : bgColor,
      fontSize: `${Math.max(10, size * 0.4)}px`,
    }"
  >
    <img
      v-if="thumbnail"
      :src="thumbnail"
      :alt="sender?.name || ''"
      class="w-full h-full object-cover"
      loading="lazy"
      decoding="async"
    />
    <span v-else>{{ initials }}</span>
  </div>
</template>
