<script setup>
import { computed, useAttrs } from 'vue';

defineOptions({
  inheritAttrs: false,
});

const props = defineProps({
  as: {
    type: String,
    default: 'div',
  },
  variant: {
    type: String,
    default: 'base',
  },
  padding: {
    type: String,
    default: 'md',
  },
});

const attrs = useAttrs();

const variantClasses = {
  base:
    'rounded-3xl border border-n-container/60 bg-n-solid-2/80 shadow-sm backdrop-blur',
  raised:
    'rounded-3xl border border-n-container/70 bg-n-solid-2/90 shadow-md backdrop-blur',
  soft: 'rounded-2xl border border-n-container/40 bg-n-background/70',
  inset: 'rounded-2xl border border-n-container/40 bg-n-alpha-2/50',
};

const paddingClasses = {
  none: 'p-0',
  sm: 'px-4 py-3',
  md: 'px-6 py-5',
  lg: 'px-8 py-6',
};

const classes = computed(() => {
  const variant = variantClasses[props.variant] || variantClasses.base;
  const padding = paddingClasses[props.padding] || paddingClasses.md;
  return ['relative overflow-hidden', variant, padding];
});
</script>

<template>
  <component :is="as" v-bind="attrs" :class="classes" data-surface="reports">
    <slot />
  </component>
</template>
