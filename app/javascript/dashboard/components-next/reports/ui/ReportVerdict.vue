<script setup>
import { computed } from 'vue';
import { useReportNarrative } from 'dashboard/composables/useReportNarrative';

// A frase de veredito do topo de cada tela de Relatorios: um rosto, um titulo curto e uma frase
// que responde "esta bom ou ruim?" antes de qualquer numero. Vem dos signals da tela, ou de um
// veredito pronto (`verdict`) quando a tela julga outra coisa (ex.: quem espera agora).
const props = defineProps({
  signals: { type: Array, default: () => [] },
  // { level: 'good'|'warn'|'bad'|'empty', title, text }
  verdict: { type: Object, default: null },
});

const { verdictFor } = useReportNarrative();

const result = computed(() => props.verdict || verdictFor(props.signals));

const LOOK = {
  good: {
    face: '😊',
    box: 'border-n-teal-7 bg-n-teal-3/60',
    title: 'text-n-teal-11',
  },
  warn: {
    face: '😐',
    box: 'border-n-amber-7 bg-n-amber-3/60',
    title: 'text-n-amber-11',
  },
  bad: {
    face: '😟',
    box: 'border-n-ruby-7 bg-n-ruby-3/60',
    title: 'text-n-ruby-11',
  },
  empty: {
    face: '🤔',
    box: 'border-n-weak bg-n-solid-2/80',
    title: 'text-n-slate-12',
  },
};
const look = computed(() => LOOK[result.value.level] || LOOK.empty);
</script>

<template>
  <section
    class="flex items-center gap-4 px-5 py-4 rounded-[22px] border backdrop-blur-xl"
    :class="look.box"
    role="status"
  >
    <span class="text-4xl leading-none shrink-0" aria-hidden="true">
      {{ look.face }}
    </span>
    <p class="m-0 text-base leading-snug text-n-slate-12 sm:text-lg">
      <strong class="font-extrabold" :class="look.title">
        {{ result.title }}
      </strong>
      {{ result.text }}
    </p>
  </section>
</template>
