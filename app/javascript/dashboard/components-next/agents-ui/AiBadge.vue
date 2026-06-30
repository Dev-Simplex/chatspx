<script setup>
defineProps({
  variant: { type: String, default: 'off' }, // on | off | warn | err
  label: { type: String, default: '' },
});
// Chip de estado — sempre cor + label (+ aria), com stroke pra legibilidade dark.
defineOptions({ name: 'AiBadge' });
const MAP = {
  on: 'text-g-800 bg-g-100 border-g-300 dark:text-g-200 dark:bg-g-900/40 dark:border-g-800',
  off: 'text-n-slate-11 bg-n-alpha-1 border-n-weak',
  warn: 'text-y-800 bg-y-100 border-y-300 dark:text-y-200 dark:bg-y-900/40 dark:border-y-800',
  err: 'text-r-800 bg-r-100 border-r-300 dark:text-r-200 dark:bg-r-900/40 dark:border-r-800',
};
</script>

<template>
  <span
    class="inline-flex gap-1 items-center px-2 py-0.5 text-[11px] font-bold rounded-md border"
    :class="MAP[variant] || MAP.off"
    :aria-label="label"
  >
    <slot />{{ label }}
  </span>
</template>
