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
    class="wa-contact-panel-header flex items-center justify-between px-4 h-[60px] border-b border-n-weak"
  >
    <span class="text-[17px] font-semibold text-n-slate-12">{{ title }}</span>
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
        class="wa-contact-panel-close flex items-center justify-center size-8 rounded-lg"
        @click="$emit('close')"
      >
        <span class="i-lucide-x size-4" />
      </button>
    </div>
  </div>
</template>
