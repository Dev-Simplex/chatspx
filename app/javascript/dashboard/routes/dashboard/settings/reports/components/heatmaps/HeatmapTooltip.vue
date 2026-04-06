<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  visible: {
    type: Boolean,
    default: false,
  },
  x: {
    type: Number,
    default: 0,
  },
  y: {
    type: Number,
    default: 0,
  },
  value: {
    type: Number,
    default: null,
  },
});

const { t } = useI18n();

const tooltipText = computed(() => {
  if (!props.value) {
    return t('OVERVIEW_REPORTS.CONVERSATION_HEATMAP.NO_CONVERSATIONS');
  }

  if (props.value === 1) {
    return t('OVERVIEW_REPORTS.CONVERSATION_HEATMAP.CONVERSATION', {
      count: props.value,
    });
  }

  return t('OVERVIEW_REPORTS.CONVERSATION_HEATMAP.CONVERSATIONS', {
    count: props.value,
  });
});
</script>

<!-- eslint-disable vue/no-static-inline-styles -->
<template>
  <div
    class="fixed z-50 px-3 py-2 text-sm font-medium bg-n-solid-2 dark:bg-n-solid-3 text-n-slate-12 rounded-lg shadow-dropdown pointer-events-none transition-[opacity,transform] duration-75"
    :class="{ 'opacity-100': visible, 'opacity-0': !visible }"
    :style="{
      left: `${x}px`,
      top: `${y - 15}px`,
      transform: 'translateX(-50%) translateZ(0)',
      willChange: 'transform, opacity',
    }"
  >
    {{ tooltipText }}
  </div>
</template>
