<script setup>
// Grouped inset list (iOS). Filhos diretos são AiListRow.
defineOptions({ name: 'AiListGroup' });
</script>

<template>
  <div
    class="overflow-hidden rounded-2xl border shadow-sm border-n-weak bg-n-solid-1"
  >
    <slot />
  </div>
</template>
