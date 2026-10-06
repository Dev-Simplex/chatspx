<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { duracao } from './tempo';
import { FAIXAS, faixaDaEspera } from './faixa';
import { linkDaConversa } from './conversa';

// O topo da tela responde, em cinco segundos, "está tudo bem ou tem lead esquecido, e com quem?".
// Primeiro uma frase com semáforo; logo abaixo, a lista do que precisa de ação, do pior para o
// melhor; e só depois os números do período.
const props = defineProps({
  // `sem_movimento` do backend: leads entregues que ninguém pegou há mais do limite. Vale AGORA,
  // independente do período, porque lead esquecido em setembro continua esquecido em outubro.
  parados: { type: Object, required: true },
  // Contagens e espera média dos leads do rodízio no período (sem filtro de consultor).
  geral: { type: Object, default: () => ({}) },
  totais: { type: Object, default: () => ({}) },
  limiar: { type: Number, default: 30 },
  decorrido: { type: Number, default: 0 },
  accountId: { type: [Number, String], required: true },
});

const emit = defineEmits(['verEsperando', 'porQue']);

const { t } = useI18n();
const tempo = segundos => duracao(t, segundos);

const MAXIMO_NA_LISTA = 5;

// Os parados chegam do mais antigo para o mais novo: a ordem já é "do pior para o melhor".
const esperaDe = lead => (lead.minutos_parado || 0) * 60 + props.decorrido;
const atrasados = computed(() => props.parados.leads || []);
const naLista = computed(() => atrasados.value.slice(0, MAXIMO_NA_LISTA));
const foraDaLista = computed(() =>
  Math.max((props.parados.total || 0) - naLista.value.length, 0)
);

const contagem = computed(() => props.geral?.contagem || {});
// Esperando, mas ainda dentro do limite: ninguém esqueceu, só ainda não deu tempo.
const esperandoNoPrazo = computed(() =>
  Math.max((contagem.value.espera || 0) - (props.parados.total || 0), 0)
);

const nivel = computed(() => {
  if (props.parados.total > 0) return 'vermelho';
  if (esperandoNoPrazo.value > 0) return 'amarelo';
  return 'verde';
});

const NIVEIS = {
  vermelho: {
    icone: 'i-lucide-siren',
    caixa: 'border-n-ruby-6 bg-n-ruby-2',
    selo: 'bg-n-ruby-9 text-n-black',
  },
  amarelo: {
    icone: 'i-lucide-hourglass',
    caixa: 'border-n-amber-6 bg-n-amber-2',
    selo: 'bg-n-amber-9 text-n-black',
  },
  verde: {
    icone: 'i-lucide-circle-check',
    caixa: 'border-n-teal-6 bg-n-teal-2',
    selo: 'bg-n-teal-9 text-n-black',
  },
};

// "Victoria Fabonatto, Gelson de Paula e admin" — quem está com os atrasados, sem repetir nome.
const listaDeNomes = nomes => {
  if (nomes.length <= 1) return nomes.join('');
  return t('AGENTS_RODIZIO.SUMMARY.LIST', {
    inicio: nomes.slice(0, -1).join(', '),
    fim: nomes[nomes.length - 1],
  });
};

const nomeDe = lead => lead.corretor || t('AGENTS_RODIZIO.DETAIL.NOBODY');

