<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';

import EvalAPI from 'dashboard/api/captain/eval';
import AiButton from 'dashboard/components-next/agents-ui/AiButton.vue';
import AiEmptyState from 'dashboard/components-next/agents-ui/AiEmptyState.vue';
import AiSelect from 'dashboard/components-next/agents-ui/AiSelect.vue';

/**
 * Eval como produto (bloco 6.02).
 *
 * O que o cliente faz aqui, na ordem em que ele faz:
 *   1. escreve os CASOS (o que o visitante diz, o que a IA tem de fazer);
 *   2. vê o CUSTO antes de rodar — o número aparece sem disparar nada;
 *   3. roda o conjunto e vê o veredito por caso;
 *   4. compara duas execuções e vê QUANTOS CASOS REGREDIRAM.
 *
 * Nenhum controle desta tela nasce mudo: todo botão sem texto visível carrega
 * `aria-label`, e o rótulo é texto limpo — símbolo só no visual. É a mesma regra
 * dos primitivos do widget (2.01), aplicada aqui na mão porque `AiButton` não a
 * cobra por prop.
 */
const { t } = useI18n();
const route = useRoute();

const assistantId = computed(() => Number(route.params.assistantId));

const cases = ref([]);
const runs = ref([]);
const estimate = ref(null);
const detail = ref(null);
const comparison = ref(null);
const isLoading = ref(false);
const errorMessage = ref('');

const baseRunId = ref('');
const comparedRunId = ref('');

const emptyCase = () => ({
  titulo: '',
  pergunta: '',
  contem: '',
  naoContem: '',
});
const form = ref(emptyCase());
const isFormOpen = ref(false);

const runOptions = computed(() =>
  runs.value.map(run => ({
    value: String(run.id),
    label: t('CAPTAIN.AGENT_TABS.EVAL.RUN_OPTION', {
      id: run.id,
      aprovacao: run.aprovacao === null ? '—' : run.aprovacao,
    }),
  }))
);

// Chaves LITERAIS, uma por situação: chave de i18n montada em runtime não é
// rastreável — nem pelo lint, nem por quem procura a string no repositório.
const situationLabel = situacao => {
  if (situacao === 'regrediu')
    return t('CAPTAIN.AGENT_TABS.EVAL.SITUATION.REGREDIU');
  if (situacao === 'corrigiu')
    return t('CAPTAIN.AGENT_TABS.EVAL.SITUATION.CORRIGIU');
  if (situacao === 'segue_passando')
    return t('CAPTAIN.AGENT_TABS.EVAL.SITUATION.SEGUE_PASSANDO');
  if (situacao === 'segue_falhando')
    return t('CAPTAIN.AGENT_TABS.EVAL.SITUATION.SEGUE_FALHANDO');
  return t('CAPTAIN.AGENT_TABS.EVAL.SITUATION.SO_EM_UMA');
};

const canCompare = computed(
  () =>
    baseRunId.value &&
    comparedRunId.value &&
    baseRunId.value !== comparedRunId.value
);

function splitList(value) {
  return value
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean);
}

async function fetchAll() {
  isLoading.value = true;
  errorMessage.value = '';
  try {
    const [casesResponse, runsResponse, estimateResponse] = await Promise.all([
      EvalAPI.getCases(assistantId.value),
      EvalAPI.getRuns(assistantId.value),
      EvalAPI.estimate(assistantId.value),
    ]);
    cases.value = casesResponse.data.data;
    runs.value = runsResponse.data.data;
    estimate.value = estimateResponse.data.data;
  } catch (error) {
    errorMessage.value = t('CAPTAIN.AGENT_TABS.EVAL.LOAD_ERROR');
  } finally {
    isLoading.value = false;
  }
}

