import { ref, computed, watch, unref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAttendanceGate } from 'dashboard/composables/useAttendanceGate';

// Decide o que a PÁGINA DE CONTATO pode fazer com um contato, do ponto de vista
// de QUEM está olhando. Fonte única do botão do header (Enviar/Solicitar/...) e
// dado da aba "Andamento".
//
// Reusa o endpoint da Fase 1 (active_attendances?contact_id=) via
// useAttendanceGate.fetchAttendances: ele já traz, por conversa e CROSS-TEAM,
// can_request / my_pending_request_id / assignee / team / inbox — o
// contactConversations NÃO serve (é cego a outro time). Nenhum backend novo.
export const SEND_ACTION = {
  SEND: 'send', // "Enviar mensagem" normal
  REQUEST: 'request', // "Solicitar atendimento" (dono é colega)
  PENDING: 'pending', // "Pedido enviado · Cancelar" (já pedi)
  BLOCKED: 'blocked', // desabilitado (outro time, sem como pedir)
};

export function useContactAttendance(contactId) {
  const { currentAccount } = useAccount();
  const { fetchAttendances } = useAttendanceGate();

  const currentUserId = useMapGetter('getCurrentUserID');
  const currentRole = useMapGetter('getCurrentRole');
  // Observado só p/ refazer o fetch quando um pedido muda de estado (realtime).
  const takeoverRecords = useMapGetter('takeoverRequests/getIncoming');

  const attendances = ref([]);
  const isFetching = ref(false);

  const gateEnabled = computed(() =>
    Boolean(currentAccount.value?.settings?.takeover_request_gate)
  );
  const isAdmin = computed(() => currentRole.value === 'administrator');

  const refetch = async () => {
    const id = unref(contactId);
    if (!id) {
      attendances.value = [];
      return;
    }
    isFetching.value = true;
    try {
      attendances.value = await fetchAttendances(id);
    } catch {
      attendances.value = [];
    } finally {
      isFetching.value = false;
    }
  };

  const isMine = a =>
    a.assignee?.type === 'user' && a.assignee.id === currentUserId.value;
  const isHuman = a => a.assignee?.type === 'user';

  // Já atendo este contato em algum lugar? Então posso mandar mensagem à vontade.
  const iAlreadyServe = computed(() => attendances.value.some(isMine));

  // O atendimento "de colega" mais recente (a lista vem ordenada por atividade
  // desc do backend) — é contra ele que o pedido é feito e é o do status.
  const colleagueAttendance = computed(
    () => attendances.value.find(a => isHuman(a) && !isMine(a)) ?? null
  );

  const statusLabel = computed(() => {
    const a = colleagueAttendance.value;
    if (!a) return null;
    return {
      name: a.assignee.availableName || a.assignee.name,
      team: a.team?.name || null,
    };
  });

  const sendAction = computed(() => {
    // Fora do modo, admin, ou eu já atendendo → botão normal (nada muda).
    if (!gateEnabled.value || isAdmin.value || iAlreadyServe.value) {
      return { type: SEND_ACTION.SEND };
    }
    const a = colleagueAttendance.value;
    if (!a) return { type: SEND_ACTION.SEND }; // sem dono / IA / sem atendimento

    if (a.myPendingRequestId) {
      return { type: SEND_ACTION.PENDING, requestId: a.myPendingRequestId };
    }
    if (a.canRequest) {
      return { type: SEND_ACTION.REQUEST, conversationId: a.id };
    }
    // dono de outro time e não posso pedir → sem saída por aqui.
    return { type: SEND_ACTION.BLOCKED };
  });

  watch(() => unref(contactId), refetch, { immediate: true });
  // dono aprovou/negou/cancelou com a página aberta → reflete sem F5.
  watch(takeoverRecords, refetch);

  return { attendances, isFetching, refetch, statusLabel, sendAction };
}
