<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import wootConstants from 'dashboard/constants/globals';

import Banner from 'dashboard/components/ui/Banner.vue';
import TeamSelectionModal from './TeamSelectionModal.vue';

const props = defineProps({
  message: {
    type: String,
    default: '',
  },
  isOnPrivateNote: {
    type: Boolean,
    default: false,
  },
});

const store = useStore();
const { t } = useI18n();

const currentChat = useMapGetter('getSelectedChat');
const currentUser = useMapGetter('getCurrentUser');
const teams = useMapGetter('teams/getTeams');

const assignedAgent = computed(() => currentChat.value?.meta?.assignee);
const showTransferTeamModal = ref(false);
const pendingTransferAgent = ref(null);
const isPendingBotHandoff = ref(false);

const isUserTyping = computed(
  () => props.message !== '' && !props.isOnPrivateNote
);
const isUnassigned = computed(() => !assignedAgent.value);
const isAssignedToOtherAgent = computed(
  () => assignedAgent.value?.id !== currentUser.value?.id
);

const showSelfAssignBanner = computed(() => {
  return (
    isUserTyping.value && (isUnassigned.value || isAssignedToOtherAgent.value)
  );
});

const showBotHandoffBanner = computed(
  () =>
    isUserTyping.value &&
    currentChat.value?.status === wootConstants.STATUS_TYPE.PENDING
);

const botHandoffActionLabel = computed(() => {
  return assignedAgent.value?.id === currentUser.value?.id
    ? t('CONVERSATION.BOT_HANDOFF_REOPEN_ACTION')
    : t('CONVERSATION.BOT_HANDOFF_ACTION');
});

const getCurrentUserAsAssignee = () => {
  const { avatar_url, ...rest } = currentUser.value || {};
  return { ...rest, thumbnail: avatar_url };
};

const needsAssignmentToCurrentUser = computed(() => {
  return isUnassigned.value || isAssignedToOtherAgent.value;
});

const conversationHasTeam = computed(() => {
  return Boolean(currentChat.value?.meta?.team || currentChat.value?.team_id);
});

const closeTransferTeamModal = () => {
  showTransferTeamModal.value = false;
  pendingTransferAgent.value = null;
  isPendingBotHandoff.value = false;
};

const openTransferTeamModal = () => {
  pendingTransferAgent.value = getCurrentUserAsAssignee();
  showTransferTeamModal.value = true;
};

const assignPendingAgentWithTeam = async teamId => {
  if (!pendingTransferAgent.value?.id || !currentChat.value?.id) {
    closeTransferTeamModal();
    return;
  }

  try {
    await store.dispatch('assignTeam', {
      conversationId: currentChat.value.id,
      teamId,
      rethrow: true,
    });
    await store.dispatch('assignAgent', {
      conversationId: currentChat.value.id,
      agentId: pendingTransferAgent.value.id,
      rethrow: true,
    });

    if (isPendingBotHandoff.value) {
      useAlert(t('CONVERSATION.BOT_HANDOFF_SUCCESS'));
    } else {
      useAlert(t('CONVERSATION.CHANGE_AGENT'));
    }
  } catch (error) {
    if (isPendingBotHandoff.value) {
      useAlert(t('CONVERSATION.BOT_HANDOFF_ERROR'));
    } else {
      useAlert(t('CONVERSATION.CHANGE_AGENT_FAILED'));
    }
  } finally {
    closeTransferTeamModal();
  }
};

const assignCurrentUserDirect = async ({ isBotHandoff = false } = {}) => {
  const assignee = getCurrentUserAsAssignee();
  if (!assignee?.id || !currentChat.value?.id) {
    return false;
  }

  try {
    await store.dispatch('assignAgent', {
      conversationId: currentChat.value.id,
      agentId: assignee.id,
      rethrow: true,
    });
    useAlert(
      isBotHandoff
        ? t('CONVERSATION.BOT_HANDOFF_SUCCESS')
        : t('CONVERSATION.CHANGE_AGENT')
    );
    return true;
  } catch (error) {
    useAlert(
      isBotHandoff
        ? t('CONVERSATION.BOT_HANDOFF_ERROR')
        : t('CONVERSATION.CHANGE_AGENT_FAILED')
    );
    return false;
  }
};

const onClickSelfAssign = async () => {
  if (conversationHasTeam.value) {
    await assignCurrentUserDirect();
    return;
  }
  openTransferTeamModal();
};

const reopenConversation = async () => {
  await store.dispatch('toggleStatus', {
    conversationId: currentChat.value?.id,
    status: wootConstants.STATUS_TYPE.OPEN,
  });
};

const onClickBotHandoff = async () => {
  try {
    await reopenConversation();

    if (needsAssignmentToCurrentUser.value) {
      if (conversationHasTeam.value) {
        await assignCurrentUserDirect({ isBotHandoff: true });
        return;
      }

      isPendingBotHandoff.value = true;
      openTransferTeamModal();
      return;
    }

    useAlert(t('CONVERSATION.BOT_HANDOFF_SUCCESS'));
  } catch (error) {
    useAlert(t('CONVERSATION.BOT_HANDOFF_ERROR'));
  }
};
</script>

<template>
  <Banner
    v-if="showSelfAssignBanner && !showBotHandoffBanner"
    action-button-variant="ghost"
    color-scheme="secondary"
    class="mx-2 mb-2 rounded-lg !py-2"
    :banner-message="$t('CONVERSATION.NOT_ASSIGNED_TO_YOU')"
    has-action-button
    :action-button-label="$t('CONVERSATION.ASSIGN_TO_ME')"
    @primary-action="onClickSelfAssign"
  />
  <Banner
    v-if="showBotHandoffBanner"
    action-button-variant="ghost"
    color-scheme="secondary"
    class="mx-2 mb-2 rounded-lg !py-2"
    :banner-message="$t('CONVERSATION.BOT_HANDOFF_MESSAGE')"
    has-action-button
    :action-button-label="botHandoffActionLabel"
    @primary-action="onClickBotHandoff"
  />
  <TeamSelectionModal
    :show="showTransferTeamModal"
    :teams="teams"
    :title="$t('CONVERSATION.SELECT_TEAM_FOR_TRANSFER_TITLE')"
    :description="$t('CONVERSATION.SELECT_TEAM_FOR_TRANSFER_DESCRIPTION')"
    @confirm="assignPendingAgentWithTeam"
    @close="closeTransferTeamModal"
  />
</template>
