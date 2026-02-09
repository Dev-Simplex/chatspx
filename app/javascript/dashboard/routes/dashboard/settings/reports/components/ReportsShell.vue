<script setup>
import { computed, useSlots } from 'vue';

const props = defineProps({
  stickyFilters: {
    type: Boolean,
    default: true,
  },
});

const slots = useSlots();
const hasFilters = computed(() => Boolean(slots.filters));
</script>

<template>
  <div
    class="grid gap-6"
    :class="hasFilters ? 'grid-cols-1 lg:grid-cols-[280px,1fr]' : 'grid-cols-1'"
  >
    <aside
      v-if="hasFilters"
      class="order-first lg:order-none"
      :class="stickyFilters ? 'lg:sticky lg:top-6 self-start' : ''"
    >
      <slot name="filters" />
    </aside>
    <main class="min-w-0">
      <slot name="content" />
    </main>
  </div>
</template>
