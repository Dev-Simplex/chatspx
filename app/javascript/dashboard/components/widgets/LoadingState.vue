<script setup>
import ConversationCardSkeleton from 'dashboard/components-next/skeleton/ConversationCardSkeleton.vue';

defineProps({
  message: { type: String, default: '' },
  skeletonCount: { type: Number, default: 6 },
});
</script>

<template>
  <div class="flex flex-col h-full">
    <div v-if="message" class="flex items-center justify-center px-4 py-2">
      <span class="text-sm text-n-slate-10">
        {{ message }}
      </span>
    </div>
    <ConversationCardSkeleton :count="skeletonCount" />
  </div>
</template>
