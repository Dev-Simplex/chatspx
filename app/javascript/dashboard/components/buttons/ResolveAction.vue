<script setup>
import { ref, computed } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useToggle } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useEmitter } from 'dashboard/composables/emitter';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useResolveValidation } from 'dashboard/composables/useResolveValidation';
import { useConversationRequiredAttributes } from 'dashboard/composables/useConversationRequiredAttributes';

import WootDropdownItem from 'shared/components/ui/dropdown/DropdownItem.vue';
import WootDropdownMenu from 'shared/components/ui/dropdown/DropdownMenu.vue';
import wootConstants from 'dashboard/constants/globals';
import {
  CMD_REOPEN_CONVERSATION,
  CMD_RESOLVE_CONVERSATION,
} from 'dashboard/helper/commandbar/events';

import ButtonGroup from 'dashboard/components-next/buttonGroup/ButtonGroup.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TeamSelectionModal from 'dashboard/components/widgets/conversation/TeamSelectionModal.vue';
import ConversationResolveAttributesModal from 'dashboard/components-next/ConversationWorkflow/ConversationResolveAttributesModal.vue';

const store = useStore();
const getters = useStoreGetters();
const { t } = useI18n();
const { checkMissingAttributes } = useConversationRequiredAttributes();

const {
  showTeamModal,
  teams,
  validateAndResolve,
  assignTeamAndResolve,
  cancelTeamSelection,
} = useResolveValidation();

const arrowDownButtonRef = ref(null);
const isLoading = ref(false);
const resolveAttributesModalRef = ref(null);

const [showActionsDropdown, toggleDropdown] = useToggle();
const closeDropdown = () => toggleDropdown(false);
const openDropdown = () => toggleDropdown(true);

const currentChat = computed(() => getters.getSelectedChat.value);

const isOpen = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.OPEN
);
const isPending = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.PENDING
);
const isResolved = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.RESOLVED
);
const isSnoozed = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.SNOOZED
);

const showAdditionalActions = computed(
  () => !isPending.value && !isSnoozed.value
);

const showOpenButton = computed(() => {
  return isPending.value || isSnoozed.value;
});

const getConversationParams = () => {
  const allConversations = document.querySelectorAll(
    '.conversations-list .conversation'
  );

  const activeConversation = document.querySelector(
    'div.conversations-list div.conversation.active'
  );
  const activeConversationIndex = [...allConversations].indexOf(
    activeConversation
  );
  const lastConversationIndex = allConversations.length - 1;

  return {
    all: allConversations,
    activeIndex: activeConversationIndex,
    lastIndex: lastConversationIndex,
  };
};

const openSnoozeModal = () => {
  const ninja = document.querySelector('ninja-keys');
  ninja.open({ parent: 'snooze_conversation' });
};

const toggleStatus = async (status, snoozedUntil, customAttributes = null) => {
  closeDropdown();
  isLoading.value = true;
  try {
    const payload = {
      conversationId: currentChat.value.id,
      status,
      snoozedUntil,
    };

    if (customAttributes) {
      payload.customAttributes = customAttributes;
    }

    // Use team validation for resolve
    if (status === wootConstants.STATUS_TYPE.RESOLVED && !customAttributes) {
      await validateAndResolve(currentChat.value.id, status, snoozedUntil);
    } else {
      await store.dispatch('toggleStatus', payload);
    }
    useAlert(t('CONVERSATION.CHANGE_STATUS'));
  } catch (error) {
    if (error.message !== 'TEAM_REQUIRED') {
      useAlert(t('CONVERSATION.CHANGE_STATUS_FAILED'));
    }
  } finally {
    isLoading.value = false;
  }
};

const handleResolveWithAttributes = ({ attributes, context }) => {
  if (context) {
    const currentCustomAttributes = currentChat.value.custom_attributes || {};
    const mergedAttributes = { ...currentCustomAttributes, ...attributes };
    toggleStatus(
      wootConstants.STATUS_TYPE.RESOLVED,
      context.snoozedUntil,
      mergedAttributes
    );
  }
};

const onCmdOpenConversation = () => {
  toggleStatus(wootConstants.STATUS_TYPE.OPEN);
};

const onCmdResolveConversation = () => {
  const currentCustomAttributes = currentChat.value.custom_attributes || {};
  const { hasMissing, missing } = checkMissingAttributes(
    currentCustomAttributes
  );

  if (hasMissing) {
    const conversationContext = {
      id: currentChat.value.id,
      snoozedUntil: null,
    };
    resolveAttributesModalRef.value?.open(
      missing,
      currentCustomAttributes,
      conversationContext
    );
  } else {
    toggleStatus(wootConstants.STATUS_TYPE.RESOLVED);
  }
};

const handleTeamSelected = async teamId => {
  try {
    await assignTeamAndResolve(teamId);
  } catch (error) {
    // Error already handled in assignTeamAndResolve
  }
};

