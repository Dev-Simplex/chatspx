<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { generateLabelForContactableInboxesList } from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper.js';

import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  targetInbox: {
    type: Object,
    default: null,
  },
  selectedContact: {
    type: Object,
    default: null,
  },
  showInboxesDropdown: {
    type: Boolean,
    required: true,
  },
  contactableInboxesList: {
    type: Array,
    default: () => [],
  },
  hasErrors: {
    type: Boolean,
    default: false,
  },
  isFetchingInboxes: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'updateInbox',
  'toggleDropdown',
  'handleInboxAction',
]);

const { t } = useI18n();

const targetInboxLabel = computed(() => {
  return generateLabelForContactableInboxesList(props.targetInbox);
});
</script>

<template>
  <div class="relative px-5 py-4 overflow-y-visible">
    <div
      v-if="targetInbox"
      class="inline-flex items-center gap-2 rounded-xl border border-n-weak/80 bg-n-alpha-3 shadow-sm px-3 py-2 min-h-10 min-w-0 max-w-full"
    >
      <span
        class="size-2 rounded-full bg-n-brand ring-2 ring-n-brand/20 flex-shrink-0"
        aria-hidden="true"
      />
      <span
        class="i-lucide-inbox size-4 text-n-slate-11 flex-shrink-0"
        aria-hidden="true"
      />
      <span class="text-sm font-medium truncate text-n-slate-12">
        {{ targetInboxLabel }}
      </span>
      <Button
        variant="ghost"
        icon="i-lucide-x"
        color="slate"
        size="xs"
        class="flex-shrink-0 ltr:ml-1 rtl:mr-1"
        @click="emit('updateInbox', null)"
      />
    </div>
    <div
      v-else
      v-on-click-outside="() => emit('toggleDropdown', false)"
      class="relative"
    >
      <Spinner v-if="isFetchingInboxes" :size="20" />
      <button
        v-else
        type="button"
        :disabled="!selectedContact"
        class="w-full flex items-center gap-3 px-4 py-3 rounded-xl border border-dashed transition-colors duration-150 disabled:opacity-50 disabled:cursor-not-allowed"
        :class="
          hasErrors
            ? 'border-n-ruby-9/50 bg-n-ruby-3/30 text-n-ruby-11 hover:border-n-ruby-9/80'
            : 'border-n-strong bg-n-alpha-1 hover:bg-n-brand/5 hover:border-n-brand/40 text-n-slate-11'
        "
        @click="emit('toggleDropdown', !showInboxesDropdown)"
      >
        <span class="i-lucide-inbox size-4" aria-hidden="true" />
        <span class="text-sm font-medium">
          {{ t('COMPOSE_NEW_CONVERSATION.FORM.INBOX_SELECTOR.BUTTON') }}
        </span>
        <span
          class="i-lucide-chevron-down size-4 ltr:ml-auto rtl:mr-auto"
          aria-hidden="true"
        />
      </button>
      <DropdownMenu
        v-if="contactableInboxesList?.length > 0 && showInboxesDropdown"
        :menu-items="contactableInboxesList"
        class="ltr:left-0 rtl:right-0 z-[100] top-12 overflow-y-auto max-h-56 w-full dark:!outline-n-slate-5"
        @action="emit('handleInboxAction', $event)"
      />
    </div>
  </div>
</template>
