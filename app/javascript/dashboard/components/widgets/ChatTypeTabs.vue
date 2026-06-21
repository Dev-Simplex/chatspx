<script setup>
import { computed } from 'vue';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import wootConstants from 'dashboard/constants/globals';

const props = defineProps({
  items: {
    type: Array,
    default: () => [],
  },
  activeTab: {
    type: String,
    default: wootConstants.ASSIGNEE_TYPE.ME,
  },
});

const emit = defineEmits(['chatTabChange']);

const activeTabIndex = computed(() => {
  return props.items.findIndex(item => item.key === props.activeTab);
});

const onTabChange = selectedTabIndex => {
  if (selectedTabIndex >= 0 && selectedTabIndex < props.items.length) {
    const selectedItem = props.items[selectedTabIndex];
    if (selectedItem.key !== props.activeTab) {
      emit('chatTabChange', selectedItem.key);
    }
  }
};

const keyboardEvents = {
  'Alt+KeyN': {
    action: () => {
      if (props.activeTab === wootConstants.ASSIGNEE_TYPE.ALL) {
        onTabChange(0);
      } else {
        const nextIndex = (activeTabIndex.value + 1) % props.items.length;
        onTabChange(nextIndex);
      }
    },
  },
};

useKeyboardEvents(keyboardEvents);
</script>

<template>
  <woot-tabs
    :index="activeTabIndex"
    class="w-full py-0 conversation-list-tabs chat-list-tabs [&_ul]:px-3 [&_ul]:py-1"
    @change="onTabChange"
  >
    <woot-tabs-item
      v-for="(item, index) in items"
      :key="item.key"
      class="text-sm [&_a]:font-medium"
      :class="{ 'tab-alert animate-jump-in': item.variant === 'alert' }"
      :index="index"
      :name="item.name"
      :count="item.count"
      :icon="item.icon"
      animated-count
      is-compact
    />
  </woot-tabs>
</template>

<style lang="scss" scoped>
// Alert variant (conditional "Unassigned" tab — DC-6). Tokens only, so dark
// mode comes for free. `!important` is required to win over the global
// `.wa-tab-item` skin rules (_wa-skin.scss). Written as plain declarations
// (not `@apply !...`) because the `!` prefix is parsed as a Sass flag inside
// a scss block and breaks the build.
.tab-alert :deep(.wa-tab-item) {
  color: rgb(var(--ruby-11)) !important;
}

.tab-alert :deep(.wa-tab-item:hover) {
  color: rgb(var(--ruby-12)) !important;
}

.tab-alert :deep(.wa-tab-item__badge) {
  background-color: rgb(var(--ruby-9) / 0.2) !important;
  color: rgb(var(--ruby-11)) !important;
}
</style>
