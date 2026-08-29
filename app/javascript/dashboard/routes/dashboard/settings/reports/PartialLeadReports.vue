<script setup>
/**
 * Bloco 4.18 — "quantos leads perdemos e onde".
 *
 * O serviço e o endpoint existiam desde o miolo e não tinham consumidor: o relatório só
 * respondia por console, como o do 4.15. Um relatório sem tela é uma consulta, não um
 * relatório — e a pergunta que este bloco existe para responder é do cliente, não do time de
 * infraestrutura.
 *
 * DUAS REGRAS PARA A TELA NÃO MENTIR:
 *
 *  1. **"Onde" é a ETAPA, não só o total.** Saber que 60% desistem não diz o que consertar;
 *     saber que 45% param no campo de CNPJ diz. Por isso a tabela por etapa é a peça
 *     principal, e não um apêndice do número grande.
 *  2. **Zero iniciados não é "ninguém desistiu".** Com denominador zero a tela diz que não
 *     houve ninguém no período, em vez de exibir 0% de abandono — que se lê como sucesso.
 *  3. **E "ninguém desistiu" não é "a captura está desligada".** É a mesma preocupação da
 *     regra 2 entrando pela outra porta: os dois estados chegam como zero, e mostrar o texto
 *     de período vazio para quem nunca ligou a chave faz o operador ler "não perdemos
 *     ninguém" onde a verdade é "não estamos medindo". Por isso o servidor manda
 *     `capture_enabled` junto das contagens, e a tela separa os dois casos. O contrário
 *     também vale: com a chave desligada DEPOIS de já ter coletado, os números históricos
 *     continuam à mostra — escondê-los apagaria medição verdadeira —, com o aviso de que
 *     eles não crescem mais.
 */
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ReportsAPI from 'dashboard/api/reports';
import ReportHeader from './components/ReportHeader.vue';
import ReportFilters from './components/ReportFilters.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const { t } = useI18n();

const isLoading = ref(false);
const report = ref(null);
const hasError = ref(false);

const started = computed(() => report.value?.started ?? 0);
const completed = computed(() => report.value?.completed ?? 0);
const abandoned = computed(() => report.value?.abandoned ?? 0);

const completionRate = computed(
  () => Math.round((report.value?.completion_rate ?? 0) * 1000) / 10
);
const abandonRate = computed(
  () => Math.round((100 - completionRate.value) * 10) / 10
);

// Ausente é LIGADA de propósito: a chave nasceu depois do endpoint, e pintar "desligada"
// diante de um payload que não a traz acusaria de desligado quem está medindo.
const captureEnabled = computed(() => report.value?.capture_enabled !== false);

/**
 * As linhas do "onde". `by_step_name` traz o NOME do campo em que a pessoa parou e
 * `by_step` traz o número da etapa — o nome é o que o administrador reconhece, e o número é o
 * que sobra quando o pré-chat não mandou nome nenhum. A tela mostra os dois na mesma linha em
 * vez de escolher: escolher só o número devolveria "etapa 3" para quem quer saber "telefone".
 */
const steps = computed(() => {
  const byStep = report.value?.by_step ?? {};
  const byName = report.value?.by_step_name ?? {};
  const nomes = Object.entries(byName).map(([name, count]) => ({
    key: `name-${name}`,
    label: name,
    count,
  }));
  // Sem nenhum nome gravado (pré-chat antigo, ou fluxo que não nomeia o campo) a tela cai no
  // número da etapa, que é sempre gravado. Nunca some — sumir viraria "ninguém parou aqui".
  if (nomes.length) return nomes.sort((a, b) => b.count - a.count);

  return Object.entries(byStep)
    .map(([step, count]) => ({
      key: `step-${step}`,
      label: t('PARTIAL_LEAD_REPORTS.STEP_NUMBER', { step }),
      count,
    }))
    .sort((a, b) => b.count - a.count);
});

const shareLabel = count =>
  `${abandoned.value ? Math.round((count / abandoned.value) * 1000) / 10 : 0}%`;

const fetchReport = async ({ from, to }) => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await ReportsAPI.getPartialLeads({ from, to });
    report.value = data;
  } catch {
    hasError.value = true;
    report.value = null;
  } finally {
    isLoading.value = false;
  }
};
</script>

