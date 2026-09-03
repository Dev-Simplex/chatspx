/**
 * O diagnostico de uma inbox (bloco 5.14, T-C8.3/T-C8.5, T4.6/T4.7).
 *
 * O aceite do bloco e uma frase de operacao, nao de codigo: **um agente de
 * suporte responde "o evento saiu?" sem abrir console de ninguem**. Traduzido
 * em tela, sao quatro perguntas, e este composable existe para responder as
 * quatro sem que o componente precise saber de HTTP:
 *
 *   1. saiu?            -> a lista das ultimas entregas, com status por destino
 *   2. quanto sai?      -> a taxa de entrega
 *   3. quando nao sai, por que? -> os erros AGRUPADOS (o mesmo erro cem vezes
 *      e um problema, nao cem)
 *   4. esta bem casado? -> o EMQ, que e o numero que decide se a Meta consegue
 *      atribuir a conversao
 *
 * Tudo que vem do servidor passa por `sanitizeDeliveries` ANTES de virar
 * estado reativo. Nao existe caminho neste composable que devolva o corpo cru
 * da resposta: se existisse, um `v-for` distraido no componente desenharia
 * `error_message` com o e-mail do lead dentro, que e exatamente o vazamento
 * que o aceite de 5.14 procura.
 */
import { computed, ref } from 'vue';
import {
  fetchDeliveries,
  sendTestEvent,
  diagnosticsPath,
} from './trackingDiagnosticsApi';
import { sanitizeDelivery, sanitizeDeliveries } from './trackingRedaction';

/** A faixa que a Meta considera boa. Abaixo dela a atribuicao degrada. */
export const EMQ_HEALTHY = 8;

/** Status que contam como "chegou". `skipped` nao e falha nem entrega. */
const DELIVERED = ['sent'];
const FAILED = ['failed', 'dead'];

export function useTrackingDiagnostics(inboxId) {
  const deliveries = ref([]);
  const retentionDays = ref(0);
  const isLoading = ref(false);
  const isSendingTest = ref(false);
  /** Preenchido quando a rota ainda nao existe — a tela NOMEIA o que falta. */
  const missingEndpoint = ref('');
  const loadError = ref('');
  const testResult = ref(null);

  const carregar = async () => {
    isLoading.value = true;
    loadError.value = '';
    missingEndpoint.value = '';
    try {
      const { data } = await fetchDeliveries(inboxId);
      deliveries.value = sanitizeDeliveries(data?.deliveries);
      retentionDays.value = Number(data?.retention_days) || 0;
    } catch (error) {
      // 404 e 501 sao "a rota ainda nao subiu" — estado conhecido, nao falha do
      // administrador. Qualquer outro codigo e erro de verdade e aparece como tal.
      const status = error?.response?.status;
      if (status === 404 || status === 501) {
        missingEndpoint.value = diagnosticsPath(inboxId);
      } else {
        loadError.value = error?.message ?? '';
      }
      deliveries.value = [];
    } finally {
      isLoading.value = false;
    }
  };

  /**
   * O botao de teste (T4.7). O retorno TEM de ser visivel: o valor deste botao
   * e mostrar o status HTTP real do destino, nao um "enviado com sucesso" que
   * so prova que o nosso lado nao explodiu.
   */
  const enviarEventoDeTeste = async () => {
    isSendingTest.value = true;
    testResult.value = null;
    try {
      const { data } = await sendTestEvent(inboxId);
      const entrega = sanitizeDelivery(data?.delivery ?? {});
      testResult.value = entrega;
      deliveries.value = [entrega, ...deliveries.value];
      return entrega;
    } catch (error) {
      const status = error?.response?.status;
      if (status === 404 || status === 501) {
        missingEndpoint.value = diagnosticsPath(inboxId);
      }
      testResult.value = {
        status: 'failed',
        http_status: status ?? null,
        error_message: '',
        field_names: [],
      };
      return testResult.value;
    } finally {
      isSendingTest.value = false;
    }
  };

  const total = computed(() => deliveries.value.length);
  const entregues = computed(
    () => deliveries.value.filter(d => DELIVERED.includes(d.status)).length
  );
  const falhas = computed(
    () => deliveries.value.filter(d => FAILED.includes(d.status)).length
  );

  /**
   * Taxa sobre o que foi TENTADO — `pending` e `skipped` ficam de fora do
   * denominador. Contar tentativa que ainda nao aconteceu como falha faz a
   * taxa despencar toda vez que a fila enche, e o numero deixa de significar
   * qualquer coisa.
   */
  const deliveryRate = computed(() => {
    const tentadas = entregues.value + falhas.value;
    return tentadas ? Math.round((entregues.value / tentadas) * 100) : null;
  });

  /** O mesmo erro cem vezes e UM problema — agrupar e o que torna isso legivel. */
  const errorGroups = computed(() => {
    const grupos = new Map();
    deliveries.value
      .filter(d => FAILED.includes(d.status))
      .forEach(d => {
        const chave = d.error_code || d.error_message || String(d.http_status);
        const atual = grupos.get(chave) ?? {
          key: chave,
          count: 0,
          message: d.error_message,
          httpStatus: d.http_status,
        };
        atual.count += 1;
        grupos.set(chave, atual);
      });
    return [...grupos.values()].sort((a, b) => b.count - a.count);
  });

  /** Media dos que TEM EMQ: destino que nao devolve a metrica nao vira zero. */
  const emqAverage = computed(() => {
    const valores = deliveries.value
      .map(d => d.emq)
      .filter(valor => typeof valor === 'number' && !Number.isNaN(valor));
    if (!valores.length) return null;

    const soma = valores.reduce((acc, valor) => acc + valor, 0);
    return Math.round((soma / valores.length) * 10) / 10;
  });

  const emqIsHealthy = computed(
    () => emqAverage.value !== null && emqAverage.value >= EMQ_HEALTHY
  );

  return {
    deliveries,
    retentionDays,
    isLoading,
    isSendingTest,
    missingEndpoint,
    loadError,
    testResult,
    total,
    entregues,
    falhas,
    deliveryRate,
    errorGroups,
    emqAverage,
    emqIsHealthy,
    carregar,
    enviarEventoDeTeste,
  };
}
