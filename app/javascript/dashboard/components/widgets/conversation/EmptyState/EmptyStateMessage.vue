<script setup>
import Icon from 'dashboard/components-next/icon/Icon.vue';
import FeaturePlaceholder from './FeaturePlaceholder.vue';

defineProps({
  message: {
    type: String,
    required: true,
  },
  icon: {
    type: String,
    default: 'i-lucide-message-square',
  },
  description: {
    type: String,
    default: '',
  },
});
</script>

<template>
  <div
    class="flex flex-col items-center justify-center h-full py-16 px-8 text-center"
  >
    <Icon :icon="icon" class="size-16 text-n-slate-5 mb-4" />
    <h3 class="text-lg font-semibold text-n-slate-12 mb-2">
      {{ message }}
    </h3>
    <p v-if="description" class="text-sm text-n-slate-10 max-w-sm mb-6">
      {{ description }}
    </p>
    <FeaturePlaceholder />
  </div>
</template>
