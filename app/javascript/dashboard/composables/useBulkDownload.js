import { ref, computed, onScopeDispose } from 'vue';
import AttachmentBulkDownloadsAPI from 'dashboard/api/attachmentBulkDownloads';

const POLL_INTERVAL_MS = 2500;
const MAX_POLL_ATTEMPTS = 360; // ~15 min de segurança

// Mapeia o código de erro do backend para a chave i18n exibida no toast.
const ERROR_KEYS = {
  too_many_files: 'GALLERY.BULK.ERROR_TOO_MANY',
  too_large: 'GALLERY.BULK.ERROR_TOO_LARGE',
  export_active: 'GALLERY.BULK.ERROR_ACTIVE',
  nothing_to_download: 'GALLERY.BULK.ERROR_EMPTY',
};

/**
 * Fluxo de download em massa (zip assíncrono + polling), compartilhado entre a
 * Galeria e a aba "Mídias e Arquivos" da conversa. Dispara o create, faz poll
 * até completed/failed e baixa o zip automaticamente ao concluir.
 *
 * Estados de `status`: 'idle' | 'preparing' | 'ready' | 'error'.
 */
export function useBulkDownload() {
  const status = ref('idle');
  const processed = ref(0);
  const total = ref(0);
  const errorMeta = ref(null); // { key, params }
  // Guarda SÍNCRONA contra duplo-clique: vira true no mesmo tick do @click, antes
  // de qualquer await/transição de `status` (que é assíncrona). Garante um único
  // `create` por clique. Resetada quando o fluxo sai de 'preparing'.
  const isStarting = ref(false);

  let timer = null;
  let attempts = 0;
  // Tolera erros de rede transitórios no polling: o job segue server-side, então
  // só desistimos após algumas falhas consecutivas (não na primeira).
  let pollErrors = 0;
  const MAX_POLL_ERRORS = 3;

  const isPreparing = computed(() => status.value === 'preparing');

  const stopTimer = () => {
    if (timer) {
      clearTimeout(timer);
      timer = null;
    }
  };

  const reset = () => {
    stopTimer();
    status.value = 'idle';
    processed.value = 0;
    total.value = 0;
    errorMeta.value = null;
    isStarting.value = false;
    attempts = 0;
    pollErrors = 0;
  };

  const triggerBrowserDownload = url => {
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.rel = 'noopener';
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
  };

  const fail = meta => {
    stopTimer();
    status.value = 'error';
    errorMeta.value = meta;
  };

  // Retorna true se o registro já está num estado terminal (completed/failed).
  const handleTerminal = record => {
    if (record.status === 'completed' && record.download_url) {
      status.value = 'ready';
      triggerBrowserDownload(record.download_url);
      return true;
    }
    if (record.status === 'failed') {
      fail({ key: 'GALLERY.BULK.ERROR_FAILED', params: {} });
      return true;
    }
    return false;
  };

  const poll = async id => {
    attempts += 1;
    if (attempts > MAX_POLL_ATTEMPTS) {
      fail({ key: 'GALLERY.BULK.ERROR_TIMEOUT', params: {} });
      return;
    }
    try {
      const { data } = await AttachmentBulkDownloadsAPI.show(id);
      pollErrors = 0;
      processed.value = data.processed_count || 0;
      total.value = data.total_count || total.value;
      if (!handleTerminal(data)) {
        timer = setTimeout(() => poll(id), POLL_INTERVAL_MS);
      }
    } catch (error) {
      pollErrors += 1;
      if (pollErrors >= MAX_POLL_ERRORS) {
        fail({ key: 'GALLERY.BULK.ERROR_FAILED', params: {} });
        return;
      }
      timer = setTimeout(() => poll(id), POLL_INTERVAL_MS);
    }
  };

  const start = async payload => {
    // Re-entrância: ignora cliques enquanto um pedido está em voo (isStarting) ou
    // já preparando. Fecha a janela do duplo-clique de forma síncrona.
    if (isStarting.value || status.value === 'preparing') return;
    reset();
    isStarting.value = true;
    status.value = 'preparing';
    try {
      const { data } = await AttachmentBulkDownloadsAPI.create(payload);
      total.value = data.total_count || 0;
      processed.value = data.processed_count || 0;
      if (!handleTerminal(data)) {
        timer = setTimeout(() => poll(data.id), POLL_INTERVAL_MS);
      }
    } catch (error) {
      const body = error?.response?.data || {};
      const key = ERROR_KEYS[body.error] || 'GALLERY.BULK.ERROR_FAILED';
      const params = {};
      if (body.error === 'too_many_files') params.limit = body.limit;
      if (body.error === 'too_large') params.limit = '2 GB';
      fail({ key, params });
    } finally {
      // create resolvido: o estado agora é refletido por isPreparing/ready/error.
      isStarting.value = false;
    }
  };

  onScopeDispose(stopTimer);

  return {
    status,
    processed,
    total,
    errorMeta,
    isPreparing,
    isStarting,
    start,
    reset,
  };
}
