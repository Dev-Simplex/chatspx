import { computed } from 'vue';
import { useStore } from 'dashboard/composables/store';

export function useTeamIsolation() {
  const store = useStore();

  const myTeamIds = computed(() => {
    const teams = store.getters['teams/getMyTeams'] || [];
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
    if (!inbox?.team_message_isolation && !inbox?.teamMessageIsolation) return false;
    const teamId = message?.team_id ?? message?.teamId;
    if (!teamId) return false;
    if (message?.message_type === 2 || message?.messageType === 2) return false;
    if (isAdmin.value) return false;
    return !myTeamIds.value.includes(teamId);
  };

  const getRestrictedPreview = () => '🔒';

  return {
    myTeamIds,
    isAdmin,
    isMessageRestricted,
    getRestrictedPreview,
  };
}
