import { ref, computed } from 'vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import wootConstants from 'dashboard/constants/globals';

export function useResolveValidation() {
  const store = useStore();
  const getters = useStoreGetters();
  const { t } = useI18n();
  const showTeamModal = ref(false);
  const pendingResolve = ref(null);
  const pendingConversationId = ref(null);
  const pendingBulkConversationIds = ref([]);

  const teams = computed(() => {
    const teamsGetter = store.getters['teams/getTeams'];
    return teamsGetter || [];
  });
  const currentChat = computed(() => getters.getSelectedChat?.value || {});

  const hasAssignedTeam = conversation => {
    if (!conversation) return false;
    if (conversation.meta?.team) {
      return true;
    }
    if (conversation.team_id) {
      return true;
    }
    return false;
  };

  const validateAndResolve = async (
    conversationId,
    status,
    snoozedUntil = null,
    { rethrow = false } = {}
  ) => {
    // Get conversation from store
    const getConversationById =
      store.getters['conversations/getConversationById'];
    const conversation = getConversationById
      ? getConversationById(conversationId)
      : currentChat.value;

    // Check if trying to resolve
    if (status === wootConstants.STATUS_TYPE.RESOLVED) {
      // Check if conversation has team
      if (!hasAssignedTeam(conversation)) {
        // Store pending resolve action
        pendingResolve.value = { conversationId, status, snoozedUntil };
        pendingConversationId.value = conversationId;
        showTeamModal.value = true;
        return Promise.reject(new Error('TEAM_REQUIRED'));
      }
    }

    // If has team or not resolving, proceed normally
    return store.dispatch('toggleStatus', {
      conversationId,
      status,
      snoozedUntil,
      rethrow,
    });
  };

  const validateAndResolveBulk = async (
    conversationIds,
    status,
    snoozedUntil = null
  ) => {
    // Check if trying to resolve
    if (status === wootConstants.STATUS_TYPE.RESOLVED) {
      // Check all conversations for teams
      const getConversationById =
        store.getters['conversations/getConversationById'];
      const conversationsWithoutTeam = conversationIds.filter(id => {
        const conversation = getConversationById
          ? getConversationById(id)
          : null;
        return !hasAssignedTeam(conversation);
      });

      if (conversationsWithoutTeam.length > 0) {
        // Store pending resolve action
        pendingResolve.value = { conversationIds, status, snoozedUntil };
        pendingBulkConversationIds.value = conversationsWithoutTeam;
        showTeamModal.value = true;
        return Promise.reject(new Error('TEAM_REQUIRED'));
      }
    }

    // If all have teams or not resolving, proceed normally
    return Promise.resolve();
  };

  const assignTeamAndResolve = async teamId => {
    try {
      // If single conversation
      if (pendingConversationId.value) {
        // Assign team first
        await store.dispatch('assignTeam', {
          conversationId: pendingConversationId.value,
          teamId,
        });

        // Then resolve
        if (pendingResolve.value) {
          await store.dispatch('toggleStatus', {
            conversationId: pendingConversationId.value,
            status: pendingResolve.value.status,
            snoozedUntil: pendingResolve.value.snoozedUntil,
          });
          useAlert(t('CONVERSATION.RESOLVE_WITH_TEAM_SUCCESS'));
        }
      }
      // If bulk conversations
      else if (pendingBulkConversationIds.value.length > 0) {
        // Assign team to all conversations without team
        const assignPromises = pendingBulkConversationIds.value.map(id =>
          store.dispatch('assignTeam', {
            conversationId: id,
            teamId,
          })
        );
        await Promise.all(assignPromises);

        // Then resolve all
        if (pendingResolve.value?.conversationIds) {
          // Use bulk actions to resolve all
          await store.dispatch('bulkActions/process', {
            type: 'Conversation',
            ids: pendingResolve.value.conversationIds,
            fields: {
              status: pendingResolve.value.status,
            },
            snoozed_until: pendingResolve.value.snoozedUntil,
          });
          useAlert(t('BULK_ACTION.UPDATE.UPDATE_SUCCESFUL'));
        }
      }

      // Reset pending state
      pendingResolve.value = null;
      pendingConversationId.value = null;
      pendingBulkConversationIds.value = [];
      showTeamModal.value = false;
    } catch (error) {
      useAlert(t('CONVERSATION.CHANGE_STATUS_FAILED'));
      throw error;
    }
  };

  const cancelTeamSelection = () => {
    pendingResolve.value = null;
    pendingConversationId.value = null;
    pendingBulkConversationIds.value = [];
    showTeamModal.value = false;
  };

  return {
    showTeamModal,
    teams,
    validateAndResolve,
    validateAndResolveBulk,
    assignTeamAndResolve,
    cancelTeamSelection,
    hasAssignedTeam,
  };
}
