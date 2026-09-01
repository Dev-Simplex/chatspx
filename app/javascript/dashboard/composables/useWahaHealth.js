import { ref, onMounted, onBeforeUnmount } from 'vue';
import wahaConnectionsAPI from 'dashboard/api/wahaConnections';

// Estados em que a linha NÃO entrega mensagem. MISSING = a sessão nem existe
// mais no servidor WAHA (apagada, renomeada, nunca criada) — o pior caso, e o
// que antes não aparecia em lugar nenhum.
export const WAHA_DOWN_STATUSES = [
  'STOPPED',
  'FAILED',
  'SCAN_QR_CODE',
  'MISSING',
];

const POLL_INTERVAL = 90000;

// Estado de módulo: um único ciclo de polling atende todos os consumidores
// (banner do admin + aviso acima do composer), sem multiplicar chamadas.
const statusByInboxId = ref({});
let consumerCount = 0;
let pollTimer = null;

const fetchHealth = async () => {
  try {
    const { data } = await wahaConnectionsAPI.health();
    const next = {};
    (Array.isArray(data) ? data : []).forEach(item => {
      next[item.inbox_id] = item.status;
    });
    statusByInboxId.value = next;
  } catch {
    // Falha de rede não é prova de linha caída: zera para não alarmar à toa.
    statusByInboxId.value = {};
  }
};

export function useWahaHealth() {
  onMounted(() => {
    consumerCount += 1;
    if (consumerCount === 1) {
      fetchHealth();
      pollTimer = setInterval(fetchHealth, POLL_INTERVAL);
    }
  });

  onBeforeUnmount(() => {
    consumerCount -= 1;
    if (consumerCount === 0 && pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  });

  const isInboxLineDown = inboxId =>
    WAHA_DOWN_STATUSES.includes(statusByInboxId.value[inboxId]);

  return { statusByInboxId, isInboxLineDown };
}
