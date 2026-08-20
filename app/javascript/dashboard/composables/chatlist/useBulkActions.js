import { ref, unref } from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store.js';
import { useResolveValidation } from 'dashboard/composables/useResolveValidation';
import { useResolveAssignmentGate } from 'dashboard/composables/useResolveAssignmentGate';
import { useConversationRequiredAttributes } from 'dashboard/composables/useConversationRequiredAttributes';
import wootConstants from 'dashboard/constants/globals';

export function useBulkActions() {
  const store = useStore();
  const { t } = useI18n();
  const { checkMissingAttributes } = useConversationRequiredAttributes();

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

  const showTransferTeamModal = ref(false);
  const pendingTransferAgent = ref(null);
  const pendingTransferConversationIds = ref([]);
  const pendingTransferConversationIdsWithoutTeam = ref([]);
  const isSingleTransfer = ref(false);

  const resetPendingAgentTransfer = () => {
    showTransferTeamModal.value = false;
    pendingTransferAgent.value = null;
    pendingTransferConversationIds.value = [];
    pendingTransferConversationIdsWithoutTeam.value = [];
    isSingleTransfer.value = false;
  };

  const normalizeConversationIds = conversationId => {
    if (conversationId === null || conversationId === undefined) {
      return selectedConversations.value;
    }
    return Array.isArray(conversationId) ? conversationId : [conversationId];
  };

  const assignAgentToConversations = async ({ agent, ids, isSingle }) => {
    await store.dispatch('bulkActions/process', {
      type: 'Conversation',
      ids,
      fields: {
        assignee_id: agent?.id ?? null,
      },
    });

    store.dispatch('bulkActions/clearSelectedConversationIds');

    if (isSingle) {
      useAlert(
        t('CONVERSATION.CARD_CONTEXT_MENU.API.AGENT_ASSIGNMENT.SUCCESFUL', {
          agentName: agent?.name || '',
          conversationId: ids[0],
        })
      );
      return;
    }

    useAlert(t('BULK_ACTION.ASSIGN_SUCCESFUL'));
  };

  const hasAssignedTeam = conversation => {
    if (!conversation) {
      return false;
    }
    return Boolean(conversation.meta?.team || conversation.team_id);
  };

  const getConversationsWithoutTeam = conversationIds => {
    const getConversationById =
      store.getters['conversations/getConversationById'];

    return conversationIds.filter(id => {
      const conversation =
        typeof getConversationById === 'function'
          ? getConversationById(id)
          : null;
      return !hasAssignedTeam(conversation);
    });
  };

  // Same method used in context menu, conversationId being passed from there.
  async function onAssignAgent(agent, conversationId = null) {
    const targetIds = normalizeConversationIds(conversationId);
    const transferIsSingle = targetIds.length === 1;

    if (agent?.id) {
      const conversationsWithoutTeam = getConversationsWithoutTeam(targetIds);
      if (!conversationsWithoutTeam.length) {
        try {
          await assignAgentToConversations({
            agent,
            ids: targetIds,
            isSingle: transferIsSingle,
          });
        } catch (err) {
          if (transferIsSingle) {
            useAlert(
              t('CONVERSATION.CARD_CONTEXT_MENU.API.AGENT_ASSIGNMENT.FAILED')
            );
            return;
          }
          useAlert(t('BULK_ACTION.ASSIGN_FAILED'));
        }
        return;
      }

      pendingTransferAgent.value = agent;
      pendingTransferConversationIds.value = targetIds;
      pendingTransferConversationIdsWithoutTeam.value =
        conversationsWithoutTeam;
      isSingleTransfer.value = transferIsSingle;
      showTransferTeamModal.value = true;
      return;
    }

    try {
      await assignAgentToConversations({
        agent,
        ids: targetIds,
        isSingle: transferIsSingle,
      });
    } catch (err) {
      if (transferIsSingle) {
        useAlert(
          t('CONVERSATION.CARD_CONTEXT_MENU.API.AGENT_ASSIGNMENT.FAILED')
        );
        return;
      }
      useAlert(t('BULK_ACTION.ASSIGN_FAILED'));
    }
  }

  const onConfirmAgentTransferTeam = async teamId => {
    if (
      !pendingTransferAgent.value ||
      !pendingTransferConversationIds.value.length ||
      !pendingTransferConversationIdsWithoutTeam.value.length
    ) {
      resetPendingAgentTransfer();
      return;
    }

    const targetIds = [...pendingTransferConversationIds.value];
    const targetIdsWithoutTeam = [
      ...pendingTransferConversationIdsWithoutTeam.value,
    ];
    const targetAgent = pendingTransferAgent.value;
    const transferIsSingle = isSingleTransfer.value;

    try {
      await store.dispatch('bulkActions/process', {
        type: 'Conversation',
        ids: targetIdsWithoutTeam,
        fields: {
          team_id: teamId,
        },
      });

      await store.dispatch('bulkActions/process', {
        type: 'Conversation',
        ids: targetIds,
        fields: {
          assignee_id: targetAgent.id,
        },
      });

      store.dispatch('bulkActions/clearSelectedConversationIds');

      if (transferIsSingle) {
        useAlert(
          t('CONVERSATION.CARD_CONTEXT_MENU.API.AGENT_ASSIGNMENT.SUCCESFUL', {
            agentName: targetAgent.name,
            conversationId: targetIds[0],
          })
        );
      } else {
        useAlert(t('BULK_ACTION.ASSIGN_SUCCESFUL'));
      }
    } catch (error) {
      if (transferIsSingle) {
        useAlert(
          t('CONVERSATION.CARD_CONTEXT_MENU.API.AGENT_ASSIGNMENT.FAILED')
        );
      } else {
        useAlert(t('BULK_ACTION.ASSIGN_FAILED'));
      }
    } finally {
      resetPendingAgentTransfer();
    }
  };

  const cancelAgentTransferTeamSelection = () => {
    resetPendingAgentTransfer();
  };

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

  // Only used in context menu
  async function onRemoveLabels(labelsToRemove, conversationId = null) {
    try {
      await store.dispatch('bulkActions/process', {
        type: 'Conversation',
        ids: conversationId || selectedConversations.value,
        labels: {
          remove: labelsToRemove,
        },
      });

      useAlert(
        t('CONVERSATION.CARD_CONTEXT_MENU.API.LABEL_REMOVAL.SUCCESFUL', {
          labelName: labelsToRemove[0],
          conversationId,
        })
      );
    } catch (err) {
      useAlert(t('CONVERSATION.CARD_CONTEXT_MENU.API.LABEL_REMOVAL.FAILED'));
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

  const { isResolveGateEnabled, isAssignedToMe, currentUserId } =
    useResolveAssignmentGate();

  // "Atribuição obrigatória" — bulk assign-and-resolve confirmation state.
  const showBulkAssignResolveDialog = ref(false);
  const bulkAssignResolveRequiresTeam = ref(false);
  const bulkAssignResolveCount = ref(0);
  const pendingBulkResolve = ref(null);

  // Apply the attributes filter, then dispatch the bulk resolve. When `selfAssign`
  // is set, the acting user is assigned in the same payload so the backend gate
  // (BulkActionsJob) lets the resolve through.
  async function finalizeBulkResolve(
    status,
    snoozedUntil,
    { selfAssign } = {}
  ) {
    const { validIds, skippedIds } = selectedConversations.value.reduce(
      (acc, id) => {
        const conversation = store.getters.getConversationById(id);
        const currentCustomAttributes = conversation?.custom_attributes || {};
        const { hasMissing } = checkMissingAttributes(currentCustomAttributes);

        if (!hasMissing) {
          acc.validIds.push(id);
        } else {
          acc.skippedIds.push(id);
        }
        return acc;
      },
      { validIds: [], skippedIds: [] }
    );

    const conversationIds = validIds;
    const skippedCount = skippedIds.length;

    if (skippedCount > 0 && validIds.length === 0) {
      // All conversations have missing attributes
      useAlert(
        t('BULK_ACTION.RESOLVE.ALL_MISSING_ATTRIBUTES') ||
          'Cannot resolve conversations due to missing required attributes'
      );
      return;
    }

    try {
      if (conversationIds.length > 0) {
        const fields = { status };
        if (selfAssign) {
          fields.assignee_id = currentUserId.value;
        }
        await store.dispatch('bulkActions/process', {
          type: 'Conversation',
          ids: conversationIds,
          fields,
          snoozed_until: snoozedUntil,
        });
      }

      store.dispatch('bulkActions/clearSelectedConversationIds');

      if (skippedCount > 0) {
        useAlert(t('BULK_ACTION.RESOLVE.PARTIAL_SUCCESS'));
      } else {
        useAlert(t('BULK_ACTION.UPDATE.UPDATE_SUCCESFUL'));
      }
    } catch (err) {
      useAlert(t('BULK_ACTION.UPDATE.UPDATE_FAILED'));
    }
  }

  async function onUpdateConversations(status, snoozedUntil) {
    // If resolving, validate teams first (our custom feature)
    if (status === wootConstants.STATUS_TYPE.RESOLVED) {
      // "Atribuição obrigatória": if any selected conversation isn't mine, confirm
      // a single assign-and-resolve before touching anything.
      if (isResolveGateEnabled.value) {
        const hasNonOwned = selectedConversations.value.some(id => {
          const conversation = store.getters.getConversationById(id);
          return !isAssignedToMe(conversation);
        });
        if (hasNonOwned) {
          pendingBulkResolve.value = { status, snoozedUntil };
          bulkAssignResolveRequiresTeam.value =
            getConversationsWithoutTeam(selectedConversations.value).length > 0;
          bulkAssignResolveCount.value = selectedConversations.value.length;
          showBulkAssignResolveDialog.value = true;
          return;
        }
      }

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

      await finalizeBulkResolve(status, snoozedUntil);
      return;
    }

    // Non-resolve bulk status changes go straight through.
    try {
      if (selectedConversations.value.length > 0) {
        await store.dispatch('bulkActions/process', {
          type: 'Conversation',
          ids: selectedConversations.value,
          fields: { status },
          snoozed_until: snoozedUntil,
        });
      }
      store.dispatch('bulkActions/clearSelectedConversationIds');
      useAlert(t('BULK_ACTION.UPDATE.UPDATE_SUCCESFUL'));
    } catch (err) {
      useAlert(t('BULK_ACTION.UPDATE.UPDATE_FAILED'));
    }
  }

  const onConfirmBulkAssignResolve = async ({ teamId } = {}) => {
    const pending = pendingBulkResolve.value;
    showBulkAssignResolveDialog.value = false;
    if (!pending) return;

    // Assign the chosen team to conversations that don't have one yet.
    if (teamId) {
      const idsWithoutTeam = getConversationsWithoutTeam(
        selectedConversations.value
      );
      if (idsWithoutTeam.length) {
        await store.dispatch('bulkActions/process', {
          type: 'Conversation',
          ids: idsWithoutTeam,
          fields: { team_id: teamId },
        });
      }
    }

    await finalizeBulkResolve(pending.status, pending.snoozedUntil, {
      selfAssign: true,
    });
    pendingBulkResolve.value = null;
  };

  const onCancelBulkAssignResolve = () => {
    showBulkAssignResolveDialog.value = false;
    pendingBulkResolve.value = null;
  };

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
    onRemoveLabels,
    onAssignTeamsForBulk,
    onUpdateConversations,
    showTransferTeamModal,
    onConfirmAgentTransferTeam,
    cancelAgentTransferTeamSelection,
    showTeamModal,
    teams,
    handleTeamSelected,
    cancelTeamSelection,
    showBulkAssignResolveDialog,
    bulkAssignResolveRequiresTeam,
    bulkAssignResolveCount,
    onConfirmBulkAssignResolve,
    onCancelBulkAssignResolve,
  };
}
