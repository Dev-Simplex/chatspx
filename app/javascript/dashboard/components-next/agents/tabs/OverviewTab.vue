<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import NumberFlow from '@number-flow/vue';
import CaptainAssistantAPI from 'dashboard/api/captain/assistant';
import { useCaptainAssistantModel } from 'dashboard/composables/useCaptainAssistantModel';

import AiStatCard from 'dashboard/components-next/agents-ui/AiStatCard.vue';
import AiListGroup from 'dashboard/components-next/agents-ui/AiListGroup.vue';
import AiListRow from 'dashboard/components-next/agents-ui/AiListRow.vue';

const { t } = useI18n();
const route = useRoute();
const store = useStore();

const assistantId = computed(() => Number(route.params.assistantId));
const agent = computed(() =>
  store.getters['captainAssistants/getRecord'](assistantId.value)
);
// `agent.config.model` não existe no payload: a linha "Modelo" mostrava sempre "—".
// O modelo é da CONTA (Agentable#agent_model). Ver useCaptainAssistantModel.
const { assistantModel } = useCaptainAssistantModel();

// Métricas REAIS (endpoint /stats — conversas do agent_bot do assistant)
const stats = ref({
  handled: 0,
  resolved: 0,
  resolution_rate: 0,
  csat: 0,
  handoffs: 0,
  series: [],
});

async function loadStats() {
  try {
    const { data } = await CaptainAssistantAPI.stats(assistantId.value);
    if (data) stats.value = data;
  } catch (e) {
    // silencioso — mantém zeros
  }
}

onMounted(loadStats);

const heroPct = computed(() => Number(stats.value.resolution_rate) || 0);
const heroCaption = computed(() =>
  stats.value.handled > 0
    ? t('CAPTAIN.AGENT_TABS.OVERVIEW.HERO_CAPTION', {
        count: stats.value.handled,
      })
    : t('CAPTAIN.AGENT_TABS.OVERVIEW.HERO_EMPTY')
);

const kpis = computed(() => [
  {
    icon: 'i-lucide-messages-square',
    tint: '#1faa59',
    value: stats.value.handled,
    label: t('CAPTAIN.AGENT_TABS.OVERVIEW.KPI_HANDLED'),
    spark: true,
  },
  {
    icon: 'i-lucide-smile',
    tint: '#34c759',
    value: stats.value.csat || 0,
    label: t('CAPTAIN.AGENT_TABS.OVERVIEW.KPI_CSAT'),
  },
  {
    icon: 'i-lucide-check-check',
    tint: '#0a84ff',
    value: stats.value.resolved,
    label: t('CAPTAIN.AGENT_TABS.OVERVIEW.KPI_RESOLVED'),
  },
  {
    icon: 'i-lucide-user-round',
    tint: '#ff3b30',
    value: stats.value.handoffs,
    label: t('CAPTAIN.AGENT_TABS.OVERVIEW.KPI_HANDOFFS'),
  },
]);

const sparkPoints = computed(() => {
  const s = stats.value.series || [];
  if (!s.length) return '';
  const vals = s.map(p => Number(p.count) || 0);
  const max = Math.max(1, ...vals);
  const n = vals.length;
  return vals
    .map((v, i) => `${(i / (n - 1 || 1)) * 100},${28 - (v / max) * 26}`)
    .join(' ');
});

const hasBehavior = computed(() => {
  const b = agent.value?.behavior;
  return b && Object.keys(b).length > 0;
});
const enabledBehaviors = computed(() => {
  const b = agent.value?.behavior || {};
  return Object.keys(b).filter(k => {
    const v = b[k];
    if (typeof v === 'object' && v !== null) return v.enabled !== false;
    if (typeof v === 'number') return v > 0;
    return Boolean(v);
  });
});
</script>

