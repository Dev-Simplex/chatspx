<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useToggle } from '@vueuse/core';
import KanbanAPI from 'dashboard/api/kanban';
import { teamDisplayName } from 'dashboard/helper/reportFormat';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

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

// Mesmo seletor das outras telas de relatorio (botao + DropdownMenu), no lugar do select nativo.
const [showFunnels, toggleFunnels] = useToggle();
const funnelItems = computed(() =>
  funnels.value.map(funnel => ({
    action: 'select',
    value: funnel.id,
    label: teamDisplayName(funnel.name),
    isSelected: funnel.id === funnelId.value,
  }))
);
const funnelLabel = computed(
  () => funnelItems.value.find(item => item.isSelected)?.label
);
const pickFunnel = ({ value }) => {
  toggleFunnels(false);
  funnelId.value = value;
};

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
        <div
          v-if="funnels.length > 1"
          v-on-clickaway="() => toggleFunnels(false)"
          class="relative"
        >
          <Button
            sm
            slate
            faded
            :label="funnelLabel"
            :aria-label="t('REPORTS_PANEL.FUNNEL.TITLE')"
            icon="i-lucide-chevron-down"
            trailing-icon
            class="max-w-48"
            @click="toggleFunnels()"
          />
          <DropdownMenu
            v-if="showFunnels"
            :menu-items="funnelItems"
            class="mt-1 top-full ltr:right-0 rtl:left-0 max-h-72 overflow-y-auto"
            @action="pickFunnel"
          />
        </div>
        <router-link
          :to="{ name: 'kanban_funnel', params: { funnelId } }"
          class="flex items-center gap-1.5 h-8 px-3 text-sm font-semibold rounded-lg text-n-slate-12 no-underline hover:bg-n-alpha-2"
        >
          <span class="i-lucide-square-kanban size-4" />
          {{ t('REPORTS_PANEL.FUNNEL.OPEN') }}
        </router-link>
      </div>
    </div>

    <!-- A coluna do nome cresce ate o nome mais longo (subgrid alinha as barras de todas as linhas);
         nome longo demais quebra em duas linhas em vez de ser cortado. -->
    <ul
      class="grid grid-cols-[auto_1fr_3rem] gap-x-3 gap-y-2 p-0 m-0 mt-4 list-none"
    >
      <li
        v-for="stage in stages"
        :key="stage.id"
        class="grid items-center col-span-3 grid-cols-subgrid"
      >
        <span
          class="text-sm leading-tight text-n-slate-11 max-w-48 break-words"
        >
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
