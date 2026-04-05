<script setup>
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';

defineProps({
  header: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    default: '',
  },
  compact: {
    type: Boolean,
    default: false,
  },
  hideToggle: {
    type: Boolean,
    default: false,
  },
});

const modelValue = defineModel({ type: Boolean, default: false });
</script>

<template>
  <div
    class="flex flex-col items-start bg-white dark:bg-n-solid-2 border border-n-weak rounded-xl [interpolate-size:allow-keywords]"
  >
    <div class="flex flex-col gap-1 items-start w-full p-6">
      <div class="flex items-center gap-3 w-full justify-between">
        <span class="text-heading-3 text-n-slate-12">
          {{ header }}
        </span>
        <div v-if="hideToggle" class="size-2" />
        <ToggleSwitch v-else v-model="modelValue" />
      </div>
      <span v-if="description" class="text-sm text-n-slate-10 mt-1">
        {{ description }}
      </span>
    </div>
    <div
      v-if="$slots.editor"
      class="w-full border-t border-n-weak/50"
      :class="{ 'p-0': compact, 'px-6 pb-6 pt-3': !compact }"
    >
      <slot name="editor" />
    </div>
  </div>
</template>
