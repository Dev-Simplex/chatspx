<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatDuration } from 'dashboard/helper/reportFormat';

// Uma barra por time com a 1a resposta media do periodo, e a linha tracejada da meta.
// Barra acima da meta fica vermelha: o olho vai direto para o time que precisa de ajuda.
const props = defineProps({
  // [{ id, name, seconds }]
  rows: { type: Array, required: true },
  goalSeconds: { type: Number, default: 300 },
});

const { t } = useI18n();

// Folga de 20% no topo para o rotulo da barra mais alta caber.
const scaleMax = computed(() =>
  Math.max(props.goalSeconds * 1.5, ...props.rows.map(row => row.seconds * 1.2))
);
const pct = seconds => (seconds / scaleMax.value) * 100;
</script>

<template>
  <section
    class="flex flex-col p-5 rounded-xl border border-n-weak bg-n-solid-2 min-w-0"
  >
    <div class="flex items-start justify-between gap-2">
      <div class="min-w-0">
        <h2 class="m-0 text-base font-semibold text-n-slate-12">
          {{ t('REPORTS_PANEL.FIRST_RESPONSE.TITLE') }}
        </h2>
        <p class="mt-0.5 mb-0 text-sm text-n-slate-11">
          {{ t('REPORTS_PANEL.FIRST_RESPONSE.SUB') }}
        </p>
      </div>
      <span
        class="flex items-center gap-1.5 shrink-0 text-xs font-semibold text-n-slate-11"
      >
        <span class="w-4 border-t-2 border-dashed border-n-ruby-9" />
        {{
          t('REPORTS_PANEL.FIRST_RESPONSE.GOAL', {
            time: formatDuration(goalSeconds, t),
          })
        }}
      </span>
    </div>

    <p v-if="!rows.length" class="mt-6 mb-0 text-sm text-n-slate-11">
      {{ t('REPORTS_PANEL.FIRST_RESPONSE.EMPTY') }}
    </p>
    <div v-else class="relative mt-6 overflow-x-auto">
      <div class="relative flex items-end gap-4 h-48 min-w-max px-1">
        <div
          class="absolute inset-x-0 border-t-2 border-dashed border-n-ruby-9 pointer-events-none"
          :style="{ bottom: `${pct(goalSeconds)}%` }"
        />
        <div
          v-for="row in rows"
          :key="row.id"
          class="flex flex-col items-center justify-end h-full w-20"
        >
          <span
            class="mb-1 text-xs font-semibold tabular-nums"
            :class="
              row.seconds > goalSeconds ? 'text-n-ruby-11' : 'text-n-slate-12'
            "
          >
            {{ formatDuration(row.seconds, t) }}
          </span>
          <span
            class="w-10 rounded-t-md"
            :class="row.seconds > goalSeconds ? 'bg-n-ruby-9' : 'bg-n-blue-9'"
            :style="{ height: `${Math.max(pct(row.seconds), 1)}%` }"
          />
        </div>
      </div>
      <div class="flex gap-4 min-w-max px-1 mt-2">
        <span
          v-for="row in rows"
          :key="row.id"
          class="w-20 text-xs text-center text-n-slate-11 line-clamp-2 break-words"
          :title="row.name"
        >
          {{ row.name }}
        </span>
      </div>
    </div>
  </section>
</template>
