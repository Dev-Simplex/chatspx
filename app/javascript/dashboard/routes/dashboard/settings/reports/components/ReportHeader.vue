<script setup>
import BackButton from 'dashboard/components/widgets/BackButton.vue';
import { useMapGetter } from 'dashboard/composables/store';

// Cabecalho de todas as telas de Relatorios, no padrao do Painel: um cartao com o nome da conta,
// o titulo, a descricao e as acoes. Os filtros da tela entram no rodape do cartao, pelo slot
// `filters` ou pelo ReportHeaderFilters (quando o filtro mora dentro de um componente filho).
defineProps({
  headerTitle: {
    required: true,
    type: String,
  },
  headerDescription: {
    type: String,
    default: '',
  },
  hasBackButton: {
    type: Boolean,
    default: false,
  },
});

const account = useMapGetter('getCurrentAccount');
</script>

<template>
  <section
    class="flex flex-col gap-4 p-5 mt-6 rounded-2xl border border-n-weak bg-n-solid-2"
  >
    <div v-if="hasBackButton">
      <BackButton compact />
    </div>
    <div class="flex flex-wrap items-start justify-between w-full gap-4">
      <div class="flex flex-col gap-1 min-w-0 max-w-3xl">
        <p
          class="m-0 text-xs font-semibold tracking-wider uppercase text-n-slate-10 truncate"
        >
          {{ account?.name }}
        </p>
        <h1 class="m-0 text-3xl font-semibold tracking-tight text-n-slate-12">
          {{ headerTitle }}
        </h1>
        <p
          v-if="headerDescription"
          class="mt-1 mb-0 text-sm text-n-slate-11 line-clamp-5 sm:line-clamp-none"
        >
          {{ headerDescription }}
        </p>
      </div>
      <div class="flex flex-wrap items-center gap-2 shrink-0">
        <slot />
      </div>
    </div>
    <div id="report-header-filters" class="empty:hidden">
      <slot name="filters" />
    </div>
  </section>
</template>
