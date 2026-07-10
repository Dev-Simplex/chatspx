<script setup>
import { ref, watch, computed, nextTick } from 'vue';
import { useKeyboardNavigableList } from 'dashboard/composables/useKeyboardNavigableList';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';

const props = defineProps({
  items: {
    type: Array,
    default: () => [],
  },
  type: {
    type: String,
    default: 'canned',
  },
});

const emit = defineEmits(['mentionSelect']);

const { getPlainText } = useMessageFormatter();

const mentionsListContainerRef = ref(null);
const selectedIndex = ref(0);
// True when the selection changed because of the mouse hovering an item. A hovered
// item is already under the cursor, so it must NOT be scrolled into view — doing so
// scrolls the ancestor containers and nudges this absolutely-positioned box, moving a
// different item under the cursor and re-firing hover (a jitter/"tremor" feedback loop).
const isPointerNavigation = ref(false);

const adjustScroll = () => {
  nextTick(() => {
    const container = mentionsListContainerRef.value;
    if (!container) return;
    const selectedElement = container.querySelector(
      `#mention-item-${selectedIndex.value}`
    );
    if (selectedElement) {
      selectedElement.scrollIntoView({ block: 'nearest', behavior: 'auto' });
    }
  });
};

const onSelect = () => {
  emit('mentionSelect', props.items[selectedIndex.value]);
};

useKeyboardNavigableList({
  items: computed(() => props.items),
  onSelect,
  adjustScroll,
  selectedIndex,
});

watch(
  () => props.items,
  newItems => {
    if (newItems.length < selectedIndex.value + 1) {
      selectedIndex.value = 0;
    }
  }
);

watch(selectedIndex, () => {
  // Skip the programmatic scroll for pointer-driven selection (see isPointerNavigation).
  if (isPointerNavigation.value) {
    isPointerNavigation.value = false;
    return;
  }
  adjustScroll();
});

const onHover = index => {
  if (index === selectedIndex.value) return;
  isPointerNavigation.value = true;
  selectedIndex.value = index;
};

const onListItemSelection = index => {
  selectedIndex.value = index;
  onSelect();
};

const variableKey = (item = {}) => {
  return props.type === 'variable' ? `{{${item.label}}}` : `/${item.label}`;
};
</script>

<template>
  <div
    ref="mentionsListContainerRef"
    class="bg-n-solid-1 p-1 rounded-xl overflow-auto absolute w-full z-20 shadow-dropdown left-0 bottom-full mb-1 max-h-60 border border-n-weak mention--box animate-dropdown-in"
  >
    <ul class="mb-0 vertical dropdown menu">
      <woot-dropdown-item
        v-for="(item, index) in items"
        :id="`mention-item-${index}`"
        :key="item.key"
        class="!mb-1"
        @mouseover="onHover(index)"
      >
        <button
          class="flex rounded-lg group flex-col gap-0.5 overflow-hidden cursor-pointer items-start px-3 py-2 justify-center w-full h-full text-left hover:bg-n-slate-3/50"
          :class="{
            'bg-n-brand/10': index === selectedIndex,
          }"
          @click="onListItemSelection(index)"
        >
          <slot :item="item" :index="index" :selected="index === selectedIndex">
            <p
              class="max-w-full min-w-0 mb-0 overflow-hidden text-sm font-medium text-n-slate-11 group-hover:text-n-slate-12 text-ellipsis whitespace-nowrap"
              :class="{
                'text-n-slate-12': index === selectedIndex,
              }"
            >
              {{ getPlainText(item.description) }}
            </p>
            <p
              class="max-w-full min-w-0 mb-0 overflow-hidden text-xs text-n-slate-11 group-hover:text-n-slate-12 text-ellipsis whitespace-nowrap"
              :class="{
                'text-n-slate-12': index === selectedIndex,
              }"
            >
              {{ variableKey(item) }}
            </p>
          </slot>
        </button>
      </woot-dropdown-item>
    </ul>
  </div>
</template>

<style scoped lang="scss">
.mention--box {
  .dropdown-menu__item:last-child > button {
    @apply border-0;
  }
}

.canned-item__button :deep(.button__content) {
  @apply overflow-hidden text-ellipsis whitespace-nowrap;
}
</style>
