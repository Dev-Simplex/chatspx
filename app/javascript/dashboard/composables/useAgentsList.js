import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useReplyAssignmentGate } from 'dashboard/composables/useReplyAssignmentGate';
import {
  getAgentsByUpdatedPresence,
  getSortedAgentsByAvailability,
} from 'dashboard/helper/agentHelper';

/**
 * A composable function that provides a list of agents for assignment.
 *
 * @param {boolean} [includeNoneAgent=true] - Whether to include a 'None' agent option.
 * @returns {Object} An object containing the agents list and assignable agents.
 */
export function useAgentsList(includeNoneAgent = true) {
  const { t } = useI18n();
  const currentUser = useMapGetter('getCurrentUser');
  const currentChat = useMapGetter('getSelectedChat');
  const currentAccountId = useMapGetter('getCurrentAccountId');
  const assignable = useMapGetter('inboxAssignableAgents/getAssignableAgents');
  const { isAssignmentGateEnabled } = useReplyAssignmentGate();

  const inboxId = computed(() => currentChat.value?.inbox_id);
  const isAgentSelected = computed(() => currentChat.value?.meta?.assignee);

  /**
   * Creates a 'None' agent object
   * @returns {Object} None agent object
   */
  const createNoneAgent = () => ({
    confirmed: true,
    name: t('AGENT_MGMT.MULTI_SELECTOR.LIST.NONE') || 'None',
    id: 0,
    role: 'agent',
    account_id: 0,
    email: 'None',
  });

  /**
   * @type {import('vue').ComputedRef<Array>}
   */
  const assignableAgents = computed(() => {
    return inboxId.value ? assignable.value(inboxId.value) : [];
  });

  const conversationTeamId = computed(
    () =>
      currentChat.value?.meta?.team?.id || currentChat.value?.team_id || null
  );

  /**
   * @type {import('vue').ComputedRef<Array>}
   */
  const agentsList = computed(() => {
    let agents = assignableAgents.value || [];

    // When conversation has a team, filter to agents belonging to that team
    // plus administrators (who can be assigned to any team)
    if (conversationTeamId.value) {
      agents = agents.filter(agent => {
        if (agent.role === 'administrator') return true;
        const teamIds = agent.team_ids || [];
        return teamIds.includes(conversationTeamId.value);
      });
    }

    const agentsByUpdatedPresence = getAgentsByUpdatedPresence(
      agents,
      currentUser.value,
      currentAccountId.value
    );

    const filteredAgentsByAvailability = getSortedAgentsByAvailability(
      agentsByUpdatedPresence
    );

    // Modo "Atribuição obrigatória" (D-11): sem opção "None" na atribuição manual
    const showNone =
      includeNoneAgent &&
      isAgentSelected.value &&
      !isAssignmentGateEnabled.value;

    return [
      ...(showNone ? [createNoneAgent()] : []),
      ...filteredAgentsByAvailability,
    ];
  });

  return {
    agentsList,
    assignableAgents,
  };
}
