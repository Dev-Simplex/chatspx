<script setup>
/**
 * Bloco 1.22 — de onde vieram os atendimentos.
 *
 * Duas regras desta tela existem para ela nao mentir:
 *   1. Conversa sem origem aparece como "origem nao disponivel", NUNCA como "origem direta".
 *      Nao sabemos que o acesso foi direto; sabemos que nao recebemos dado.
 *   2. O periodo anterior a entrada da medicao aparece rotulado como "antes da medicao", nunca
 *      vazio nem zerado — vazio e lido como "nao veio ninguem", e isso e mentira.
 */
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ReportsAPI from 'dashboard/api/reports';
import ReportHeader from './components/ReportHeader.vue';
import ReportFilters from './components/ReportFilters.vue';
import OriginDimensionTable from './components/OriginDimensionTable.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const { t } = useI18n();

const isLoading = ref(false);
const report = ref(null);
const hasError = ref(false);

const measurementStartedAt = computed(
  () => report.value?.measurement_started_at ?? null
);
const beforeMeasurementCount = computed(
  () => report.value?.before_measurement?.conversations_count ?? 0
);
const coversWholeRange = computed(
  () => report.value?.before_measurement?.covers_whole_range ?? false
);
const measuredCount = computed(
  () => report.value?.measured?.conversations_count ?? 0
);

const formattedStartDate = computed(() => {
  if (!measurementStartedAt.value) return '';
  return new Date(measurementStartedAt.value).toLocaleDateString();
});

const rowsFor = dimension => report.value?.measured?.[dimension] ?? [];

// `origin_kind` e a unica dimensao com vocabulario fechado: os valores vem do catalogo do 1.18 e
// tem rotulo proprio. As outras tres carregam o que o site do cliente escreveu, e ai o valor cru
// E o dado — traduzir seria reescrever a campanha dele.
// Chaves literais, uma a uma: chave dinamica escapa do rastreio do lint de i18n e vira string
// faltando em producao sem ninguem perceber.
const ORIGIN_KIND_LABELS = computed(() => ({
  busca_paga: t('ORIGIN_REPORTS.ORIGIN_KINDS.busca_paga'),
  busca_organica: t('ORIGIN_REPORTS.ORIGIN_KINDS.busca_organica'),
  social: t('ORIGIN_REPORTS.ORIGIN_KINDS.social'),
  ia_generativa: t('ORIGIN_REPORTS.ORIGIN_KINDS.ia_generativa'),
  email: t('ORIGIN_REPORTS.ORIGIN_KINDS.email'),
  referencia: t('ORIGIN_REPORTS.ORIGIN_KINDS.referencia'),
  nao_disponivel: t('ORIGIN_REPORTS.ORIGIN_KINDS.nao_disponivel'),
}));

const fetchReport = async ({ from, to }) => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await ReportsAPI.getConversationOrigin({ from, to });
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
    :header-title="$t('ORIGIN_REPORTS.HEADER')"
    :header-description="$t('ORIGIN_REPORTS.DESCRIPTION')"
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
    class="p-4 my-4 rounded-lg bg-n-ruby-2 text-n-ruby-11 text-body-main"
  >
    {{ $t('ORIGIN_REPORTS.ERROR') }}
  </div>

  <div v-else-if="report" class="flex flex-col gap-6 py-4">
    <!--
      Faixa "antes da medicao". Ela aparece SEMPRE que houve conversa antes do marco, inclusive
      quando o marco nao existe (conta nunca medida) — e nesse caso cobre o periodo inteiro.
      Mostrar zero ou nada nesse lugar seria dizer "nao veio ninguem".
    -->
    <div
      v-if="beforeMeasurementCount > 0"
      data-testid="before-measurement"
      class="flex flex-col gap-1 p-4 rounded-lg bg-n-amber-2 border border-n-amber-6"
    >
      <span class="text-body-main font-medium text-n-amber-12">
        {{ $t('ORIGIN_REPORTS.BEFORE_MEASUREMENT.TITLE') }}
      </span>
      <span class="text-body-small text-n-slate-12">
        {{
          coversWholeRange
            ? $t('ORIGIN_REPORTS.BEFORE_MEASUREMENT.WHOLE_RANGE', {
                count: beforeMeasurementCount,
              })
            : $t('ORIGIN_REPORTS.BEFORE_MEASUREMENT.PARTIAL', {
                count: beforeMeasurementCount,
                date: formattedStartDate,
              })
        }}
      </span>
    </div>

    <div
      v-if="measuredCount === 0 && !coversWholeRange"
      data-testid="no-measured-conversations"
      class="p-4 rounded-lg bg-n-slate-2 text-n-slate-11 text-body-main"
    >
      {{ $t('ORIGIN_REPORTS.EMPTY_MEASURED') }}
    </div>

    <template v-else-if="measuredCount > 0">
      <OriginDimensionTable
        testid="origin-source"
        :title="$t('ORIGIN_REPORTS.DIMENSIONS.SOURCE')"
        :rows="rowsFor('source')"
      />
      <OriginDimensionTable
        testid="origin-medium"
        :title="$t('ORIGIN_REPORTS.DIMENSIONS.MEDIUM')"
        :rows="rowsFor('medium')"
      />
      <OriginDimensionTable
        testid="origin-campaign"
        :title="$t('ORIGIN_REPORTS.DIMENSIONS.CAMPAIGN')"
        :rows="rowsFor('campaign')"
      />
      <OriginDimensionTable
        testid="origin-origin_kind"
        :title="$t('ORIGIN_REPORTS.DIMENSIONS.ORIGIN_KIND')"
        :rows="rowsFor('origin_kind')"
        :value-labels="ORIGIN_KIND_LABELS"
      />
    </template>
  </div>
</template>
