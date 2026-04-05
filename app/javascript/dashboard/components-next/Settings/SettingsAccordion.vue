<script setup>
import { useToggle } from '@vueuse/core';

const props = defineProps({
  title: {
    type: String,
    required: true,
  },
  defaultOpen: {
    type: Boolean,
    default: true,
  },
});

const [isOpen, toggle] = useToggle(props.defaultOpen);
</script>

<template>
  <div
    v-bind="$attrs"
    class="flex items-center justify-between w-full cursor-pointer py-3 border-t border-n-weak"
    @click="toggle()"
  >
    <span class="text-heading-2 text-n-slate-12 w-full">
      {{ title }}
    </span>
    <span
      class="i-lucide-chevron-down size-5 text-n-slate-10 flex-shrink-0 transition-transform duration-200"
      :class="{ 'rotate-180': isOpen }"
    />
  </div>
  <div v-if="isOpen" class="w-full space-y-4 pt-4 mb-4">
    <slot />
  </div>
</template>
