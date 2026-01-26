import { ref, unref } from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store.js';
import { useResolveValidation } from 'dashboard/composables/useResolveValidation';
import wootConstants from 'dashboard/constants/globals';

export function useBulkActions() {
  const store = useStore();
  const { t } = useI18n();

  const selectedConversations = useMapGetter(
    'bulkActions/getSelectedConversationIds'
  );
  const selectedInboxes = ref([]);

  function selectConversation(conversationId, inboxId) {
    store.dispatch('bulkActions/setSelectedConversationIds', conversationId);
    selectedInboxes.value = [...selectedInboxes.value, inboxId];
  }

  function deSelectConversation(conversationId, inboxId) {
    store.dispatch('bulkActions/removeSelectedConversationIds', conversationId);
    selectedInboxes.value = selectedInboxes.value.filter(
      item => item !== inboxId
    );
  }

  function resetBulkActions() {
    store.dispatch('bulkActions/clearSelectedConversationIds');
    selectedInboxes.value = [];
  }

  function selectAllConversations(check, conversationList) {
    const availableConversations = unref(conversationList);
    if (check) {
      store.dispatch(
        'bulkActions/setSelectedConversationIds',
        availableConversations.map(item => item.id)
      );
      selectedInboxes.value = availableConversations.map(item => item.inbox_id);
    } else {
      resetBulkActions();
    }
  }

  function isConversationSelected(id) {
    return selectedConversations.value.includes(id);
  }

  // Same method used in context menu, conversationId being passed from there.
  async function onAssignAgent(agent, conversationId = null) {
    try {
      await store.dispatch('bulkActions/process', {
        type: 'Conversation',
        ids: conversationId || selectedConversations.value,
        fields: {
          assignee_id: agent.id,
        },
      });
      store.dispatch('bulkActions/clearSelectedConversationIds');
      if (conversationId) {
        useAlert(
          t('CONVERSATION.CARD_CONTEXT_MENU.API.AGENT_ASSIGNMENT.SUCCESFUL', {
            agentName: agent.name,
            conversationId,
          })
        );
      } else {
        useAlert(t('BULK_ACTION.ASSIGN_SUCCESFUL'));
      }
    } catch (err) {
      useAlert(t('BULK_ACTION.ASSIGN_FAILED'));
    }
  }

  // Same method used in context menu, conversationId being passed from there.
  async function onAssignLabels(newLabels, conversationId = null) {
    try {
      await store.dispatch('bulkActions/process', {
        type: 'Conversation',
        ids: conversationId || selectedConversations.value,
        labels: {
          add: newLabels,
        },
      });
      store.dispatch('bulkActions/clearSelectedConversationIds');
      if (conversationId) {
        useAlert(
          t('CONVERSATION.CARD_CONTEXT_MENU.API.LABEL_ASSIGNMENT.SUCCESFUL', {
            labelName: newLabels[0],
            conversationId,
          })
        );
      } else {
        useAlert(t('BULK_ACTION.LABELS.ASSIGN_SUCCESFUL'));
      }
    } catch (err) {
      useAlert(t('BULK_ACTION.LABELS.ASSIGN_FAILED'));
    }
  }

  async function onAssignTeamsForBulk(team) {
    try {
      await store.dispatch('bulkActions/process', {
        type: 'Conversation',
        ids: selectedConversations.value,
        fields: {
          team_id: team.id,
        },
      });
      store.dispatch('bulkActions/clearSelectedConversationIds');
      useAlert(t('BULK_ACTION.TEAMS.ASSIGN_SUCCESFUL'));
    } catch (err) {
      useAlert(t('BULK_ACTION.TEAMS.ASSIGN_FAILED'));
    }
  }

  const {
    showTeamModal,
    teams,
    validateAndResolveBulk,
    assignTeamAndResolve,
    cancelTeamSelection,
  } = useResolveValidation();

  async function onUpdateConversations(status, snoozedUntil) {
    try {
      // If resolving, validate teams first
      if (status === wootConstants.STATUS_TYPE.RESOLVED) {
        try {
          await validateAndResolveBulk(
            selectedConversations.value,
            status,
            snoozedUntil
          );
        } catch (error) {
          if (error.message === 'TEAM_REQUIRED') {
            // Modal will be shown by composable
            return;
          }
          throw error;
        }
      }

      // If all have teams or not resolving, proceed normally
      await store.dispatch('bulkActions/process', {
        type: 'Conversation',
        ids: selectedConversations.value,
        fields: {
          status,
        },
        snoozed_until: snoozedUntil,
      });
      store.dispatch('bulkActions/clearSelectedConversationIds');
      useAlert(t('BULK_ACTION.UPDATE.UPDATE_SUCCESFUL'));
    } catch (err) {
      useAlert(t('BULK_ACTION.UPDATE.UPDATE_FAILED'));
    }
  }

  const handleTeamSelected = async teamId => {
    try {
      await assignTeamAndResolve(teamId);
      store.dispatch('bulkActions/clearSelectedConversationIds');
    } catch (error) {
      // Error already handled in assignTeamAndResolve
    }
  };

  return {
    selectedConversations,
    selectedInboxes,
    selectConversation,
    deSelectConversation,
    selectAllConversations,
    resetBulkActions,
    isConversationSelected,
    onAssignAgent,
    onAssignLabels,
    onAssignTeamsForBulk,
    onUpdateConversations,
    showTeamModal,
    teams,
    handleTeamSelected,
    cancelTeamSelection,
  };
}
