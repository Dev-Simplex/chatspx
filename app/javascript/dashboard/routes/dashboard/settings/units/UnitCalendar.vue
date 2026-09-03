<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  startOfMonth,
  endOfMonth,
  startOfWeek,
  endOfWeek,
  addDays,
  eachDayOfInterval,
  isSameMonth,
  isSameDay,
  addMonths,
  subMonths,
} from 'date-fns';
import Button from 'dashboard/components-next/button/Button.vue';
import { comoTextoISO, regraValeNoDia } from './unitSchedule';

const props = defineProps({
  // Regras já cadastradas, no formato que a API devolve.
  rules: { type: Array, default: () => [] },
  // Grade da semana, para o calendário mostrar o dia que a unidade não abre.
  workingHours: { type: Array, default: () => [] },
  // Dia escolhido, em ISO — é o que abre o painel de perguntas.
  selected: { type: String, default: '' },
  cores: { type: Object, required: true },
});
const emit = defineEmits(['select', 'edit']);

const { t, locale } = useI18n();

const mes = ref(startOfMonth(new Date()));

const idioma = computed(() => locale.value.replace('_', '-'));

const titulo = computed(() =>
  new Intl.DateTimeFormat(idioma.value, {
    month: 'long',
    year: 'numeric',
  }).format(mes.value)
);

// Sempre seis semanas: o calendário não pula de altura ao trocar de mês, e a última
// linha mostra o começo do mês seguinte em vez de sumir.
const dias = computed(() => {
  const inicio = startOfWeek(startOfMonth(mes.value));
  const fimDoMes = endOfWeek(endOfMonth(mes.value));
  const semanas = Math.round((fimDoMes - inicio) / (7 * 24 * 60 * 60 * 1000));
  const fim = semanas < 6 ? addDays(fimDoMes, (6 - semanas) * 7) : fimDoMes;
  return eachDayOfInterval({ start: inicio, end: fim });
});

const hoje = new Date();
const selecionado = computed(() =>
  props.selected ? new Date(`${props.selected}T12:00:00`) : null
);

const fechadoNaSemana = data =>
  props.workingHours.find(hora => hora.day_of_week === data.getDay())
    ?.closed_all_day ?? false;

const regrasDoDia = data =>
  props.rules
    .map((regra, index) => ({ ...regra, index }))
    .filter(regra => regraValeNoDia(regra, data));

const celulas = computed(() =>
  dias.value.map(data => ({
    data,
    chave: comoTextoISO(data),
    numero: data.getDate(),
    doMes: isSameMonth(data, mes.value),
    ehHoje: isSameDay(data, hoje),
    ehSelecionado: !!selecionado.value && isSameDay(data, selecionado.value),
    fechado: fechadoNaSemana(data),
    regras: regrasDoDia(data),
  }))
);

const irPara = quantos => {
  mes.value = quantos > 0 ? addMonths(mes.value, 1) : subMonths(mes.value, 1);
};

const voltarParaHoje = () => {
  mes.value = startOfMonth(new Date());
  emit('select', comoTextoISO(new Date()));
};
</script>

<template>
  <div class="overflow-hidden border rounded-xl border-n-weak">
    <div
      class="flex flex-wrap items-center justify-between gap-2 px-3 py-2 border-b border-n-weak bg-n-solid-1"
    >
      <div class="flex items-center gap-1">
        <Button
          ghost
          slate
          xs
          icon="i-lucide-chevron-left"
          :title="t('UNITS_MGMT.FORM.CALENDAR.PREVIOUS')"
          @click.prevent="irPara(-1)"
        />
        <span class="text-heading-3 text-n-slate-12 first-letter:uppercase">
          {{ titulo }}
        </span>
        <Button
          ghost
          slate
          xs
          icon="i-lucide-chevron-right"
          :title="t('UNITS_MGMT.FORM.CALENDAR.NEXT')"
          @click.prevent="irPara(1)"
        />
      </div>
      <Button
        faded
        slate
        xs
        :label="t('UNITS_MGMT.FORM.CALENDAR.TODAY')"
        @click.prevent="voltarParaHoje"
      />
    </div>

    <div class="grid grid-cols-7 bg-n-solid-1">
      <span
        v-for="dia in [0, 1, 2, 3, 4, 5, 6]"
        :key="dia"
        class="px-2 py-1.5 text-center uppercase text-label-small text-n-slate-11"
      >
        {{ t(`UNITS_MGMT.WEEKDAYS_SHORT.${dia}`) }}
      </span>
    </div>

    <!-- gap-px sobre um fundo: as linhas da malha são o próprio fundo aparecendo entre
         as células. `border` não serve aqui — o CSS global do app zera a borda de todo
         `button`, e a utilitária do Tailwind perde para ele. -->
    <div class="grid grid-cols-7 gap-px bg-n-weak border-t border-n-weak">
      <button
        v-for="celula in celulas"
        :key="celula.chave"
        type="button"
        class="flex flex-col items-stretch gap-1 p-1.5 text-start min-h-20 bg-n-solid-1 hover:brightness-110"
        :class="{
          'bg-n-slate-2 dark:bg-n-solid-2': celula.fechado && celula.doMes,
          'opacity-40': !celula.doMes,
          'outline outline-1 -outline-offset-1 outline-n-brand !bg-n-brand/10':
            celula.ehSelecionado,
        }"
        @click.prevent="emit('select', celula.chave)"
      >
        <span
          class="self-start px-1.5 py-0.5 rounded-full text-label-small tabular-nums"
          :class="
            celula.ehHoje
              ? 'bg-n-brand text-white font-medium'
              : 'text-n-slate-11'
          "
        >
          {{ celula.numero }}
        </span>
        <span
          v-for="regra in celula.regras"
          :key="regra.index"
          class="px-1.5 py-0.5 rounded text-label-small truncate cursor-pointer"
          :class="cores[regra.category]"
          :title="regra.name"
          @click.stop.prevent="emit('edit', regra.index)"
        >
          {{ regra.name }}
        </span>
      </button>
    </div>
  </div>
</template>