async function saveCase() {
  errorMessage.value = '';
  try {
    await EvalAPI.createCase(assistantId.value, {
      titulo: form.value.titulo,
      mensagens: [{ role: 'user', content: form.value.pergunta }],
      expectativas: {
        contem: splitList(form.value.contem),
        nao_contem: splitList(form.value.naoContem),
      },
    });
    form.value = emptyCase();
    isFormOpen.value = false;
    await fetchAll();
  } catch (error) {
    errorMessage.value =
      error?.response?.data?.message || t('CAPTAIN.AGENT_TABS.EVAL.SAVE_ERROR');
  }
}

async function removeCase(evalCase) {
  await EvalAPI.deleteCase(assistantId.value, evalCase.id);
  await fetchAll();
}

async function runSet() {
  errorMessage.value = '';
  try {
    const { data } = await EvalAPI.run(assistantId.value);
    runs.value = [data.data, ...runs.value];
  } catch (error) {
    errorMessage.value = t('CAPTAIN.AGENT_TABS.EVAL.RUN_ERROR');
  }
}

async function openRun(run) {
  const { data } = await EvalAPI.getRun(assistantId.value, run.id);
  detail.value = data.data;
}

async function compareRuns() {
  const { data } = await EvalAPI.compare(
    assistantId.value,
    baseRunId.value,
    comparedRunId.value
  );
  comparison.value = data.data;
}

onMounted(fetchAll);
</script>

