import { computed, ref, onMounted, onBeforeUnmount } from 'vue';

// Defaults em segundos: 5min âmbar / 15min laranja / 30min vermelho
const DEFAULT_THRESHOLDS = [5 * 60, 15 * 60, 30 * 60];

/**
 * Calcula nível de urgência (0-3) de uma conversa atribuída a mim
 * com mensagens não respondidas, escalando por tempo.
 *
 *   0 = neutro (não atribuída a mim, sem unread, ou < 5min)
 *   1 = âmbar (atenção, 5-15min)
 *   2 = laranja (urgente, 15-30min)
 *   3 = vermelho (crítico, 30+min)
 *
 * Respeita SLA do inbox quando configurado (first_response_threshold em segundos):
 *   thresholds = [SLA*0.33, SLA*0.66, SLA]
 *
 * Recomputa a cada 30s — nível pode mudar sem nova ação do user.
 *
 * @param {Ref<Object>} conversation — ref/computed da conversa
 * @param {Ref<number>} currentUserId — ref do id do user logado
 * @param {Ref<Object>} inbox — ref do inbox da conversa (pra SLA)
 * @returns { urgencyLevel, urgencyClass }
 */
export function useConversationUrgency(conversation, currentUserId, inbox) {
  const tick = ref(Date.now());
  let timer = null;

  onMounted(() => {
    timer = setInterval(() => {
      tick.value = Date.now();
    }, 30 * 1000);
  });

  onBeforeUnmount(() => {
    if (timer) clearInterval(timer);
  });

  const urgencyLevel = computed(() => {
    // referencia tick pra forçar recompute (recalcula a cada 30s)
    const _ = tick.value; // eslint-disable-line no-unused-vars
    const c = conversation.value;
    if (!c) return 0;

    // Filtros — TODAS precisam ser true
    const assigneeId = c.meta?.assignee?.id ?? c.assignee_id;
    const assignedToMe =
      currentUserId.value && assigneeId === currentUserId.value;
    const isOpen = c.status === 'open';
    const hasUnread = (c.unread_count || 0) > 0;

    if (!assignedToMe || !isOpen || !hasUnread) return 0;

    // Tempo decorrido desde última atividade da conversa.
    // `timestamp` no Chatwoot é unix seconds (last activity).
    const lastActivityTs = c.timestamp;
    if (!lastActivityTs) return 0;
    const elapsedSec = Math.floor(Date.now() / 1000) - lastActivityTs;
    if (elapsedSec < 0) return 0;

    // Thresholds — usa SLA do inbox quando disponível
    const slaSeconds =
      inbox?.value?.sla_policy?.first_response_threshold ||
      c.sla_policy?.first_response_threshold;

    let thresholds;
    if (slaSeconds && slaSeconds > 0) {
      thresholds = [slaSeconds * 0.33, slaSeconds * 0.66, slaSeconds];
    } else {
      thresholds = DEFAULT_THRESHOLDS;
    }

    if (elapsedSec >= thresholds[2]) return 3;
    if (elapsedSec >= thresholds[1]) return 2;
    if (elapsedSec >= thresholds[0]) return 1;
    return 0;
  });

  const urgencyClass = computed(() => {
    const lvl = urgencyLevel.value;
    if (lvl === 0) return '';
    return `wa-urgency-${lvl}`;
  });

  return { urgencyLevel, urgencyClass };
}
