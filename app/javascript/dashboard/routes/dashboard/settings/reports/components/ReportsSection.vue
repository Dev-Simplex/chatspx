<script setup>
import { computed } from 'vue';

const props = defineProps({
  title: {
    type: String,
    default: '',
  },
  description: {
    type: String,
    default: '',
  },
  eyebrow: {
    type: String,
    default: '',
  },
  compact: {
    type: Boolean,
    default: false,
  },
});

const hasHeader = computed(
  () => props.title || props.description || props.eyebrow
);
</script>

<template>
  <section class="flex flex-col" :class="compact ? 'gap-3' : 'gap-4'">
    <div
      v-if="hasHeader || $slots.actions || $slots.meta"
      class="flex flex-col gap-3 md:flex-row md:items-end md:justify-between"
    >
      <div class="flex flex-col gap-2 max-w-3xl">
        <span
          v-if="eyebrow"
          class="text-[11px] uppercase tracking-[0.32em] text-n-slate-10"
        >
          {{ eyebrow }}
        </span>
        <h2
          v-if="title"
          class="text-xl md:text-2xl font-semibold tracking-tight text-n-slate-12"
        >
          {{ title }}
        </h2>
        <p v-if="description" class="text-sm text-n-slate-11">
          {{ description }}
        </p>
        <div v-if="$slots.meta" class="flex items-center gap-2">
          <slot name="meta" />
        </div>
      </div>
      <div class="flex items-center gap-2 flex-shrink-0">
        <slot name="actions" />
      </div>
    </div>
    <slot />
  </section>
</template>
