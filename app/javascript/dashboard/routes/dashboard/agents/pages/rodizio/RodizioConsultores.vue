<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'next/avatar/Avatar.vue';
import { useReportNarrative } from 'dashboard/composables/useReportNarrative';
import { duracao } from './tempo';
import { larguraDe } from './largura';

// "Está dividindo por igual?" respondido pelo comprimento das barras, sem ler número nenhum. Só o
// que passou PELA FILA entra na barra: continuidade e pedido do cliente já nascem com dono e não
// dizem nada sobre a justiça do rodízio — aparecem ao lado, em cinza, como contexto.
const props = defineProps({
  linhas: { type: Array, default: () => [] },
  // Consultor do filtro: a linha dele fica em destaque e as outras esmaecem (sem sumir — o
  // gestor quer comparar).
  destacado: { type: [Number, String], default: '' },
});

const emit = defineEmits(['escolher']);

const { t } = useI18n();
const { dotClassFor } = useReportNarrative();

const motivo = (linha, chave) => linha.motivos?.[chave] || 0;

const maior = computed(() =>
  Math.max(...props.linhas.map(linha => motivo(linha, 'rodizio')), 1)
);

const itens = computed(() =>
  props.linhas.map(linha => {
    const rodizio = motivo(linha, 'rodizio');
    const continuidade = motivo(linha, 'continuidade');
    const preferencia = motivo(linha, 'preferencia_cliente');
    const extras = [
      continuidade
        ? t('AGENTS_RODIZIO.AGENT_ROW.CONTINUITY', { n: continuidade })
        : null,
      preferencia
        ? t('AGENTS_RODIZIO.AGENT_ROW.PREFERENCE', { n: preferencia })
        : null,
    ].filter(Boolean);

    return {
      id: linha.user_id,
      nome: linha.nome || `#${linha.user_id}`,
      rodizio,
      largura: larguraDe(rodizio / maior.value),
      extras: extras.join(' · '),
      esperando: linha.abertos || 0,
      // Espera média por consultor: só aparece quando o backend manda (`media_espera_segundos`).
      media: linha.media_espera_segundos
        ? t('AGENTS_RODIZIO.AGENT_ROW.AVG', {
            tempo: duracao(t, linha.media_espera_segundos),
          })
        : '',
      bolinha: dotClassFor(linha.signal),
      detalhe: t('AGENTS_RODIZIO.AGENT_ROW.BREAKDOWN', {
        rodizio,
        continuidade,
        preferencia,
        repasse: motivo(linha, 'repasse_sla'),
        gestor:
          motivo(linha, 'escalado_gestor') + motivo(linha, 'manual_gestor'),
      }),
      apagado: props.destacado && String(props.destacado) !== String(linha.user_id),
    };
  })
);
</script>

<template>
  <section class="flex flex-col gap-3">
    <p class="m-0 text-sm text-n-slate-11">
      {{ t('AGENTS_RODIZIO.AGENT_ROW.HINT') }}
    </p>

    <p v-if="!itens.length" class="text-sm text-n-slate-10">
      {{ t('AGENTS_RODIZIO.EMPTY') }}
    </p>

    <ul v-else class="flex flex-col gap-1 m-0 list-none">
      <li v-for="item in itens" :key="item.id">
        <button
          class="grid w-full grid-cols-[minmax(9rem,14rem)_1fr] md:grid-cols-[minmax(9rem,14rem)_1fr_auto] items-center gap-x-4 gap-y-1 px-3 py-2.5 text-left border rounded-xl bg-white dark:bg-n-solid-2 border-n-weak transition-shadow hover:shadow-md"
          :class="{ 'opacity-50': item.apagado }"
          :title="t('AGENTS_RODIZIO.AGENT_ROW.OPEN_LEADS', { nome: item.nome })"
          @click="emit('escolher', item.id)"
        >
          <span class="flex items-center min-w-0 gap-2">
            <Avatar :name="item.nome" :size="24" rounded-full />
            <span class="text-sm font-medium truncate text-n-slate-12">
              {{ item.nome }}
            </span>
          </span>

          <span v-tooltip.top="item.detalhe" class="flex items-center gap-2">
            <span class="flex-1 h-2 rounded-full bg-n-slate-3 dark:bg-n-solid-1">
              <span
                class="block h-2 rounded-full bg-n-slate-9"
                :class="item.largura"
              />
            </span>
            <span
              class="w-8 text-sm font-semibold text-right tabular-nums text-n-slate-12"
            >
              {{ item.rodizio }}
            </span>
          </span>

          <span
            class="flex flex-wrap items-center col-span-2 gap-x-3 gap-y-1 text-xs md:col-span-1 md:justify-end text-n-slate-10"
          >
            <span v-if="item.extras">{{ item.extras }}</span>
            <span
              v-if="item.esperando"
              class="px-2 py-0.5 font-medium rounded-full bg-n-amber-3 text-n-amber-11 whitespace-nowrap"
            >
              {{ t('AGENTS_RODIZIO.AGENT_ROW.WAITING', { n: item.esperando }) }}
            </span>
            <span
              v-if="item.media"
              class="inline-flex items-center gap-1.5 whitespace-nowrap"
            >
              <span
                v-if="item.bolinha"
                class="rounded-full size-2"
                :class="item.bolinha"
              />
              {{ item.media }}
            </span>
            <span class="i-lucide-chevron-right size-4 text-n-slate-10" />
          </span>
        </button>
      </li>
    </ul>
  </section>
</template>