const frase = computed(() => {
  const min = props.limiar;
  if (nivel.value === 'vermelho') {
    const n = props.parados.total;
    const pessoas = [...new Set(atrasados.value.map(nomeDe))];
    const maisAntigo = atrasados.value[0];
    return {
      titulo: t('AGENTS_RODIZIO.SUMMARY.LATE_TITLE', { n, min }, n),
      detalhe: [
        maisAntigo &&
          t('AGENTS_RODIZIO.SUMMARY.LATE_OLDEST', {
            nome: nomeDe(maisAntigo),
            tempo: tempo(esperaDe(maisAntigo)),
          }),
        t('AGENTS_RODIZIO.SUMMARY.LATE_WHO', { lista: listaDeNomes(pessoas) }),
      ]
        .filter(Boolean)
        .join(' '),
    };
  }
  if (nivel.value === 'amarelo') {
    const n = esperandoNoPrazo.value;
    return {
      titulo: t('AGENTS_RODIZIO.SUMMARY.WARN_TITLE', { n }, n),
      detalhe: t('AGENTS_RODIZIO.SUMMARY.WARN_SUB', { min }),
    };
  }
  return {
    titulo: t('AGENTS_RODIZIO.SUMMARY.OK_TITLE'),
    detalhe: t('AGENTS_RODIZIO.SUMMARY.OK_SUB', { min }),
  };
});

// --- os números do período ---------------------------------------------------------------

const leadsDoRodizio = computed(() => contagem.value.todos || 0);
const mediaEspera = computed(() => props.geral?.media_espera_segundos);

const numeros = computed(() => {
  const min = props.limiar;
  const media = mediaEspera.value;
  return [
    {
      chave: 'distribuidos',
      rotulo: t('AGENTS_RODIZIO.KPI.DISTRIBUTED'),
      dica: t('AGENTS_RODIZIO.KPI.DISTRIBUTED_HINT'),
      valor: props.totais.recebidos || 0,
      apoio: t('AGENTS_RODIZIO.KPI.DISTRIBUTED_SUB', {
        n: props.totais.por_motivo?.rodizio || 0,
      }),
      cor: 'text-n-slate-12',
    },
    {
      chave: 'parados',
      rotulo: t('AGENTS_RODIZIO.KPI.STALLED', { min }),
      dica: t('AGENTS_RODIZIO.KPI.STALLED_HINT', { min }),
      valor: props.parados.total || 0,
      apoio: props.parados.total
        ? t('AGENTS_RODIZIO.KPI.STALLED_SUB')
        : t('AGENTS_RODIZIO.KPI.STALLED_NONE'),
      cor: props.parados.total ? FAIXAS.atrasado.texto : FAIXAS.ok.texto,
    },
    {
      chave: 'media',
      rotulo: t('AGENTS_RODIZIO.KPI.AVG_WAIT'),
      dica: t('AGENTS_RODIZIO.KPI.AVG_WAIT_HINT'),
      valor: media ? tempo(media) : '—',
      apoio: t('AGENTS_RODIZIO.KPI.AVG_WAIT_SUB', { min }),
      cor: media
        ? faixaDaEspera({ segundos: media, limiar: min }).texto
        : 'text-n-slate-12',
    },
    {
      chave: 'repassados',
      rotulo: t('AGENTS_RODIZIO.KPI.PASSED'),
      dica: t('AGENTS_RODIZIO.KPI.PASSED_HINT'),
      valor: contagem.value.repassado || 0,
      apoio: t('AGENTS_RODIZIO.KPI.OF_ROTATION', { n: leadsDoRodizio.value }),
      cor: contagem.value.repassado ? FAIXAS.atrasado.texto : 'text-n-slate-12',
    },
  ];
});
</script>

