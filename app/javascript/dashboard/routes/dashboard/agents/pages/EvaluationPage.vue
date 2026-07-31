<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import EvalDashboardAPI from 'dashboard/api/captain/evalDashboard';
import AiStatCard from 'dashboard/components-next/agents-ui/AiStatCard.vue';

defineOptions({ name: 'EvaluationPage' });

const { t, te } = useI18n();
const router = useRouter();
const { accountId } = useAccount();

const loading = ref(true);
const loadError = ref(false);
const data = ref(null);

// drill-down por indicador (F4.1): clicar numa barra/KPI filtra a lista de episódios
const activeFilter = ref(null); // { params, chave }
const filteredRows = ref(null);
const filterLoading = ref(false);

onMounted(async () => {
  try {
    const { data: payload } = await EvalDashboardAPI.show();
    data.value = payload;
  } catch (e) {
    loadError.value = true;
  } finally {
    loading.value = false;
  }
});

const applyFilter = async (params, chave) => {
  activeFilter.value = { params, chave };
  filterLoading.value = true;
  try {
    const { data: payload } = await EvalDashboardAPI.episodes(params);
    filteredRows.value = payload.rows || [];
  } catch (e) {
    filteredRows.value = [];
  } finally {
    filterLoading.value = false;
  }
};

const clearFilter = () => {
  activeFilter.value = null;
  filteredRows.value = null;
};

const displayRows = computed(() =>
  activeFilter.value ? filteredRows.value || [] : data.value?.recentes || []
);
const hasEvidence = computed(() =>
  displayRows.value.some(r => r.findings_matched && r.findings_matched.length)
);

const totals = computed(() => data.value?.totals || {});
const nota = computed(() => data.value?.nota || {});
const findings = computed(() => data.value?.findings || {});

const label = key => {
  const i18nKey = `AGENTS_EVALUATION.LABELS.${String(key).toUpperCase()}`;
  return te(i18nKey) ? t(i18nKey) : String(key).replaceAll('_', ' ');
};

// objeto {chave: contagem} -> linhas ordenadas com % relativa ao maior valor
const toBars = obj => {
  const entries = Object.entries(obj || {}).sort((a, b) => b[1] - a[1]);
  const max = entries.length ? entries[0][1] : 0;
  return entries.map(([key, count]) => ({
    key,
    count,
    pct: max ? Math.max(2, Math.round((count / max) * 100)) : 0,
  }));
};

const NOTA_ORDER = ['9-10', '7-8', '5-6', '0-4'];
const notaBars = computed(() => {
  const dist = nota.value.dist || {};
  const max = Math.max(1, ...Object.values(dist));
  return NOTA_ORDER.map(key => ({
    key,
    count: dist[key] || 0,
    pct: Math.max(2, Math.round(((dist[key] || 0) / max) * 100)),
  }));
});
const notaBarClass = key => {
  if (key === '9-10') return 'bg-n-teal-9';
  if (key === '7-8') return 'bg-n-blue-9';
  if (key === '5-6') return 'bg-n-amber-9';
  return 'bg-n-ruby-9';
};

const funilBars = computed(() => toBars(data.value?.funil));
const handoffBars = computed(() => toBars(data.value?.handoff));
const fronteiraBars = computed(() => toBars(data.value?.fronteiras));
// cada categoria carrega o split IA x Humano (mesmas cores da barra-resumo acima)
const findingBars = computed(() => {
  const top = findings.value.top || [];
  const max = top.length ? Math.max(...top.map(f => f.count || 0)) : 0;
  return top.map(f => {
    const count = f.count || 0;
    const pctIa = count ? Math.round(((f.ia || 0) / count) * 100) : 0;
    return {
      key: f.categoria,
      count,
      ia: f.ia || 0,
      humano: f.humano || 0,
      pct: max ? Math.max(2, Math.round((count / max) * 100)) : 0,
      pctIa,
      pctHumano: 100 - pctIa,
    };
  });
});

const iaHumanoPct = computed(() => {
  const ia = findings.value.ia || 0;
  const humano = findings.value.humano || 0;
  const total = ia + humano;
  if (!total) return { ia: 50, humano: 50, total };
  return {
    ia: Math.round((ia / total) * 100),
    humano: 100 - Math.round((ia / total) * 100),
    total,
  };
});

