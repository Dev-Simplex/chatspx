<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { formatNumber } from '@chatwoot/utils';
import wootConstants from 'dashboard/constants/globals';

import ConversationBasicFilter from './widgets/conversation/ConversationBasicFilter.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ConversationSearchBar from './widgets/conversation/ConversationSearchBar.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';

const { t } = useI18n();

const props = defineProps({
  pageTitle: { type: String, required: true },
  hasAppliedFilters: { type: Boolean, required: true },
  hasActiveFolders: { type: Boolean, required: true },
  activeStatus: { type: String, required: true },
  isOnExpandedLayout: { type: Boolean, required: true },
  conversationStats: { type: Object, required: true },
  isListLoading: { type: Boolean, required: true },
  searchContext: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits([
  'addFolders',
  'deleteFolders',
  'resetFilters',
  'basicFilterChange',
  'filtersModal',
  'openSearch',
]);

const { uiSettings, updateUISettings } = useUISettings();

const onBasicFilterChange = (value, type) => {
  emit('basicFilterChange', value, type);
};

const hasAppliedFiltersOrActiveFolders = computed(() => {
  return props.hasAppliedFilters || props.hasActiveFolders;
});

const allCount = computed(() => props.conversationStats?.allCount || 0);
const formattedAllCount = computed(() => formatNumber(allCount.value));

const toggleConversationLayout = () => {
  const { LAYOUT_TYPES } = wootConstants;
  const {
    conversation_display_type: conversationDisplayType = LAYOUT_TYPES.CONDENSED,
  } = uiSettings.value;
  const newViewType =
    conversationDisplayType === LAYOUT_TYPES.CONDENSED
      ? LAYOUT_TYPES.EXPANDED
      : LAYOUT_TYPES.CONDENSED;
  updateUISettings({
    conversation_display_type: newViewType,
    previously_used_conversation_display_type: newViewType,
  });
};

const layoutIcon = computed(() =>
  props.isOnExpandedLayout
    ? 'i-lucide-arrow-left-to-line'
    : 'i-lucide-arrow-right-to-line'
);

const showHeaderActionsDropdown = ref(false);

const toggleHeaderActionsDropdown = () => {
  showHeaderActionsDropdown.value = !showHeaderActionsDropdown.value;
};

const closeHeaderActionsDropdown = () => {
  showHeaderActionsDropdown.value = false;
};

const openFiltersModal = () => {
  emit('filtersModal');
  closeHeaderActionsDropdown();
};

const handleSwitchLayoutToggle = () => {
  toggleConversationLayout();
  closeHeaderActionsDropdown();
};

</script>

<template>
  <div class="flex flex-col">
    <div
      class="flex items-center justify-between gap-2 px-3 h-12"
      :class="{
        'border-b border-n-strong': hasAppliedFiltersOrActiveFolders,
      }"
    >
    <div class="flex items-center justify-center min-w-0">
      <h1
        class="text-base font-medium truncate text-n-slate-12"
        :title="pageTitle"
      >
        {{ pageTitle }}
      </h1>
      <span
        v-if="
          allCount > 0 && hasAppliedFiltersOrActiveFolders && !isListLoading
        "
        class="px-2 py-1 my-0.5 mx-1 rounded-md capitalize bg-n-slate-3 text-xxs text-n-slate-12 shrink-0"
        :title="allCount"
      >
        {{ formattedAllCount }}
      </span>
      <span
        v-if="!hasAppliedFiltersOrActiveFolders"
        class="px-2 py-1 my-0.5 mx-1 rounded-md capitalize bg-n-slate-3 text-xxs text-n-slate-12 shrink-0"
      >
        {{ $t(`CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.${activeStatus}.TEXT`) }}
      </span>
    </div>
    <div class="flex items-center gap-1">
      <template v-if="hasAppliedFilters && !hasActiveFolders">
        <div class="relative">
          <NextButton
            v-tooltip.top-end="$t('FILTER.CUSTOM_VIEWS.ADD.SAVE_BUTTON')"
            icon="i-lucide-save"
            slate
            xs
            faded
            @click="emit('addFolders')"
          />
          <div
            id="saveFilterTeleportTarget"
            class="absolute z-40 mt-2"
            :class="{ 'ltr:right-0 rtl:left-0': isOnExpandedLayout }"
          />
        </div>
        <NextButton
          v-tooltip.top-end="$t('FILTER.CLEAR_BUTTON_LABEL')"
          icon="i-lucide-circle-x"
          ruby
          faded
          xs
          @click="emit('resetFilters')"
        />
      </template>
      <template v-if="hasActiveFolders">
        <NextButton
          id="toggleConversationFilterButton"
          v-tooltip.top-end="$t('FILTER.CUSTOM_VIEWS.DELETE.DELETE_BUTTON')"
          icon="i-lucide-trash-2"
          ruby
          xs
          faded
          @click="emit('deleteFolders')"
        />
        <div class="relative">
          <NextButton
            id="toggleConversationFilterButton"
            v-tooltip.top-end="$t('FILTER.CUSTOM_VIEWS.EDIT.EDIT_BUTTON')"
            icon="i-lucide-message-square-plus"
            slate
            xs
            faded
            @click="emit('filtersModal')"
          />
          <div
            id="conversationFilterTeleportTarget"
            class="absolute z-40 mt-2"
            :class="{ 'ltr:right-0 rtl:left-0': isOnExpandedLayout }"
          />
        </div>
      </template>
      <ComposeConversation align-position="right">
        <template #trigger="{ toggle }">
          <NextButton
            icon="i-lucide-message-square-plus"
            slate
            sm
            faded
            class="!h-8 !w-8"
            @click="toggle"
          />
        </template>
      </ComposeConversation>
      <div
        v-on-click-outside="closeHeaderActionsDropdown"
        class="relative"
      >
        <NextButton
          icon="i-lucide-ellipsis-vertical"
          slate
          sm
          faded
          class="!h-8 !w-8"
          @click="toggleHeaderActionsDropdown"
        />
        <div
          id="conversationFilterTeleportTarget"
          class="absolute z-40 mt-2"
          :class="{ 'ltr:right-0 rtl:left-0': isOnExpandedLayout }"
        />
        <div
          v-if="showHeaderActionsDropdown"
          class="absolute z-40 mt-2 top-full p-1 rounded-xl border border-n-weak bg-n-alpha-3 backdrop-blur-[100px]"
          :class="{ 'ltr:right-0 rtl:left-0': isOnExpandedLayout }"
        >
          <div class="flex flex-col gap-1 min-w-[12rem]">
            <NextButton
              id="toggleConversationFilterButton"
              icon="i-lucide-list-filter"
              :label="t('FILTER.TOOLTIP_LABEL')"
              justify="start"
              slate
              xs
              faded
              class="w-full"
              @click="openFiltersModal"
            />
            <ConversationBasicFilter
              :is-on-expanded-layout="isOnExpandedLayout"
              :button-label="t('CHAT_LIST.SORT_TOOLTIP_LABEL')"
              button-justify="start"
              button-class="w-full"
              :show-tooltip="false"
              @change-filter="onBasicFilterChange"
            />
            <NextButton
              :icon="layoutIcon"
              :label="t('CONVERSATION.SWITCH_VIEW_LAYOUT')"
              justify="start"
              slate
              xs
              faded
              class="w-full"
              @click="handleSwitchLayoutToggle"
            />
          </div>
        </div>
      </div>
    </div>
    </div>
    <ConversationSearchBar
      :context="searchContext"
      @search="emit('search', $event)"
      @clear="emit('clearSearch')"
    />
  </div>
</template>

