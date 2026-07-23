import { ref } from 'vue';
import camelcaseKeys from 'camelcase-keys';
import ActiveAttendancesAPI from 'dashboard/api/activeAttendances';

/**
 * Fonte ÚNICA de "este contato já está em atendimento?".
 *
 * Por que não usar o store `contactConversations` (que já está aí):
 * ele passa pelo Conversations::PermissionFilterService, que devolve VAZIO para
 * agente de outro time — e o ConversationBuilder do backend reusa a conversa
 * existente mesmo assim. Ou seja: a fonte antiga diz "não tem nada" justamente
 * no caso que mais importa, e o agente acaba escrevendo dentro de uma conversa
 * que ele nem enxerga. O endpoint da Fase 1 é metadado puro e não filtra por
 * time — é o único que responde a pergunta certa.
 *
 * Também é aqui que as DUAS cópias divergentes de "achar conversa ativa"
 * (ComposeConversation e ContactCard) viram uma só.
 */
export const ATTENDANCE_VARIANT = {
  HUMAN: 'human', // dono humano → dá pra pedir o atendimento (Fase 3)
  BOT: 'bot', // dona IA/AgentBot
  UNASSIGNED: 'unassigned', // conversa aberta na fila, sem dono
  UNKNOWN: 'unknown', // a checagem falhou — ver nota abaixo
};

export function useAttendanceGate() {
  const isChecking = ref(false);

  const fetchAttendances = async contactId => {
    if (!contactId) return [];
    const { data } = await ActiveAttendancesAPI.get({ contactId });
    return (data.payload ?? []).map(record =>
      camelcaseKeys(record, { deep: true })
    );
  };

  const variantFor = attendance => {
    if (!attendance?.assignee) return ATTENDANCE_VARIANT.UNASSIGNED;
    return attendance.assignee.type === 'agent_bot'
      ? ATTENDANCE_VARIANT.BOT
      : ATTENDANCE_VARIANT.HUMAN;
  };

  /**
   * @returns {{blocked, attendance, variant, sameInbox}}
   * blocked = tem que avisar antes de mandar.
   */
  const resolveGate = async ({ contactId, inboxId } = {}) => {
    const notBlocked = {
      blocked: false,
      attendance: null,
      variant: null,
      sameInbox: false,
    };
    if (!contactId) return notBlocked;

    isChecking.value = true;
    let attendances;
    try {
      attendances = await fetchAttendances(contactId);
    } catch {
      // Falhar ABERTO (deixar passar calado) devolve exatamente o bug que esta
      // fase existe pra matar. Falhar FECHADO (barrar) trava trabalho legítimo
      // por causa de um 500. Então: avisa que NÃO deu pra verificar e deixa o
      // agente decidir — a única saída honesta.
      return {
        blocked: true,
        attendance: null,
        variant: ATTENDANCE_VARIANT.UNKNOWN,
        sameInbox: false,
      };
    } finally {
      isChecking.value = false;
    }

    if (!attendances.length) return notBlocked;

    // Cross-inbox de propósito: o contato pode estar em atendimento em OUTRA
    // caixa, e é justamente essa a duplicação a evitar (o
    // getActiveConversationByInbox de hoje filtra por inbox e por isso é cego
    // pra ela). Preferimos a conversa da mesma caixa só para o texto do aviso;
    // o backend já ordena por last_activity_at desc.
    const sameInboxAttendance = inboxId
      ? attendances.find(a => a.inbox?.id === Number(inboxId))
      : null;
    const attendance = sameInboxAttendance || attendances[0];

    return {
      blocked: true,
      attendance,
      variant: variantFor(attendance),
      sameInbox: Boolean(sameInboxAttendance),
    };
  };

  return { isChecking, fetchAttendances, resolveGate };
}
