<script setup>
defineProps({
  variant: { type: String, default: 'off' }, // on | off | warn | err
  label: { type: String, default: '' },
});
// Chip de estado — sempre cor + label (+ aria), com stroke pra legibilidade dark.
defineOptions({ name: 'AiBadge' });
const MAP = {
  on: 'text-n-teal-12 bg-n-teal-3 border-n-teal-6',
  off: 'text-n-slate-11 bg-n-alpha-1 border-n-weak',
  warn: 'text-n-amber-12 bg-n-amber-3 border-n-amber-6',
  err: 'text-n-ruby-12 bg-n-ruby-3 border-n-ruby-6',
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
