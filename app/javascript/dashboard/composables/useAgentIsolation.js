import { computed } from 'vue';
import { useStore } from 'dashboard/composables/store';

// Espelho de useTeamIsolation, mas por AGENTE: cada agente só vê as mensagens que
// ele mesmo enviou (agent_id === eu) + as públicas (agent_id NULL: cliente, bot,
// atividade, template). Admin vê tudo. Usado nos previews (lista/kanban) p/ mascarar
// com 🔒 — a bolha em si é tratada no Message.vue (isRestrictedByAgent).
export function useAgentIsolation() {
  const store = useStore();

  const currentUserId = computed(() => store.getters.getCurrentUser?.id);

  const currentAccount = computed(() => store.getters.getCurrentAccount || {});

  const isAdmin = computed(() => {
    const user = store.getters.getCurrentUser || {};
    const accountId = currentAccount.value?.id;
    const accountUser = user.accounts?.find(a => a.id === accountId);
    return accountUser?.role === 'administrator';
  });

  const isMessageRestricted = (message, inbox) => {
    if (!inbox?.agent_message_isolation && !inbox?.agentMessageIsolation) {
      return false;
    }
    const agentId = message?.agent_id ?? message?.agentId;
    if (!agentId) return false;
    if (message?.message_type === 2 || message?.messageType === 2) return false;
    if (isAdmin.value) return false;
    return agentId !== currentUserId.value;
  };

  const getRestrictedPreview = () => '🔒';

  return {
    currentUserId,
    isAdmin,
    isMessageRestricted,
    getRestrictedPreview,
  };
}
