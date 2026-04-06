<script setup>
defineProps({
  align: {
    type: String,
    default: 'start',
    validator: value => ['start', 'center', 'end'].includes(value),
  },
});
</script>

<template>
  <td
    class="px-4 py-3 text-sm text-n-slate-12"
    :class="{
      'text-start': align === 'start',
      'text-center': align === 'center',
      'text-end': align === 'end',
    }"
  >
    <slot />
  </td>
</template>
