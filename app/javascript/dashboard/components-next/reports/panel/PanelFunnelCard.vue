<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import KanbanAPI from 'dashboard/api/kanban';

// Quantos cards estao em cada etapa do funil agora (o funil e uma foto do momento,
// nao depende do periodo). Com mais de um funil, da para escolher qual mostrar.
const emit = defineEmits(['empty']);
const { t } = useI18n();

const funnels = ref([]);
const funnelId = ref(null);
const stages = ref([]);

const loadStats = async () => {
  if (!funnelId.value) return;
  try {
    const { data } = await KanbanAPI.getFunnelStats(funnelId.value);
    stages.value = data.stages || [];
  } catch {
    // Sem os numeros deste funil, nao deixa os do funil anterior na tela.
    stages.value = [];
  }
};

onMounted(async () => {
  const { data } = await KanbanAPI.getFunnels();
  funnels.value = data || [];
  if (!funnels.value.length) {
    emit('empty');
    return;
  }
  funnelId.value = funnels.value[0].id;
});
watch(funnelId, loadStats);

// O funil de um setor nasce com o nome do time, que o sistema grava em minusculas.
const displayName = name =>
  (name || '').replace(
    /(^|[\s(])(\p{Ll})/gu,
    (_, space, letter) => `${space}${letter.toUpperCase()}`
  );

const maxCount = computed(() =>
  Math.max(1, ...stages.value.map(stage => stage.count))
);
</script>

<template>
  <section
    v-if="funnels.length"
    class="flex flex-col p-5 relative hover:z-30 focus-within:z-30 rounded-[22px] border border-n-weak bg-n-solid-2/80 backdrop-blur-xl shadow-[inset_0_1px_0_rgb(255_255_255/0.7),0_14px_36px_rgb(16_24_40/0.08)] dark:shadow-[inset_0_1px_0_rgb(255_255_255/0.06),0_14px_36px_rgb(0_0_0/0.4)] min-w-0"
  >
    <div class="flex flex-wrap items-start justify-between gap-2">
      <div class="min-w-0">
        <h2
          class="m-0 text-[15px] font-extrabold tracking-[-0.015em] text-n-slate-12"
        >
          {{ t('REPORTS_PANEL.FUNNEL.TITLE') }}
        </h2>
        <p class="mt-0.5 mb-0 text-sm text-n-slate-11">
          {{ t('REPORTS_PANEL.FUNNEL.SUB') }}
        </p>
      </div>
      <div class="flex items-center gap-2">
        <select
          v-if="funnels.length > 1"
          v-model="funnelId"
          class="h-8 py-0 m-0 text-sm w-auto max-w-48"
          :aria-label="t('REPORTS_PANEL.FUNNEL.TITLE')"
        >
          <option v-for="funnel in funnels" :key="funnel.id" :value="funnel.id">
            {{ displayName(funnel.name) }}
          </option>
        </select>
        <router-link
          :to="{ name: 'kanban_funnel', params: { funnelId } }"
          class="flex items-center gap-1.5 h-8 px-3 text-sm font-semibold rounded-lg text-n-slate-12 no-underline hover:bg-n-alpha-2"
        >
          <span class="i-lucide-square-kanban size-4" />
          {{ t('REPORTS_PANEL.FUNNEL.OPEN') }}
        </router-link>
      </div>
    </div>

    <ul class="flex flex-col gap-2 p-0 m-0 mt-4 list-none">
      <li
        v-for="stage in stages"
        :key="stage.id"
        class="grid items-center grid-cols-[8rem_1fr_3rem] gap-3"
      >
        <span class="text-sm text-n-slate-11 truncate" :title="stage.name">
          {{ stage.name }}
        </span>
        <span class="flex justify-start">
          <span
            class="block h-6 rounded-md bg-n-blue-9"
            :style="{
              width: `${Math.max((stage.count / maxCount) * 100, 2)}%`,
              backgroundColor: stage.color || undefined,
            }"
          />
        </span>
        <span
          class="text-sm font-semibold text-right tabular-nums text-n-slate-12"
        >
          {{ stage.count }}
        </span>
      </li>
    </ul>
  </section>
</template>
