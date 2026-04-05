<script setup>
import Button from './button/Button.vue';
defineProps({
  title: {
    type: String,
    required: true,
  },
  buttons: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['click', 'close']);

const handleButtonClick = button => {
  emit('click', button.key);
};
</script>

<template>
  <div
    class="flex items-center justify-between px-4 h-14 border-b border-n-weak"
  >
    <span class="text-base font-semibold text-n-slate-12">{{ title }}</span>
    <div class="flex items-center gap-1">
      <Button
        v-for="button in buttons"
        :key="button.key"
        v-tooltip="button.tooltip"
        :icon="button.icon"
        ghost
        sm
        @click="handleButtonClick(button)"
      />
      <button
        v-tooltip="$t('GENERAL.CLOSE')"
        class="flex items-center justify-center size-8 rounded-lg hover:bg-n-slate-3/50 text-n-slate-10"
        @click="$emit('close')"
      >
        <span class="i-lucide-x size-4" />
      </button>
    </div>
  </div>
</template>
