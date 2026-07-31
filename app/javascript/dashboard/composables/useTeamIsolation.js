import { computed } from 'vue';
import { useStore } from 'dashboard/composables/store';

export function useTeamIsolation() {
  const store = useStore();

  // Membro ∪ supervisionado (getter da F4). Supervisor de time enxerga as
  // mensagens daquele time sem ser membro dele — é exatamente o que o backend
  // já entrega. Sem ninguém supervisionando, getVisibleTeams devolve o mesmo
  // conjunto de getMyTeams e o comportamento fica idêntico ao de antes.
  const visibleTeamIds = computed(() => {
    const teams = store.getters['teams/getVisibleTeams'] || [];
    return teams.map(t => t.id);
  });

  const currentAccount = computed(() => store.getters.getCurrentAccount || {});

  const isAdmin = computed(() => {
    const user = store.getters.getCurrentUser || {};
    const accountId = currentAccount.value?.id;
    const accountUser = user.accounts?.find(a => a.id === accountId);
    return accountUser?.role === 'administrator';
  });

  const isMessageRestricted = (message, inbox) => {
    if (!inbox?.team_message_isolation && !inbox?.teamMessageIsolation) {
      return false;
    }
    const teamId = message?.team_id ?? message?.teamId;
    if (!teamId) return false;
    if (message?.message_type === 2 || message?.messageType === 2) return false;
    if (isAdmin.value) return false;
    return !visibleTeamIds.value.includes(teamId);
  };

  const getRestrictedPreview = () => '🔒';

  return {
    visibleTeamIds,
    isAdmin,
    isMessageRestricted,
    getRestrictedPreview,
  };
}