<template>
  <div class="px-6 pt-4 pb-10 mx-auto space-y-6 max-w-3xl">
    <!-- Herói: taxa de resolução real -->
    <div
      class="p-5 rounded-2xl border bg-gradient-to-br to-transparent border-n-weak from-n-brand/10"
    >
      <div class="flex gap-4 items-center">
        <div
          class="text-[40px] font-black leading-none tracking-tight text-n-slate-12"
        >
          <NumberFlow :value="heroPct" suffix="%" />
        </div>
        <p class="max-w-xs text-[13.5px] text-n-slate-11">{{ heroCaption }}</p>
      </div>
    </div>

    <!-- KPIs reais -->
    <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
      <AiStatCard
        v-for="(k, i) in kpis"
        :key="k.icon"
        :value="k.value"
        :label="k.label"
        :icon="k.icon"
        :tint="k.tint"
        :style="{ animationDelay: `${i * 70}ms` }"
      >
        <template v-if="k.spark && sparkPoints" #spark>
          <svg
            class="mt-2 w-full h-7"
            viewBox="0 0 100 28"
            preserveAspectRatio="none"
          >
            <polyline
              fill="none"
              stroke="#1faa59"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
              :points="sparkPoints"
            />
          </svg>
        </template>
      </AiStatCard>
    </div>

    <!-- Configuração do agente -->
    <template v-if="hasBehavior">
      <p
        class="px-1 pt-1 pb-2 text-xs font-bold tracking-wide uppercase text-n-slate-10"
      >
        {{ t('CAPTAIN.AGENT_TABS.OVERVIEW.AGENT_CONFIG') }}
      </p>
      <AiListGroup>
        <AiListRow
          :title="t('CAPTAIN.AGENT_TABS.OVERVIEW.MODEL')"
          :subtitle="t('CAPTAIN.AGENT_TABS.OVERVIEW.MODEL_HINT')"
        >
          <template #leading>
            <span
              class="grid place-items-center text-white bg-green-500 rounded-lg size-[30px]"
            >
              <span class="i-lucide-cpu size-4" />
            </span>
          </template>
          <template #trailing>
            <span class="font-mono text-sm text-n-slate-12">{{
              assistantModel || '—'
            }}</span>
          </template>
        </AiListRow>
        <AiListRow :title="t('CAPTAIN.AGENT_TABS.OVERVIEW.TEMPERATURE')">
          <template #leading>
            <span
              class="grid place-items-center text-n-black bg-n-amber-9 rounded-lg size-[30px]"
            >
              <span class="i-lucide-thermometer size-4" />
            </span>
          </template>
          <template #trailing>
            <span class="font-mono text-sm text-n-slate-12">{{
              agent?.config?.temperature ?? '—'
            }}</span>
          </template>
        </AiListRow>
        <AiListRow :title="t('CAPTAIN.AGENT_TABS.OVERVIEW.BEHAVIORS')">
          <template #leading>
            <span
              class="grid place-items-center text-white bg-n-violet-9 rounded-lg size-[30px]"
            >
              <span class="i-lucide-settings size-4" />
            </span>
          </template>
          <div class="flex flex-wrap gap-1.5 mt-1">
            <span
              v-for="bkey in enabledBehaviors"
              :key="bkey"
              class="px-2 py-0.5 font-mono text-xs rounded-full bg-n-alpha-2 text-n-slate-11"
            >
              {{ bkey }}
            </span>
            <span
              v-if="!enabledBehaviors.length"
              class="text-xs text-n-slate-10"
            >
              {{ t('CAPTAIN.AGENT_TABS.OVERVIEW.NONE_CONFIGURED') }}
            </span>
          </div>
        </AiListRow>
      </AiListGroup>
    </template>
    <template v-else>
      <div
        class="flex flex-col items-center px-6 py-14 text-center rounded-2xl border border-dashed border-n-weak bg-n-alpha-1"
      >
        <span class="mb-3 i-lucide-rocket size-9 text-n-slate-9" />
        <h3 class="mb-1 text-base font-semibold text-n-slate-12">
          {{ t('CAPTAIN.AGENT_TABS.OVERVIEW.CONFIGURE_TITLE') }}
        </h3>
        <p class="max-w-md text-sm text-n-slate-10">
          {{ t('CAPTAIN.AGENT_TABS.OVERVIEW.CONFIGURE_DESCRIPTION') }}
        </p>
      </div>
    </template>
  </div>
</template>
