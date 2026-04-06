<script setup>
defineProps({
  title: {
    type: String,
    default: '',
  },
  height: {
    type: String,
    default: 'max-h-96',
  },
});
</script>

<template>
  <div class="-mx-2 n-dropdown-section">
    <div
      v-if="title"
      class="px-3 py-1 leading-4 font-medium text-n-slate-10 text-xs"
    >
      {{ title }}
    </div>
    <ul
      class="gap-2 grid reset-base list-none px-2 overflow-y-auto"
      :class="height"
    >
      <slot />
    </ul>
  </div>
</template>
