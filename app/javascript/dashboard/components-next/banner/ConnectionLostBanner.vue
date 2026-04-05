<script setup>
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  message: {
    type: String,
    default: 'Connection lost. Reconnecting...',
  },
});
</script>

<template>
  <div
    class="flex items-center gap-2 px-4 py-2 bg-n-ruby-3/30 dark:bg-n-ruby-5/20 border-b border-n-ruby-6/30"
  >
    <Icon icon="i-lucide-wifi-off" class="size-4 text-n-ruby-11 shrink-0" />
    <span class="text-sm text-n-ruby-11">
      {{ message }}
    </span>
  </div>
</template>
