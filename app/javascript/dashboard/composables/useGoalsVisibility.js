import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper';

// CHAT-177: "Metas" aparece para quem gerencia ou quando a conta liberou o ranking ao atendente.
// Uma regra so, usada pelas abas dos relatorios (ReportTabs) e por quem mais precisar.
export const useGoalsVisibility = () => {
  const accountId = useMapGetter('getCurrentAccountId');
  const currentUser = useMapGetter('getCurrentUser');
  const getAccount = useMapGetter('accounts/getAccount');

  const showGoals = computed(() => {
    const permissions = getUserPermissions(currentUser.value, accountId.value);
    const visibility = getAccount.value(accountId.value)?.settings
      ?.goals_visibility;
    return (
      permissions.includes('administrator') ||
      permissions.includes('team_supervisor') ||
      ['own', 'everyone'].includes(visibility)
    );
  });

  return { showGoals };
};
