<script setup>
import Spinner from 'shared/components/Spinner.vue';
import ReportLiveDot from 'dashboard/components-next/reports/ui/ReportLiveDot.vue';
import {
  GLASS_CARD,
  SECTION_TITLE,
} from 'dashboard/components-next/reports/ui/styles';

// Cartao ao vivo da Visao Geral, no desenho dos outros relatorios (vidro, titulo forte,
// ponto pulsando de "em tempo real"). Os dados continuam vindo de quem usa o cartao.
defineProps({
  header: {
    type: String,
    default: '',
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  loadingMessage: {
    type: String,
    default: '',
  },
});
</script>

<template>
  <section
    class="flex flex-col flex-grow min-w-0 p-5 text-n-slate-12"
    :class="GLASS_CARD"
  >
    <div class="flex flex-wrap items-center justify-between gap-3 mb-4">
      <slot name="header">
        <h2 class="flex items-center gap-2" :class="SECTION_TITLE">
          <ReportLiveDot />
          {{ header }}
          <span
            class="px-2 py-0.5 text-[11px] font-semibold rounded-full bg-n-teal-3 text-n-teal-11"
          >
            {{ $t('OVERVIEW_REPORTS.LIVE') }}
          </span>
        </h2>
        <div class="flex flex-row items-center justify-end gap-2">
          <slot name="control" />
        </div>
      </slot>
    </div>
    <div v-if="!isLoading" class="flex justify-between w-full max-w-full">
      <slot />
    </div>
    <div v-else class="flex items-center justify-center px-12 py-6 text-base">
      <Spinner />
      <span class="text-n-slate-11">
        {{ loadingMessage }}
      </span>
    </div>
  </section>
</template>
