<script setup>
import { computed, ref, watch } from 'vue';
import SidebarGroupLeaf from './SidebarGroupLeaf.vue';
import SidebarGroupSeparator from './SidebarGroupSeparator.vue';

import { useSidebarContext } from './provider';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useEventListener } from '@vueuse/core';

const props = defineProps({
  name: { type: String, required: true },
  parentName: { type: String, required: true },
  isExpanded: { type: Boolean, default: false },
  label: { type: String, required: true },
  icon: { type: [Object, String], required: true },
  children: { type: Array, default: undefined },
  activeChild: { type: Object, default: undefined },
  isCollapsed: { type: Boolean, default: false },
});

const { isAllowed } = useSidebarContext();
const { uiSettings, updateUISettings } = useUISettings();
const scrollableContainer = ref(null);

const accessibleItems = computed(() =>
  props.children.filter(child => {
    return child.to && isAllowed(child.to);
  })
);

const hasAccessibleItems = computed(() => {
  return accessibleItems.value.length > 0;
});

const isScrollable = computed(() => {
  return accessibleItems.value.length > 7;
});

const subgroupKey = computed(() => `${props.parentName}/${props.name}`);
const sidebarSubgroupState = computed(
  () => uiSettings.value?.sidebar_subgroup_state || {}
);
const storedExpandedState = computed(
  () => sidebarSubgroupState.value[subgroupKey.value]
);
const hasActiveChild = computed(() => {
  if (!props.activeChild?.name) return false;
  return props.children.some(child => child.name === props.activeChild.name);
});
const isSubgroupExpanded = computed(() => {
  if (hasActiveChild.value) return true;
  return storedExpandedState.value !== undefined
    ? storedExpandedState.value
    : true;
});

const setSubgroupExpanded = value => {
  updateUISettings({
    sidebar_subgroup_state: {
      ...sidebarSubgroupState.value,
      [subgroupKey.value]: value,
    },
  });
};

const toggleSubgroup = () => {
  setSubgroupExpanded(!isSubgroupExpanded.value);
};

const scrollEnd = ref(false);

// set scrollEnd to true when the scroll reaches the end
useEventListener(scrollableContainer, 'scroll', () => {
  const container = scrollableContainer.value;
  if (!container) return;
  const { scrollHeight, scrollTop, clientHeight } = container;
  scrollEnd.value = scrollHeight - scrollTop === clientHeight;
});

watch(
  hasActiveChild,
  value => {
    if (!value) return;
    if (storedExpandedState.value === false) {
      setSubgroupExpanded(true);
    }
  },
  { immediate: true }
);
</script>

<template>
  <SidebarGroupSeparator
    v-if="hasAccessibleItems"
    v-show="isExpanded"
    :label
    :icon
    collapsible
    :is-expanded="isSubgroupExpanded"
    @toggle="toggleSubgroup"
    class="my-1"
  />
  <ul v-if="children.length" class="m-0 list-none reset-base relative group">
    <!-- Each element has h-8, which is 32px, we will show 7 items with one hidden at the end,
    which is 14rem. Then we add 16px so that we have some text visible from the next item  -->
    <div
      ref="scrollableContainer"
      v-show="isSubgroupExpanded"
      :class="{
        'max-h-[calc(14rem+16px)] overflow-y-scroll no-scrollbar': isScrollable,
      }"
    >
      <SidebarGroupLeaf
        v-for="child in children"
        v-show="isExpanded || activeChild?.name === child.name"
        v-bind="child"
        :key="child.name"
        :active="activeChild?.name === child.name"
        :is-collapsed="isCollapsed"
      />
    </div>
    <div
      v-if="isScrollable && isExpanded && isSubgroupExpanded"
      v-show="!scrollEnd"
      class="absolute bg-gradient-to-t from-n-solid-2 w-full h-12 to-transparent -bottom-1 pointer-events-none flex items-end justify-end px-2 animate-fade-in-up"
    >
      <svg
        width="16"
        height="24"
        viewBox="0 0 16 24"
        fill="none"
        class="text-n-slate-9 opacity-50 group-hover:opacity-100"
        xmlns="http://www.w3.org/2000/svg"
      >
        <path
          d="M4 4L8 8L12 4"
          stroke="currentColor"
          opacity="0.5"
          stroke-width="1.33333"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
        <path
          d="M4 10L8 14L12 10"
          stroke="currentColor"
          opacity="0.75"
          stroke-width="1.33333"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
        <path
          d="M4 16L8 20L12 16"
          stroke="currentColor"
          stroke-width="1.33333"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
      </svg>
    </div>
  </ul>
</template>
