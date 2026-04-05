<script setup>
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  message: {
    type: String,
    required: true,
  },
  actionLabel: {
    type: String,
    default: null,
  },
});

const emit = defineEmits(['action']);
</script>

<template>
  <div
    class="flex items-center justify-between gap-2 px-4 py-2 bg-n-amber-3/50 border-b border-n-amber-6/30"
  >
    <div class="flex items-center gap-2">
      <Icon
        icon="i-lucide-alert-triangle"
        class="size-4 text-n-amber-11 shrink-0"
      />
      <span class="text-sm text-n-amber-11">
        {{ message }}
      </span>
    </div>
    <button
      v-if="actionLabel"
      class="px-3 py-1 text-sm font-medium rounded-lg bg-n-amber-4 hover:bg-n-amber-5 text-n-amber-11 shrink-0"
      @click="emit('action')"
    >
      {{ actionLabel }}
    </button>
  </div>
</template>
