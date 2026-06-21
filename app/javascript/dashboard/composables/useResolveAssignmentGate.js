import { computed } from 'vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import wootConstants from 'dashboard/constants/globals';

/**
 * "Atribuição obrigatória" mode for resolving conversations.
 *
 * When the account flag `resolve_assignment_gate` is enabled, a human can only
 * resolve a conversation they are assigned to. Anyone else is intercepted with a
 * dialog that self-assigns (and assigns a team if needed) before resolving.
 *
 * The backend (Conversations::ToggleStatusService + BulkActionsJob) is the source
 * of truth; this composable only drives the UX so the action never silently fails.
 */
export function useResolveAssignmentGate() {
  const store = useStore();
  const getters = useStoreGetters();
  const { currentAccount } = useAccount();

  const isResolveGateEnabled = computed(() =>
    Boolean(currentAccount.value?.settings?.resolve_assignment_gate)
  );

  const currentUserId = computed(() => getters.getCurrentUserID.value);

  const getAssignee = conversation => conversation?.meta?.assignee || null;

  const isAssignedToMe = conversation => {
    const assignee = getAssignee(conversation);
    return Boolean(assignee && assignee.id === currentUserId.value);
  };

  /**
   * Whether a manual resolve of this conversation must go through the
   * assign-and-resolve dialog instead of resolving directly.
   */
  const requiresAssignmentToResolve = conversation => {
    if (!isResolveGateEnabled.value) return false;
    return !isAssignedToMe(conversation);
  };

  /**
   * Which copy variant the dialog should render.
   * @returns {'unassigned' | 'colleague' | 'ai'}
   */
  const getResolveVariant = conversation => {
    const assignee = getAssignee(conversation);
    if (!assignee) return 'unassigned';
    if (assignee.type === 'agent_bot' || assignee.is_bot) return 'ai';
    return 'colleague';
  };

  const hasTeam = conversation =>
    Boolean(conversation?.meta?.team || conversation?.team_id);

  /**
   * Self-assign the conversation (optionally assigning a team first) and then
   * resolve it. Mirrors the backend guard's "assign + resolve" sequence so the
   * resolve never gets lost.
   */
  const assignSelfAndResolve = async (
    conversationId,
    { teamId = null, snoozedUntil = null } = {}
  ) => {
    if (teamId) {
      await store.dispatch('assignTeam', { conversationId, teamId });
    }
    await store.dispatch('assignAgent', {
      conversationId,
      agentId: currentUserId.value,
      rethrow: true,
    });
    return store.dispatch('toggleStatus', {
      conversationId,
      status: wootConstants.STATUS_TYPE.RESOLVED,
      snoozedUntil,
    });
  };

  return {
    isResolveGateEnabled,
    currentUserId,
    isAssignedToMe,
    requiresAssignmentToResolve,
    getResolveVariant,
    getAssignee,
    hasTeam,
    assignSelfAndResolve,
  };
}