<template>
  <ReportHeader
    :header-title="$t('PARTIAL_LEAD_REPORTS.HEADER')"
    :header-description="$t('PARTIAL_LEAD_REPORTS.DESCRIPTION')"
  />

  <ReportFilters
    :show-group-by="false"
    :show-business-hours="false"
    :show-entity-filter="false"
    @filter-change="fetchReport"
  />

  <div v-if="isLoading" class="flex justify-center py-10">
    <Spinner />
  </div>

  <div
    v-else-if="hasError"
    data-testid="partial-lead-error"
    class="p-4 my-4 rounded-lg bg-n-ruby-2 text-n-ruby-11 text-body-main"
  >
    {{ $t('PARTIAL_LEAD_REPORTS.ERROR') }}
  </div>

  <div v-else-if="report" class="flex flex-col gap-6 py-4">
    <div
      v-if="!captureEnabled"
      data-testid="partial-lead-capture-off"
      class="p-4 rounded-lg bg-n-amber-2 text-n-amber-12 text-body-main"
    >
      {{
        started > 0
          ? $t('PARTIAL_LEAD_REPORTS.CAPTURE_OFF_HISTORY')
          : $t('PARTIAL_LEAD_REPORTS.CAPTURE_OFF')
      }}
    </div>

    <div
      v-else-if="started === 0"
      data-testid="partial-lead-empty"
      class="p-4 rounded-lg bg-n-slate-2 text-n-slate-11 text-body-main"
    >
      {{ $t('PARTIAL_LEAD_REPORTS.EMPTY') }}
    </div>

    <template v-if="started > 0">
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div
          data-testid="partial-lead-started"
          class="flex flex-col gap-1 p-4 rounded-lg bg-n-slate-2"
        >
          <span class="text-body-small text-n-slate-11">
            {{ $t('PARTIAL_LEAD_REPORTS.STARTED') }}
          </span>
          <span class="text-heading-2 text-n-slate-12 tabular-nums">
            {{ started }}
          </span>
        </div>
        <div
          data-testid="partial-lead-completed"
          class="flex flex-col gap-1 p-4 rounded-lg bg-n-slate-2"
        >
          <span class="text-body-small text-n-slate-11">
            {{ $t('PARTIAL_LEAD_REPORTS.COMPLETED') }}
          </span>
          <span class="text-heading-2 text-n-slate-12 tabular-nums">
            {{ completed }}
            <small class="text-body-small text-n-slate-11">
              {{ $t('PARTIAL_LEAD_REPORTS.RATE', { rate: completionRate }) }}
            </small>
          </span>
        </div>
        <div
          data-testid="partial-lead-abandoned"
          class="flex flex-col gap-1 p-4 rounded-lg bg-n-amber-2"
        >
          <span class="text-body-small text-n-slate-11">
            {{ $t('PARTIAL_LEAD_REPORTS.ABANDONED') }}
          </span>
          <span class="text-heading-2 text-n-amber-12 tabular-nums">
            {{ abandoned }}
            <small class="text-body-small text-n-slate-11">
              {{ $t('PARTIAL_LEAD_REPORTS.RATE', { rate: abandonRate }) }}
            </small>
          </span>
        </div>
      </div>

      <section data-testid="partial-lead-steps" class="flex flex-col gap-2">
        <h3 class="text-heading-3 text-n-slate-12">
          {{ $t('PARTIAL_LEAD_REPORTS.WHERE') }}
        </h3>
        <table v-if="steps.length" class="w-full text-body-main">
          <thead>
            <tr class="text-left text-n-slate-12">
              <th class="py-2 font-medium">
                {{ $t('PARTIAL_LEAD_REPORTS.TABLE.STEP') }}
              </th>
              <th class="py-2 font-medium text-right">
                {{ $t('PARTIAL_LEAD_REPORTS.TABLE.LEADS') }}
              </th>
              <th class="py-2 font-medium text-right">
                {{ $t('PARTIAL_LEAD_REPORTS.TABLE.SHARE') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in steps"
              :key="row.key"
              class="border-t border-n-weak"
            >
              <td class="py-2 text-n-slate-12">{{ row.label }}</td>
              <td class="py-2 text-right tabular-nums">{{ row.count }}</td>
              <td class="py-2 text-right tabular-nums text-n-slate-12">
                {{ shareLabel(row.count) }}
              </td>
            </tr>
          </tbody>
        </table>
        <p v-else class="text-body-main text-n-slate-11">
          {{ $t('PARTIAL_LEAD_REPORTS.NO_ABANDONED') }}
        </p>
      </section>
    </template>
  </div>
</template>
