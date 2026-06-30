<script setup>
import { computed } from 'vue';
// Avatar iOS: inicial do nome sobre gradiente determinístico (hash do nome).
const props = defineProps({
  name: { type: String, default: '' },
  size: { type: Number, default: 36 },
});
defineOptions({ name: 'AiAvatar' });
const GRAD = [
  'from-[#0a84ff] to-[#5e5ce6]',
  'from-[#1faa59] to-[#30b0c7]',
  'from-[#ff9500] to-[#ff2d55]',
  'from-[#af52de] to-[#5e5ce6]',
  'from-[#34c759] to-[#0a84ff]',
  'from-[#ff3b30] to-[#ff9500]',
];
const initial = computed(() =>
  (props.name || '?').trim().charAt(0).toUpperCase()
);
const grad = computed(() => {
  const s = (props.name || '')
    .split('')
    .reduce((a, c) => a + c.charCodeAt(0), 0);
  return GRAD[s % GRAD.length];
});
</script>

<template>
  <span
    class="grid flex-none font-bold tracking-tight text-white bg-gradient-to-br rounded-full place-items-center"
    :class="grad"
    :style="{
      width: `${size}px`,
      height: `${size}px`,
      fontSize: `${Math.round(size * 0.42)}px`,
    }"
  >
    {{ initial }}
  </span>
</template>