<template>
  <section class="flex flex-col gap-4">
    <div
      class="flex flex-col gap-3 p-4 border rounded-xl"
      :class="NIVEIS[nivel].caixa"
    >
      <div class="flex items-start gap-3">
        <span
          class="flex items-center justify-center rounded-full size-9 shrink-0"
          :class="NIVEIS[nivel].selo"
        >
          <span class="size-5" :class="NIVEIS[nivel].icone" />
        </span>
        <div class="flex flex-col flex-1 min-w-0 gap-0.5">
          <h2 class="m-0 text-base font-semibold text-n-slate-12">
            {{ frase.titulo }}
          </h2>
          <p class="m-0 text-sm text-n-slate-11">{{ frase.detalhe }}</p>
        </div>
        <button
          v-if="nivel !== 'verde'"
          class="items-center hidden h-8 gap-1 px-3 text-sm font-medium bg-white border rounded-lg sm:inline-flex shrink-0 dark:bg-n-solid-3 border-n-weak text-n-slate-12 hover:bg-n-slate-2"
          @click="emit('verEsperando')"
        >
          {{ t('AGENTS_RODIZIO.SUMMARY.SEE_WAITING') }}
          <span class="i-lucide-arrow-down size-4" />
        </button>
      </div>

      <!-- A lista de ação: um lead por linha, do que espera há mais tempo para o mais recente. -->
      <ul
        v-if="naLista.length"
        class="flex flex-col p-0 m-0 overflow-hidden list-none bg-white border divide-y rounded-lg dark:bg-n-solid-2 border-n-weak divide-n-weak"
      >
        <li
          v-for="lead in naLista"
          :key="lead.conversation_id"
          class="flex flex-wrap items-center px-3 py-2 gap-x-3 gap-y-1"
        >
          <span
            class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-semibold rounded-full whitespace-nowrap tabular-nums"
            :class="FAIXAS.atrasado.selo"
          >
            <span class="i-lucide-clock size-3" />
            {{
              t('AGENTS_RODIZIO.SUMMARY.WAITING_FOR', {
                tempo: tempo(esperaDe(lead)),
              })
            }}
          </span>
          <span class="min-w-0 text-sm text-n-slate-12">
            <span class="font-semibold">{{ nomeDe(lead) }}</span>
            <span class="text-n-slate-11">
              {{ t('AGENTS_RODIZIO.SUMMARY.HAS_NOT_TAKEN') }}
            </span>
            <span class="font-medium">
              {{ lead.contato || `#${lead.display_id}` }}
            </span>
          </span>
          <span class="text-xs tabular-nums text-n-slate-10">
            {{
              [`#${lead.display_id}`, lead.produto].filter(Boolean).join(' · ')
            }}
          </span>
          <span class="flex items-center gap-1 ml-auto">
            <button
              class="h-7 px-2 text-xs rounded-md text-n-slate-11 hover:bg-n-slate-3"
              @click="emit('porQue', lead)"
            >
              {{ t('AGENTS_RODIZIO.DETAIL.OPEN') }}
            </button>
            <a
              :href="linkDaConversa(accountId, lead.display_id)"
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center h-7 gap-1 px-2 text-xs font-medium border rounded-md border-n-weak text-n-slate-12 hover:bg-n-slate-3"
            >
              {{ t('AGENTS_RODIZIO.OPEN_CONVERSATION') }}
              <span class="i-lucide-external-link size-3" />
            </a>
          </span>
        </li>
        <li v-if="foraDaLista" class="px-3 py-2">
          <button
            class="text-xs font-medium underline text-n-slate-11 underline-offset-2"
            @click="emit('verEsperando')"
          >
            {{ t('AGENTS_RODIZIO.SUMMARY.MORE', { n: foraDaLista }) }}
          </button>
        </li>
      </ul>
    </div>

    <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
      <div
        v-for="numero in numeros"
        :key="numero.chave"
        class="flex flex-col gap-1 px-4 py-3 bg-white border rounded-xl dark:bg-n-solid-2 border-n-weak"
      >
        <p
          v-tooltip.top="numero.dica"
          class="inline-flex items-center gap-1 m-0 text-xs font-medium text-n-slate-11 w-fit cursor-help"
        >
          {{ numero.rotulo }}
          <span class="i-lucide-info size-3 text-n-slate-9" />
        </p>
        <p
          class="m-0 text-2xl font-semibold leading-tight tabular-nums"
          :class="numero.cor"
        >
          {{ numero.valor }}
        </p>
        <p class="m-0 text-xs text-n-slate-10">{{ numero.apoio }}</p>
      </div>
    </div>
  </section>
</template>
