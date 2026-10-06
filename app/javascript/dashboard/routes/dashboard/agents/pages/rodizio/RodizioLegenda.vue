<script setup>
import { useI18n } from 'vue-i18n';
import { FAIXAS } from './faixa';

// Legenda sempre à vista, em cima da lista: quem abre a tela pela primeira vez entende o cartão
// sem ninguém explicar — o que é cada bolinha, qual é a atual, e o que a cor da espera quer dizer.
defineProps({
  limiar: { type: Number, default: 30 },
});

const { t } = useI18n();
</script>

<template>
  <div
    class="flex flex-wrap items-center px-3 py-2 text-xs border rounded-lg gap-x-4 gap-y-1.5 border-n-weak bg-n-slate-2 dark:bg-n-solid-2 text-n-slate-11"
  >
    <span class="font-medium text-n-slate-12">
      {{ t('AGENTS_RODIZIO.TIMELINE.LEGEND.TITLE') }}
    </span>
    <span class="inline-flex items-center gap-1.5">
      <span
        class="flex items-center justify-center rounded-full size-4 bg-n-slate-3 text-n-slate-11"
      >
        <span class="i-lucide-user-check size-2.5" />
      </span>
      {{ t('AGENTS_RODIZIO.TIMELINE.LEGEND.STEPS') }}
    </span>
    <span class="inline-flex items-center gap-1.5">
      <span
        class="rounded-full size-4 bg-n-slate-3 text-n-slate-11 ring-2 ring-current"
      />
      {{ t('AGENTS_RODIZIO.TIMELINE.LEGEND.NOW') }}
    </span>
    <span class="inline-flex flex-wrap items-center gap-x-3 gap-y-1">
      <span class="inline-flex items-center gap-1.5">
        <span class="w-4 h-1.5 rounded-full" :class="FAIXAS.ok.barra" />
        {{ t('AGENTS_RODIZIO.TIMELINE.LEGEND.OK', { min: limiar }) }}
      </span>
      <span class="inline-flex items-center gap-1.5">
        <span class="w-4 h-1.5 rounded-full" :class="FAIXAS.atencao.barra" />
        {{ t('AGENTS_RODIZIO.TIMELINE.LEGEND.WARN', { min: limiar }) }}
      </span>
      <span class="inline-flex items-center gap-1.5">
        <span class="w-4 h-1.5 rounded-full" :class="FAIXAS.atrasado.barra" />
        {{ t('AGENTS_RODIZIO.TIMELINE.LEGEND.LATE', { min: limiar }) }}
      </span>
      <span class="text-n-slate-10">
        {{ t('AGENTS_RODIZIO.TIMELINE.LEGEND.RULE') }}
      </span>
    </span>
  </div>
</template>
