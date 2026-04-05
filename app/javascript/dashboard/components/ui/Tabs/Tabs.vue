<script setup>
import { ref, useTemplateRef, provide, computed, watch } from 'vue';
import { useElementSize } from '@vueuse/core';

const props = defineProps({
  index: {
    type: Number,
    default: 0,
  },
});

const emit = defineEmits(['change']);

const tabsContainer = useTemplateRef('tabsContainer');
const tabsList = useTemplateRef('tabsList');

const { width: containerWidth } = useElementSize(tabsContainer);
const { width: listWidth } = useElementSize(tabsList);

const hasScroll = ref(false);

const activeIndex = computed({
  get: () => props.index,
  set: newValue => {
    emit('change', newValue);
  },
});

provide('activeIndex', activeIndex);
provide('updateActiveIndex', index => {
  activeIndex.value = index;
});

const computeScrollWidth = () => {
  if (tabsContainer.value && tabsList.value) {
    // Only show scroll buttons when content overflows by more than 20px
    // This prevents chevrons from appearing when tabs barely overflow
    hasScroll.value = tabsList.value.scrollWidth > tabsList.value.clientWidth + 20;
  }
};

const onScrollClick = direction => {
  if (tabsContainer.value && tabsList.value) {
    let scrollPosition = tabsList.value.scrollLeft;
    scrollPosition += direction === 'left' ? -100 : 100;
    tabsList.value.scrollTo({
      top: 0,
      left: scrollPosition,
      behavior: 'smooth',
    });
  }
};

// Watch for changes in element sizes with immediate execution
watch(
  [containerWidth, listWidth],
  () => {
    computeScrollWidth();
  },
  { immediate: true }
);
</script>

<template>
  <div ref="tabsContainer" class="flex items-center w-full">
    <button
      v-if="hasScroll"
      class="items-center rounded-none cursor-pointer flex h-auto justify-center min-w-6 opacity-60 hover:opacity-100 transition-opacity"
      @click="onScrollClick('left')"
    >
      <span class="i-lucide-chevron-left size-3.5" />
    </button>
    <ul
      ref="tabsList"
      class="flex items-center gap-1.5 px-3 py-1.5 list-none mb-0 overflow-x-auto no-scrollbar flex-1 min-w-0"
    >
      <slot />
    </ul>
    <button
      v-if="hasScroll"
      class="items-center rounded-none cursor-pointer flex h-auto justify-center min-w-6 opacity-60 hover:opacity-100 transition-opacity"
      @click="onScrollClick('right')"
    >
      <span class="i-lucide-chevron-right size-3.5" />
    </button>
  </div>
</template>