const notaClass = value => {
  if (value === null || value === undefined) return 'bg-n-slate-7';
  if (value >= 9) return 'bg-n-teal-9';
  if (value >= 7) return 'bg-n-blue-9';
  if (value >= 5) return 'bg-n-amber-9';
  return 'bg-n-ruby-9';
};

const openConversation = displayId => {
  if (!displayId) return;
  router.push(`/app/accounts/${accountId.value}/conversations/${displayId}`);
};
</script>

<template>
  <div class="p-6 mx-auto max-w-6xl">
    <div class="flex flex-wrap gap-3 justify-between items-end mb-5">
      <div>
        <h1 class="text-xl font-bold text-n-slate-12">
          {{ t('AGENTS_EVALUATION.TITLE') }}
        </h1>
        <p class="mt-0.5 text-sm text-n-slate-11">
          {{ t('AGENTS_EVALUATION.SUBTITLE') }}
        </p>
      </div>
      <span
        v-if="data"
        class="px-2.5 py-1 text-xs font-semibold rounded-full border border-n-weak bg-n-solid-2 text-n-slate-11"
      >
        {{
          data.unit === 'episode'
            ? t('AGENTS_EVALUATION.UNIT_EPISODE')
            : t('AGENTS_EVALUATION.UNIT_CONVERSATION')
        }}
      </span>
    </div>

    <div v-if="loading" class="py-16 text-sm text-center text-n-slate-10">
      {{ t('AGENTS_EVALUATION.LOADING') }}
    </div>
    <div
      v-else-if="loadError || !data"
      class="py-16 text-sm text-center text-n-slate-10"
    >
      {{ t('AGENTS_EVALUATION.ERROR') }}
    </div>
    <div v-else-if="!totals.julgados" class="py-16 text-center">
      <p class="text-sm text-n-slate-11">
        {{ t('AGENTS_EVALUATION.EMPTY') }}
      </p>
    </div>

    <template v-else>
      <!-- KPIs -->
      <div class="grid grid-cols-2 gap-3 lg:grid-cols-5 md:grid-cols-3">
        <AiStatCard
          :value="Number(nota.media) || 0"
          :label="t('AGENTS_EVALUATION.KPI_NOTA')"
          icon="i-lucide-gauge"
          tint="#1faa59"
        />
        <AiStatCard
          :value="totals.em_escopo || 0"
          :label="t('AGENTS_EVALUATION.KPI_JULGADOS')"
          icon="i-lucide-scale"
          tint="#2563eb"
        />
        <AiStatCard
          :value="totals.episodios || 0"
          :label="t('AGENTS_EVALUATION.KPI_EPISODIOS')"
          icon="i-lucide-list-video"
          tint="#7c5cd6"
        />
        <AiStatCard
          :value="totals.conversas || 0"
          :label="t('AGENTS_EVALUATION.KPI_CONVERSAS')"
          icon="i-lucide-messages-square"
          tint="#0e9aa7"
        />
        <div
          class="cursor-pointer"
          role="button"
          tabindex="0"
          @click="
            applyFilter({ escopo: 'ruido' }, t('AGENTS_EVALUATION.KPI_RUIDO'))
          "
          @keydown.enter="
            applyFilter({ escopo: 'ruido' }, t('AGENTS_EVALUATION.KPI_RUIDO'))
          "
        >
          <AiStatCard
            :value="totals.fora_de_escopo || 0"
            :label="t('AGENTS_EVALUATION.KPI_RUIDO')"
            icon="i-lucide-filter-x"
            tint="#c2831f"
          />
        </div>
      </div>

      <!-- Distribuições -->
      <div class="grid grid-cols-1 gap-3 mt-3 md:grid-cols-2">
        <div class="p-4 rounded-2xl border border-n-weak bg-n-solid-1/70">
          <h2
            class="mb-3 text-xs font-bold tracking-wide uppercase text-n-slate-11"
          >
            {{ t('AGENTS_EVALUATION.SECTION_NOTA') }}
          </h2>
          <div class="space-y-2.5">
            <div
              v-for="bar in notaBars"
              :key="bar.key"
              class="grid grid-cols-[70px_1fr_40px] gap-3 items-center rounded-md cursor-pointer hover:bg-n-alpha-1"
              role="button"
              tabindex="0"
              @click="applyFilter({ nota_faixa: bar.key }, bar.key)"
              @keydown.enter="applyFilter({ nota_faixa: bar.key }, bar.key)"
            >
              <span class="text-[12.5px] text-n-slate-11">{{ bar.key }}</span>
              <div class="overflow-hidden h-2 rounded-full bg-n-alpha-1">
                <div
                  class="h-full rounded-full"
                  :class="notaBarClass(bar.key)"
                  :style="{ width: `${bar.pct}%` }"
                />
              </div>
              <span
                class="text-[12.5px] font-semibold text-right text-n-slate-12"
              >
                {{ bar.count }}
              </span>
            </div>
          </div>
        </div>

        <div class="p-4 rounded-2xl border border-n-weak bg-n-solid-1/70">
          <h2
            class="mb-3 text-xs font-bold tracking-wide uppercase text-n-slate-11"
          >
            {{ t('AGENTS_EVALUATION.SECTION_FUNIL') }}
          </h2>
          <div class="space-y-2.5">
            <div
              v-for="bar in funilBars"
              :key="bar.key"
              class="grid grid-cols-[110px_1fr_40px] gap-3 items-center rounded-md cursor-pointer hover:bg-n-alpha-1"
              role="button"
              tabindex="0"
              @click="applyFilter({ funil: bar.key }, label(bar.key))"
              @keydown.enter="applyFilter({ funil: bar.key }, label(bar.key))"
            >
              <span class="text-[12.5px] truncate text-n-slate-11">
                {{ label(bar.key) }}
              </span>
              <div class="overflow-hidden h-2 rounded-full bg-n-alpha-1">
                <div
                  class="h-full rounded-full bg-n-brand"
                  :style="{ width: `${bar.pct}%` }"
                />
              </div>
              <span
                class="text-[12.5px] font-semibold text-right text-n-slate-12"
              >
                {{ bar.count }}
              </span>
            </div>
          </div>
        </div>

        <div class="p-4 rounded-2xl border border-n-weak bg-n-solid-1/70">
          <h2
            class="mb-3 text-xs font-bold tracking-wide uppercase text-n-slate-11"
          >
            {{ t('AGENTS_EVALUATION.SECTION_HANDOFF') }}
          </h2>
          <div class="space-y-2.5">
            <div
              v-for="bar in handoffBars"
              :key="bar.key"
              class="grid grid-cols-[130px_1fr_40px] gap-3 items-center rounded-md cursor-pointer hover:bg-n-alpha-1"
              role="button"
              tabindex="0"
              @click="applyFilter({ handoff_timing: bar.key }, label(bar.key))"
              @keydown.enter="
                applyFilter({ handoff_timing: bar.key }, label(bar.key))
              "
            >
              <span class="text-[12.5px] truncate text-n-slate-11">
                {{ label(bar.key) }}
              </span>
              <div class="overflow-hidden h-2 rounded-full bg-n-alpha-1">
                <div
                  class="h-full rounded-full"
                  :class="
                    bar.key === 'tardio' || bar.key === 'precisava_nao_fez'
                      ? 'bg-n-ruby-9'
                      : 'bg-n-teal-9'
                  "
                  :style="{ width: `${bar.pct}%` }"
                />
              </div>
              <span
                class="text-[12.5px] font-semibold text-right text-n-slate-12"
              >
                {{ bar.count }}
              </span>
            </div>
          </div>
        </div>

        <div class="p-4 rounded-2xl border border-n-weak bg-n-solid-1/70">
          <h2
            class="mb-3 text-xs font-bold tracking-wide uppercase text-n-slate-11"
          >
            {{ t('AGENTS_EVALUATION.SECTION_FRONTEIRAS') }}
          </h2>
          <div class="space-y-2.5">
            <div
              v-for="bar in fronteiraBars"
              :key="bar.key"
              class="grid grid-cols-[130px_1fr_40px] gap-3 items-center"
            >
              <span class="text-[12.5px] truncate text-n-slate-11">
                {{ label(bar.key) }}
              </span>
              <div class="overflow-hidden h-2 rounded-full bg-n-alpha-1">
                <div
                  class="h-full rounded-full bg-n-brand"
                  :style="{ width: `${bar.pct}%` }"
                />
              </div>
              <span
                class="text-[12.5px] font-semibold text-right text-n-slate-12"
              >
                {{ bar.count }}
              </span>
            </div>
          </div>
        </div>
      </div>

      <!-- Falhas IA x Humano -->
      <div class="p-4 mt-3 rounded-2xl border border-n-weak bg-n-solid-1/70">
        <h2
          class="mb-1 text-xs font-bold tracking-wide uppercase text-n-slate-11"
        >
          {{ t('AGENTS_EVALUATION.SECTION_FALHAS') }}
        </h2>
        <p class="mb-3 text-[12px] text-n-slate-10">
          {{
            t('AGENTS_EVALUATION.FALHAS_HINT', {
              ia: findings.ia || 0,
              humano: findings.humano || 0,
              gate: findings.gate || 0,
            })
          }}
        </p>
        <div
          v-if="iaHumanoPct.total"
          class="flex overflow-hidden mb-4 h-7 text-[11.5px] font-semibold text-white rounded-lg"
        >
          <div
            class="flex justify-center items-center cursor-pointer bg-n-blue-9 hover:opacity-90"
            role="button"
            tabindex="0"
            :style="{ width: `${iaHumanoPct.ia}%` }"
            @click="applyFilter({ quem: 'ia' }, 'IA')"
            @keydown.enter="applyFilter({ quem: 'ia' }, 'IA')"
          >
            {{ t('AGENTS_EVALUATION.IA') }} · {{ findings.ia }}
          </div>
          <div
            class="flex justify-center items-center cursor-pointer bg-n-ruby-9 hover:opacity-90"
            :style="{ width: `${iaHumanoPct.humano}%` }"
            role="button"
            tabindex="0"
            @click="
              applyFilter({ quem: 'humano' }, t('AGENTS_EVALUATION.HUMANO'))
            "
            @keydown.enter="
              applyFilter({ quem: 'humano' }, t('AGENTS_EVALUATION.HUMANO'))
            "
          >
            {{ t('AGENTS_EVALUATION.HUMANO') }} · {{ findings.humano }}
          </div>
        </div>
        <div class="space-y-2.5">
          <div
            v-for="bar in findingBars"
            :key="bar.key"
            class="grid grid-cols-[180px_1fr_40px] gap-3 items-center rounded-md cursor-pointer hover:bg-n-alpha-1"
            role="button"
            tabindex="0"
            @click="applyFilter({ categoria: bar.key }, label(bar.key))"
            @keydown.enter="applyFilter({ categoria: bar.key }, label(bar.key))"
          >
            <span class="text-[12.5px] truncate text-n-slate-11">
              {{ label(bar.key) }}
            </span>
            <div class="overflow-hidden h-2 rounded-full bg-n-alpha-1">
              <div
                class="flex overflow-hidden h-full rounded-full"
                :style="{ width: `${bar.pct}%` }"
              >
                <div
                  v-if="bar.ia"
                  class="h-full bg-n-blue-9 hover:opacity-80"
                  :style="{ width: `${bar.pctIa}%` }"
                  :title="`${t('AGENTS_EVALUATION.IA')} · ${bar.ia}`"
                  @click.stop="
                    applyFilter(
                      { categoria: bar.key, quem: 'ia' },
                      `${label(bar.key)} — ${t('AGENTS_EVALUATION.IA')}`
                    )
                  "
                />
                <div
                  v-if="bar.humano"
                  class="h-full bg-n-ruby-9 hover:opacity-80"
                  :style="{ width: `${bar.pctHumano}%` }"
                  :title="`${t('AGENTS_EVALUATION.HUMANO')} · ${bar.humano}`"
                  @click.stop="
                    applyFilter(
                      { categoria: bar.key, quem: 'humano' },
                      `${label(bar.key)} — ${t('AGENTS_EVALUATION.HUMANO')}`
                    )
                  "
                />
              </div>
            </div>
            <span
              class="text-[12.5px] font-semibold text-right text-n-slate-12"
            >
              {{ bar.count }}
            </span>
          </div>
        </div>
      </div>

      <!-- Últimos julgamentos / resultado do filtro -->
      <div class="p-4 mt-3 rounded-2xl border border-n-weak bg-n-solid-1/70">
        <div class="flex flex-wrap gap-2 items-center mb-3">
          <h2 class="text-xs font-bold tracking-wide uppercase text-n-slate-11">
            {{
              activeFilter
                ? t('AGENTS_EVALUATION.SECTION_FILTRADOS')
                : t('AGENTS_EVALUATION.SECTION_RECENTES')
            }}
          </h2>
          <button
            v-if="activeFilter"
            type="button"
            class="inline-flex gap-1.5 items-center px-2.5 py-1 text-xs font-semibold rounded-full border border-n-brand/40 bg-n-brand/10 text-n-brand hover:bg-n-brand/20"
            @click="clearFilter"
          >
            {{ activeFilter.chave }}
            <span class="i-lucide-x size-3.5" />
          </button>
        </div>
        <div
          v-if="filterLoading"
          class="py-10 text-sm text-center text-n-slate-10"
        >
          {{ t('AGENTS_EVALUATION.LOADING') }}
        </div>
        <div
          v-else-if="activeFilter && !displayRows.length"
          class="py-10 text-sm text-center text-n-slate-10"
        >
          {{ t('AGENTS_EVALUATION.EMPTY_FILTER') }}
        </div>
        <div v-else class="overflow-x-auto">
          <table class="w-full min-w-[720px] text-[12.5px]">
            <thead>
              <tr class="text-left border-b border-n-weak text-n-slate-10">
                <th class="py-2 pr-3 font-semibold">
                  {{ t('AGENTS_EVALUATION.COL_CONVERSA') }}
                </th>
                <th class="py-2 pr-3 font-semibold">
                  {{ t('AGENTS_EVALUATION.COL_EPISODIO') }}
                </th>
                <th class="py-2 pr-3 font-semibold">
                  {{ t('AGENTS_EVALUATION.COL_NOTA') }}
                </th>
                <th class="py-2 pr-3 font-semibold">
                  {{ t('AGENTS_EVALUATION.COL_FUNIL') }}
                </th>
                <th class="py-2 pr-3 font-semibold">
                  {{
                    hasEvidence
                      ? t('AGENTS_EVALUATION.COL_EVIDENCIA')
                      : t('AGENTS_EVALUATION.COL_RESUMO')
                  }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(row, index) in displayRows"
                :key="index"
                class="border-b cursor-pointer border-n-weak/60 hover:bg-n-alpha-1"
                @click="openConversation(row.conversation_display_id)"
              >
                <td
                  class="py-2 pr-3 font-semibold whitespace-nowrap text-n-brand"
                >
                  #{{ row.conversation_display_id }}
                </td>
                <td class="py-2 pr-3 whitespace-nowrap text-n-slate-11">
                  <template v-if="row.episode_seq">
                    {{ row.episode_seq }}/{{ row.episode_total }} ·
                    {{ label(row.boundary_reason) }}
                  </template>
                  <template v-else>—</template>
                </td>
                <td class="py-2 pr-3">
                  <span
                    class="inline-flex justify-center items-center px-2 h-5 min-w-6 text-[11.5px] font-bold text-white rounded"
                    :class="notaClass(row.nota)"
                  >
                    {{ row.nota ?? '—' }}
                  </span>
                </td>
                <td class="py-2 pr-3 whitespace-nowrap text-n-slate-11">
                  {{ label(row.funil || '') }}
                </td>
                <td class="py-2 pr-3 max-w-[380px] text-n-slate-11">
                  <template
                    v-if="row.findings_matched && row.findings_matched.length"
                  >
                    <div
                      v-for="(f, fi) in row.findings_matched"
                      :key="fi"
                      class="mb-1 last:mb-0"
                    >
                      <span class="italic text-n-slate-12">
                        {{ `“${f.trecho}”` }}
                      </span>
                      <span class="block text-[11.5px] text-n-slate-10">
                        {{ f.porque }}
                      </span>
                    </div>
                  </template>
                  <span v-else class="block truncate">{{ row.resumo }}</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </template>
  </div>
</template>
