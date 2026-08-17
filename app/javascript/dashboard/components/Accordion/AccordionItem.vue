<script setup>
import EmojiOrIcon from 'shared/components/EmojiOrIcon.vue';

defineProps({
  title: {
    type: String,
    required: true,
  },
  compact: {
    type: Boolean,
    default: false,
  },
  icon: {
    type: String,
    default: '',
  },
  emoji: {
    type: String,
    default: '',
  },
  isOpen: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits(['toggle']);

const onToggle = () => {
  emit('toggle');
};
</script>

<template>
  <div class="text-sm border-t border-n-weak/50">
    <button
      class="flex items-center select-none w-full m-0 cursor-pointer justify-between px-4 py-3 hover:bg-n-slate-3/30 drag-handle"
      @click.stop="onToggle"
    >
      <div class="flex items-center gap-2">
        <EmojiOrIcon
          v-if="icon || emoji"
          class="inline-block w-5"
          :icon="icon"
          :emoji="emoji"
        />
        <span class="text-sm font-medium text-n-slate-12">
          {{ title }}
        </span>
      </div>
      <div class="flex flex-row items-center gap-1">
        <slot name="button" />
        <span
          class="i-lucide-chevron-down size-4 text-n-slate-10 transition-transform duration-200"
          :class="{ 'rotate-180': isOpen }"
        />
      </div>
    </button>
    <div v-if="isOpen" :class="compact ? 'p-0' : 'px-4 pb-3'">
      <slot />
    </div>
  </div>
</template>