const keyboardEvents = {
  'Alt+KeyM': {
    action: () => arrowDownButtonRef.value?.$el.click(),
    allowOnFocusedInput: true,
  },
  'Alt+KeyE': {
    action: async () => {
      onCmdResolveConversation();
    },
  },
  '$mod+Alt+KeyE': {
    action: async event => {
      const { all, activeIndex, lastIndex } = getConversationParams();
      onCmdResolveConversation();

      if (activeIndex < lastIndex) {
        all[activeIndex + 1].click();
      } else if (all.length > 1) {
        all[0].click();
        document.querySelector('.conversations-list').scrollTop = 0;
      }
      event.preventDefault();
    },
  },
};

useKeyboardEvents(keyboardEvents);

useEmitter(CMD_REOPEN_CONVERSATION, onCmdOpenConversation);
useEmitter(CMD_RESOLVE_CONVERSATION, onCmdResolveConversation);
</script>

<template>
  <div class="flex relative justify-end items-center resolve-actions">
    <ButtonGroup class="flex-shrink-0 rounded-lg">
      <Button
        v-if="isOpen"
        v-tooltip.top="`${t('CONVERSATION.HEADER.RESOLVE_ACTION')} (Alt+E)`"
        :label="t('CONVERSATION.HEADER.RESOLVE_ACTION')"
        size="sm"
        no-animation
        class="ltr:rounded-r-none rtl:rounded-l-none !outline-0 !bg-n-brand !text-white hover:!bg-[#1FB85A] !font-medium"
        :is-loading="isLoading"
        @click="onCmdResolveConversation"
      />
      <Button
        v-else-if="isResolved"
        v-tooltip.top="t('CONVERSATION.HEADER.REOPEN_ACTION')"
        :label="t('CONVERSATION.HEADER.REOPEN_ACTION')"
        size="sm"
        no-animation
        class="ltr:rounded-r-none rtl:rounded-l-none !outline-0 !bg-n-slate-8 !text-white hover:!bg-n-slate-9 !font-medium"
        :is-loading="isLoading"
        @click="onCmdOpenConversation"
      />
      <Button
        v-else-if="showOpenButton"
        v-tooltip.top="t('CONVERSATION.HEADER.OPEN_ACTION')"
        :label="t('CONVERSATION.HEADER.OPEN_ACTION')"
        size="sm"
        no-animation
        class="!bg-n-slate-8 !text-white hover:!bg-n-slate-9 !font-medium"
        :is-loading="isLoading"
        @click="onCmdOpenConversation"
      />
      <Button
        v-if="showAdditionalActions"
        ref="arrowDownButtonRef"
        v-tooltip.top="`${t('CONVERSATION.HEADER.MORE_ACTIONS')} (Alt+M)`"
        icon="i-lucide-chevron-down"
        :disabled="isLoading"
        size="sm"
        no-animation
        class="ltr:rounded-l-none rtl:rounded-r-none !outline-0"
        :class="
          isOpen
            ? '!bg-n-brand !text-white hover:!bg-[#1FB85A]'
            : '!bg-n-slate-8 !text-white hover:!bg-n-slate-9'
        "
        trailing-icon
        @click="openDropdown"
      />
    </ButtonGroup>
    <div
      v-if="showActionsDropdown"
      v-on-clickaway="closeDropdown"
      class="bg-n-solid-1 border border-n-weak rounded-xl shadow-lg p-1 w-fit z-10 absolute block left-auto top-full mt-0.5 start-0 xl:start-auto xl:end-0 max-w-[12.5rem] min-w-[9.75rem] [&_ul>li]:mb-0"
    >
      <WootDropdownMenu class="mb-0">
        <WootDropdownItem v-if="!isPending">
          <Button
            :label="t('CONVERSATION.RESOLVE_DROPDOWN.SNOOZE_UNTIL')"
            ghost
            slate
            sm
            start
            icon="i-lucide-alarm-clock-minus"
            class="w-full"
            @click="() => openSnoozeModal()"
          />
        </WootDropdownItem>
        <WootDropdownItem v-if="!isPending">
          <Button
            :label="t('CONVERSATION.RESOLVE_DROPDOWN.MARK_PENDING')"
            ghost
            slate
            sm
            start
            icon="i-lucide-circle-dot-dashed"
            class="w-full"
            @click="() => toggleStatus(wootConstants.STATUS_TYPE.PENDING)"
          />
        </WootDropdownItem>
      </WootDropdownMenu>
    </div>
    <TeamSelectionModal
      :show="showTeamModal"
      :teams="teams"
      :is-bulk="false"
      @confirm="handleTeamSelected"
      @close="cancelTeamSelection"
    />
    <ConversationResolveAttributesModal
      ref="resolveAttributesModalRef"
      @submit="handleResolveWithAttributes"
    />
  </div>
</template>
