<script setup>
import { ref, useTemplateRef, provide, computed, watch } from 'vue';
import { useElementSize } from '@vueuse/core';

const props = defineProps({
  index: {
    type: Number,
    default: 0,
  },
  border: {
    type: Boolean,
    default: true,
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
    hasScroll.value = tabsList.value.scrollWidth > tabsList.value.clientWidth;
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
  <div
    ref="tabsContainer"
    class="flex items-center"
  >
    <button
      v-if="hasScroll"
      class="items-center rounded-none cursor-pointer flex h-auto justify-center min-w-8"
      @click="onScrollClick('left')"
    >
      <fluent-icon icon="chevron-left" :size="16" />
    </button>
    <ul
      ref="tabsList"
      class="flex items-center gap-2 px-3 py-2 list-none mb-0 overflow-x-auto no-scrollbar"
      :class="
        hasScroll ? 'max-w-[calc(100%-64px)]' : ''
      "
    >
      <slot />
    </ul>
    <button
      v-if="hasScroll"
      class="items-center rounded-none cursor-pointer flex h-auto justify-center min-w-8"
      @click="onScrollClick('right')"
    >
      <fluent-icon icon="chevron-right" :size="16" />
    </button>
  </div>
</template>