<template>
  <div class="px-6 pt-4 pb-10 mx-auto max-w-3xl">
    <h3 class="text-[15px] font-bold text-n-slate-12">
      {{ t('CAPTAIN.AGENT_TABS.EVAL.TITLE') }}
    </h3>
    <p class="mt-1 mb-4 text-sm text-n-slate-11">
      {{ t('CAPTAIN.AGENT_TABS.EVAL.SUBTITLE') }}
    </p>

    <p v-if="errorMessage" class="mb-4 text-sm text-r-500" role="alert">
      {{ errorMessage }}
    </p>

    <!-- O custo ANTES de rodar. Fica ao lado do botão de propósito: o número tem
         de estar à vista no momento da decisão, não numa tela de confirmação. -->
    <section
      class="flex flex-wrap gap-4 justify-between items-center p-4 mb-6 rounded-2xl border border-n-weak bg-n-solid-1"
    >
      <div>
        <p class="text-sm font-semibold text-n-slate-12">
          {{ t('CAPTAIN.AGENT_TABS.EVAL.COST_TITLE') }}
        </p>
        <p
          v-if="estimate"
          class="text-sm text-n-slate-11"
          data-testid="eval-cost"
        >
          {{
            t('CAPTAIN.AGENT_TABS.EVAL.COST_LINE', {
              casos: estimate.casos,
              respostas: estimate.respostas,
              tokens: estimate.tokens_estimados,
            })
          }}
        </p>
        <p v-if="estimate" class="text-xs text-n-slate-10">
          {{ estimate.base_da_estimativa }}
        </p>
        <p
          v-if="estimate && estimate.excede_saldo"
          class="text-xs font-semibold text-r-500"
          data-testid="eval-cost-warning"
        >
          {{
            t('CAPTAIN.AGENT_TABS.EVAL.COST_OVER_BALANCE', {
              disponivel: estimate.saldo.disponivel,
            })
          }}
        </p>
      </div>
      <AiButton
        :disabled="!cases.length"
        :aria-label="t('CAPTAIN.AGENT_TABS.EVAL.RUN_ARIA')"
        data-testid="eval-run"
        @click="runSet"
      >
        {{ t('CAPTAIN.AGENT_TABS.EVAL.RUN') }}
      </AiButton>
    </section>

    <!-- Casos -->
    <section class="mb-8">
      <div class="flex justify-between items-center mb-3">
        <h4 class="text-sm font-bold text-n-slate-12">
          {{ t('CAPTAIN.AGENT_TABS.EVAL.CASES') }}
        </h4>
        <AiButton
          variant="ghost"
          :aria-label="t('CAPTAIN.AGENT_TABS.EVAL.NEW_CASE_ARIA')"
          data-testid="eval-new-case"
          @click="isFormOpen = !isFormOpen"
        >
          {{ t('CAPTAIN.AGENT_TABS.EVAL.NEW_CASE') }}
        </AiButton>
      </div>

      <form
        v-if="isFormOpen"
        class="p-4 mb-4 space-y-3 rounded-2xl border border-n-weak"
        @submit.prevent="saveCase"
      >
        <label class="block text-xs font-semibold text-n-slate-11">
          {{ t('CAPTAIN.AGENT_TABS.EVAL.FIELD_TITLE') }}
          <input
            v-model="form.titulo"
            class="reset-base w-full"
            type="text"
            required
          />
        </label>
        <label class="block text-xs font-semibold text-n-slate-11">
          {{ t('CAPTAIN.AGENT_TABS.EVAL.FIELD_QUESTION') }}
          <input
            v-model="form.pergunta"
            class="reset-base w-full"
            type="text"
            required
          />
        </label>
        <label class="block text-xs font-semibold text-n-slate-11">
          {{ t('CAPTAIN.AGENT_TABS.EVAL.FIELD_CONTAINS') }}
          <textarea v-model="form.contem" class="reset-base w-full" rows="2" />
        </label>
        <label class="block text-xs font-semibold text-n-slate-11">
          {{ t('CAPTAIN.AGENT_TABS.EVAL.FIELD_NOT_CONTAINS') }}
          <textarea
            v-model="form.naoContem"
            class="reset-base w-full"
            rows="2"
          />
        </label>
        <AiButton type="submit" data-testid="eval-save-case">
          {{ t('CAPTAIN.AGENT_TABS.EVAL.SAVE_CASE') }}
        </AiButton>
      </form>

      <AiEmptyState
        v-if="!cases.length && !isLoading"
        icon="i-lucide-list-checks"
        :title="t('CAPTAIN.AGENT_TABS.EVAL.NO_CASES')"
      />
      <ul v-else class="space-y-2">
        <li
          v-for="evalCase in cases"
          :key="evalCase.id"
          class="flex gap-3 justify-between items-start p-3 rounded-2xl border border-n-weak bg-n-solid-1"
        >
          <div>
            <p class="text-sm font-semibold text-n-slate-12">
              {{ evalCase.titulo }}
            </p>
            <p class="text-xs text-n-slate-11">
              {{ evalCase.mensagens.map(m => m.content).join(' · ') }}
            </p>
          </div>
          <button
            type="button"
            class="text-xs font-semibold text-r-500"
            :aria-label="
              t('CAPTAIN.AGENT_TABS.EVAL.DELETE_CASE_ARIA', {
                titulo: evalCase.titulo,
              })
            "
            @click="removeCase(evalCase)"
          >
            {{ t('CAPTAIN.AGENT_TABS.EVAL.DELETE_CASE') }}
          </button>
        </li>
      </ul>
    </section>

    <!-- Histórico -->
    <section class="mb-8">
      <h4 class="mb-3 text-sm font-bold text-n-slate-12">
        {{ t('CAPTAIN.AGENT_TABS.EVAL.HISTORY') }}
      </h4>
      <AiEmptyState
        v-if="!runs.length"
        icon="i-lucide-history"
        :title="t('CAPTAIN.AGENT_TABS.EVAL.NO_RUNS')"
      />
      <ul v-else class="space-y-2">
        <li
          v-for="run in runs"
          :key="run.id"
          class="flex gap-3 justify-between items-center p-3 rounded-2xl border border-n-weak bg-n-solid-1"
        >
          <div>
            <p class="text-sm font-semibold text-n-slate-12">
              {{
                t('CAPTAIN.AGENT_TABS.EVAL.RUN_LINE', {
                  ok: run.casos_ok,
                  total: run.casos_total,
                })
              }}
            </p>
            <p class="text-xs text-n-slate-11">
              {{ run.status }} ·
              {{ t('CAPTAIN.AGENT_TABS.EVAL.PROMPT_VERSION') }}
              {{ run.prompt_fingerprint || '—' }}
            </p>
          </div>
          <button
            type="button"
            class="text-xs font-semibold text-n-brand"
            :aria-label="
              t('CAPTAIN.AGENT_TABS.EVAL.OPEN_RUN_ARIA', { id: run.id })
            "
            @click="openRun(run)"
          >
            {{ t('CAPTAIN.AGENT_TABS.EVAL.OPEN_RUN') }}
          </button>
        </li>
      </ul>
    </section>

    <!-- Veredito por caso -->
    <section v-if="detail" class="mb-8" data-testid="eval-detail">
      <h4 class="mb-3 text-sm font-bold text-n-slate-12">
        {{ t('CAPTAIN.AGENT_TABS.EVAL.VERDICTS') }}
      </h4>
      <ul class="space-y-2">
        <li
          v-for="resultado in detail.resultados"
          :key="resultado.eval_case_id"
          class="p-3 rounded-2xl border border-n-weak bg-n-solid-1"
        >
          <p class="text-sm font-semibold text-n-slate-12">
            <span :class="resultado.passou ? 'text-g-500' : 'text-r-500'">
              {{
                resultado.passou
                  ? t('CAPTAIN.AGENT_TABS.EVAL.PASSED')
                  : t('CAPTAIN.AGENT_TABS.EVAL.FAILED')
              }}
            </span>
            — {{ resultado.titulo }}
          </p>
          <p class="text-xs text-n-slate-11">{{ resultado.resposta }}</p>
          <ul v-if="resultado.findings.length" class="mt-1 text-xs text-r-500">
            <li v-for="(finding, index) in resultado.findings" :key="index">
              {{ finding.porque }}
            </li>
          </ul>
        </li>
      </ul>
    </section>

    <!-- Comparação -->
    <section>
      <h4 class="mb-3 text-sm font-bold text-n-slate-12">
        {{ t('CAPTAIN.AGENT_TABS.EVAL.COMPARE') }}
      </h4>
      <div class="flex flex-wrap gap-3 items-end">
        <div class="w-52">
          <AiSelect
            v-model="baseRunId"
            :options="runOptions"
            :aria-label="t('CAPTAIN.AGENT_TABS.EVAL.COMPARE_BASE')"
          />
        </div>
        <div class="w-52">
          <AiSelect
            v-model="comparedRunId"
            :options="runOptions"
            :aria-label="t('CAPTAIN.AGENT_TABS.EVAL.COMPARE_TARGET')"
          />
        </div>
        <AiButton
          variant="ghost"
          :disabled="!canCompare"
          :aria-label="t('CAPTAIN.AGENT_TABS.EVAL.COMPARE_ARIA')"
          data-testid="eval-compare"
          @click="compareRuns"
        >
          {{ t('CAPTAIN.AGENT_TABS.EVAL.COMPARE_ACTION') }}
        </AiButton>
      </div>

      <div v-if="comparison" class="mt-4" data-testid="eval-comparison">
        <p class="text-sm font-semibold text-n-slate-12">
          {{
            t('CAPTAIN.AGENT_TABS.EVAL.REGRESSED', {
              count: comparison.regrediram.length,
            })
          }}
        </p>
        <p v-if="!comparison.mesmo_prompt" class="text-xs text-n-slate-11">
          {{ t('CAPTAIN.AGENT_TABS.EVAL.DIFFERENT_PROMPT') }}
        </p>
        <p v-else class="text-xs text-n-slate-11">
          {{ t('CAPTAIN.AGENT_TABS.EVAL.SAME_PROMPT') }}
        </p>
        <ul class="mt-2 space-y-1">
          <li
            v-for="linha in comparison.casos"
            :key="linha.eval_case_id"
            class="text-xs text-n-slate-11"
          >
            {{ linha.titulo }} —
            {{ situationLabel(linha.situacao) }}
          </li>
        </ul>
      </div>
    </section>
  </div>
</template>
