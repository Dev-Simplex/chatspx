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

  const supervisedTeamIds = computed(() => {
    const teams = store.getters['teams/getSupervisedTeams'] || [];
    return teams.map(t => t.id);
  });

  // O time é o DA CONVERSA (não o da mensagem): o backend isenta o supervisor por
  // conversa, então a máscara aqui tem que usar o mesmo eixo. O call site passa a
  // conversa quando já a tem em mãos; senão caímos no store pelo conversation_id
  // da mensagem — que é o display_id, exatamente a chave de getConversationById.
  const conversationTeamIdFor = (message, conversation) => {
    const chat =
      conversation ||
      store.getters.getConversationById?.(
        message?.conversation_id ?? message?.conversationId
      );
    return chat?.meta?.team?.id ?? chat?.team_id ?? chat?.teamId ?? null;
  };

  const isSupervisedConversation = (message, conversation) => {
    // Curto-circuito: sem NENHUMA supervisão nem consultamos o store, então o
    // caminho do agente comum fica byte-a-byte o de antes.
    if (!supervisedTeamIds.value.length) return false;
    const teamId = conversationTeamIdFor(message, conversation);
    return !!teamId && supervisedTeamIds.value.includes(teamId);
  };

  const isMessageRestricted = (message, inbox, conversation) => {
    if (!inbox?.agent_message_isolation && !inbox?.agentMessageIsolation) {
      return false;
    }
    const agentId = message?.agent_id ?? message?.agentId;
    if (!agentId) return false;
    if (message?.message_type === 2 || message?.messageType === 2) return false;
    if (isAdmin.value) return false;
    if (agentId === currentUserId.value) return false;
    // Supervisor do time da conversa vê todas as bolhas dela (o MessageFinder já
    // as devolve); mascarar aqui seria o front desmentir o backend.
    return !isSupervisedConversation(message, conversation);
  };

  const getRestrictedPreview = () => '🔒';

  return {
    currentUserId,
    isAdmin,
    isSupervisedConversation,
    isMessageRestricted,
    getRestrictedPreview,
  };
}
