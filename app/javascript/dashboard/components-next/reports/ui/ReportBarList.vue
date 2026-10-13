<script setup>
import { computed } from 'vue';

// Lista de barras horizontais (CSAT por agente, NPS por time, SLA por politica...):
// nome, barra e valor. A cor de cada barra vem da linha (verde dentro da meta, amarelo perto,
// vermelho longe); a linha tracejada marca a meta quando ha uma.
const props = defineProps({
  // [{ key, label, value, display, barClass, hint }]
  rows: { type: Array, required: true },
  // escala da barra; sem ela, o maior valor ocupa a barra inteira
  max: { type: Number, default: null },
  goal: { type: Number, default: null },
  clickable: { type: Boolean, default: false },
  emptyText: { type: String, default: '' },
});

const emit = defineEmits(['select']);

const scale = computed(
  () => props.max || Math.max(1, ...props.rows.map(row => row.value))
);
const pct = value => Math.min(100, (value / scale.value) * 100);
</script>

<template>
  <p v-if="!rows.length" class="mt-4 mb-0 text-sm text-n-slate-11">
    {{ emptyText }}
  </p>
  <ul v-else class="flex flex-col gap-1 p-0 m-0 mt-4 list-none">
    <li v-for="row in rows" :key="row.key">
      <component
        :is="clickable ? 'button' : 'div'"
        :type="clickable ? 'button' : undefined"
        class="grid items-center w-full grid-cols-[minmax(0,7rem)_1fr_4.75rem] gap-3 px-2 py-1.5 m-0 -mx-2 text-left rounded-xl text-[length:inherit]"
        :class="clickable ? 'cursor-pointer hover:bg-n-alpha-1' : ''"
        :title="row.hint || row.label"
        @click="clickable && emit('select', row)"
      >
        <span class="text-[13px] font-semibold text-n-slate-12 truncate">
          {{ row.label }}
        </span>
        <span class="relative h-2.5 rounded-full bg-n-alpha-2">
          <span
            class="absolute inset-y-0 left-0 rounded-full"
            :class="row.barClass || 'bg-n-blue-9'"
            :style="{ width: `${pct(row.value)}%` }"
          />
          <span
            v-if="goal !== null"
            class="absolute -inset-y-1 border-l-2 border-dashed border-n-slate-9"
            :style="{ left: `${pct(goal)}%` }"
          />
        </span>
        <span
          class="text-xs font-bold text-right whitespace-nowrap tabular-nums text-n-slate-12"
        >
          {{ row.display }}
        </span>
      </component>
    </li>
  </ul>
</template>
