<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { duracao } from './tempo';
import RodizioLeadCard from './RodizioLeadCard.vue';
import RodizioLegenda from './RodizioLegenda.vue';

// Uma linha por consultor: quantos recebeu, por onde cada lead chegou (barra empilhada, com o
// número exato ao lado) e quantos ele ainda não pegou. Substituiu a tabela de dez colunas, em
// que era preciso somar de cabeça para entender a distribuição.
const props = defineProps({
  linhas: { type: Array, default: () => [] },
  expandido: { type: [Number, String], default: null },
  faixas: { type: Object, default: () => ({}) },
  carregandoFaixa: { type: Boolean, default: false },
  decorrido: { type: Number, default: 0 },
  limiar: { type: Number, default: 30 },
  accountId: { type: [Number, String], required: true },
});

const emit = defineEmits(['alternar']);

const { t } = useI18n();

// As cinco origens, na ordem em que somam "Recebidos". Cores que esta skin de fato separa
// (azul, teal e iris são o MESMO verde aqui): verde, violeta, âmbar, vermelho e cinza.
const ORIGENS = computed(() => [
  {
    chave: 'rodizio',
    motivos: ['rodizio'],
    cor: 'bg-n-teal-9',
    nome: t('AGENTS_RODIZIO.AGENTS.ORIGIN.RODIZIO'),
    dica: t('AGENTS_RODIZIO.AGENTS.ORIGIN.RODIZIO_HINT'),
  },
  {
    chave: 'continuidade',
    motivos: ['continuidade'],
    cor: 'bg-n-violet-9',
    nome: t('AGENTS_RODIZIO.AGENTS.ORIGIN.CONTINUIDADE'),
    dica: t('AGENTS_RODIZIO.AGENTS.ORIGIN.CONTINUIDADE_HINT'),
  },
  {
    chave: 'preferencia',
    motivos: ['preferencia_cliente'],
    cor: 'bg-n-amber-9',
    nome: t('AGENTS_RODIZIO.AGENTS.ORIGIN.PREFERENCIA'),
    dica: t('AGENTS_RODIZIO.AGENTS.ORIGIN.PREFERENCIA_HINT'),
  },
  {
    chave: 'repasse',
    motivos: ['repasse_sla'],
    cor: 'bg-n-ruby-9',
    nome: t('AGENTS_RODIZIO.AGENTS.ORIGIN.REPASSE'),
    dica: t('AGENTS_RODIZIO.AGENTS.ORIGIN.REPASSE_HINT'),
  },
  {
    chave: 'gestor',
    motivos: ['manual_gestor', 'escalado_gestor'],
    cor: 'bg-n-slate-9',
    nome: t('AGENTS_RODIZIO.AGENTS.ORIGIN.GESTOR'),
    dica: t('AGENTS_RODIZIO.AGENTS.ORIGIN.GESTOR_HINT'),
  },
]);

const maiorRecebido = computed(() =>
  Math.max(...props.linhas.map(linha => linha.recebidos || 0), 1)
);

const origensDe = linha =>
  ORIGENS.value
    .map(origem => ({
      ...origem,
      total: origem.motivos.reduce(
        (soma, motivo) => soma + (linha.motivos?.[motivo] || 0),
        0
      ),
    }))
    .filter(origem => origem.total > 0);

// A barra de cada um é proporcional ao MAIOR do time: dá para comparar quem recebeu mais de
// bater o olho, e os segmentos dentro dela mostram por onde cada lead chegou.
const larguraDaBarra = linha =>
  `${Math.max(((linha.recebidos || 0) / maiorRecebido.value) * 100, 4)}%`;

const larguraDoSegmento = (origem, linha) =>
  `${(origem.total / Math.max(linha.recebidos || 0, 1)) * 100}%`;

const resumoDe = mapa =>
  Object.entries(mapa || {})
    .map(([nome, total]) => `${nome} ${total}`)
    .join(' · ');

const faixaDe = userId => props.faixas[userId] || { leads: [], total: 0 };
const leadsDe = userId => faixaDe(userId).leads || [];
const restantesDe = userId =>
  Math.max((faixaDe(userId).total || 0) - leadsDe(userId).length, 0);
const mediaDe = userId => {
  const segundos = faixaDe(userId).media_espera_segundos;
  return segundos ? duracao(t, segundos) : '';
};
</script>

<template>
  <section class="flex flex-col gap-3">
    <div class="flex flex-wrap items-center justify-between gap-2">
      <p class="m-0 text-sm font-medium text-n-slate-12">
        {{ t('AGENTS_RODIZIO.AGENTS.TITLE') }}
      </p>
      <!-- Legenda das origens, cada termo com a explicação no balão. -->
      <div
        class="flex flex-wrap items-center text-xs gap-x-3 gap-y-1 text-n-slate-11"
      >
        <span
          v-for="origem in ORIGENS"
          :key="origem.chave"
          v-tooltip.top="origem.dica"
          class="inline-flex items-center gap-1.5 cursor-help"
        >
          <span class="rounded-sm size-2.5" :class="origem.cor" />
          {{ origem.nome }}
          <span class="i-lucide-info size-3 text-n-slate-9" />
        </span>
      </div>
    </div>

    <p
      v-if="!linhas.length"
      class="px-4 py-8 m-0 text-sm text-center border rounded-xl border-n-weak text-n-slate-10"
    >
      {{ t('AGENTS_RODIZIO.EMPTY') }}
    </p>

    <ul
      v-else
      class="flex flex-col p-0 m-0 overflow-hidden list-none bg-white border divide-y rounded-xl dark:bg-n-solid-2 border-n-weak divide-n-weak"
    >
      <li v-for="linha in linhas" :key="linha.user_id">
        <button
          class="grid items-center w-full grid-cols-1 px-4 py-3 text-left md:grid-cols-[minmax(0,13rem)_minmax(0,1fr)_auto] gap-x-5 gap-y-2 hover:bg-n-slate-2 dark:hover:bg-n-solid-3"
          :aria-expanded="expandido === linha.user_id"
          @click="emit('alternar', linha)"
        >
          <span class="flex items-center min-w-0 gap-2">
            <span
              class="transition-transform duration-200 i-lucide-chevron-right size-4 shrink-0 text-n-slate-10"
              :class="{ 'rotate-90': expandido === linha.user_id }"
            />
            <span class="text-sm font-semibold truncate text-n-slate-12">
              {{ linha.nome || linha.user_id }}
            </span>
          </span>

          <span class="flex flex-col min-w-0 gap-1.5">
            <span
              class="flex h-2.5 overflow-hidden rounded-full bg-n-slate-3"
              :style="{ width: larguraDaBarra(linha) }"
            >
              <span
                v-for="origem in origensDe(linha)"
                :key="origem.chave"
                v-tooltip.top="`${origem.nome}: ${origem.total}`"
                class="h-full"
                :class="origem.cor"
                :style="{ width: larguraDoSegmento(origem, linha) }"
              />
            </span>
            <span
              class="flex flex-wrap text-xs gap-x-3 gap-y-0.5 text-n-slate-11 tabular-nums"
            >
              <span
                v-for="origem in origensDe(linha)"
                :key="origem.chave"
                class="inline-flex items-center gap-1"
              >
                <span class="rounded-sm size-2" :class="origem.cor" />
                {{ origem.total }} {{ origem.nome.toLowerCase() }}
              </span>
            </span>
          </span>

          <span class="flex items-center gap-3 md:justify-end">
            <span
              class="text-sm tabular-nums text-n-slate-11 whitespace-nowrap"
            >
              <span class="text-lg font-semibold text-n-slate-12">
                {{ linha.recebidos }}
              </span>
              {{ t('AGENTS_RODIZIO.AGENTS.RECEIVED', linha.recebidos) }}
            </span>
            <span
              v-tooltip.top="t('AGENTS_RODIZIO.AGENTS.OPEN_HINT')"
              class="px-2 py-0.5 text-xs font-medium rounded-full whitespace-nowrap tabular-nums"
              :class="
                linha.abertos
                  ? 'bg-n-amber-3 text-n-amber-11'
                  : 'bg-n-slate-3 text-n-slate-10'
              "
            >
              {{
                linha.abertos
                  ? t(
                      'AGENTS_RODIZIO.AGENTS.OPEN',
                      { n: linha.abertos },
                      linha.abertos
                    )
                  : t('AGENTS_RODIZIO.AGENTS.OPEN_NONE')
              }}
            </span>
          </span>
        </button>

        <!-- Os leads que passaram por esta pessoa, com o mesmo cartão da linha do tempo. -->
        <div
          v-if="expandido === linha.user_id"
          class="flex flex-col gap-3 px-4 py-4 border-t bg-n-slate-2 dark:bg-n-solid-1 border-n-weak"
        >
          <div
            class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1"
          >
            <p class="m-0 text-sm font-medium text-n-slate-12">
              {{
                t('AGENTS_RODIZIO.TIMELINE.TITLE', {
                  nome: linha.nome || linha.user_id,
                })
              }}
            </p>
            <p
              v-if="mediaDe(linha.user_id)"
              class="m-0 text-xs text-n-slate-11"
            >
              {{
                t('AGENTS_RODIZIO.TIMELINE.AVG_WAIT', {
                  tempo: mediaDe(linha.user_id),
                })
              }}
            </p>
          </div>
          <p class="m-0 text-xs text-n-slate-10">
            {{
              t('AGENTS_RODIZIO.AGENTS.CHANNELS_PRODUCTS', {
                canais: resumoDe(linha.canais) || '—',
                produtos: resumoDe(linha.produtos) || '—',
              })
            }}
          </p>

          <p v-if="carregandoFaixa" class="m-0 text-sm text-n-slate-10">
            {{ t('AGENTS_RODIZIO.LOADING') }}
          </p>
          <p
            v-else-if="!leadsDe(linha.user_id).length"
            class="m-0 text-sm text-n-slate-10"
          >
            {{ t('AGENTS_RODIZIO.TIMELINE.EMPTY') }}
          </p>
          <template v-else>
            <RodizioLegenda :limiar="limiar" />
            <RodizioLeadCard
              v-for="lead in leadsDe(linha.user_id)"
              :key="lead.id"
              :lead="lead"
              :decorrido="decorrido"
              :limiar="limiar"
              :account-id="accountId"
            />
            <p
              v-if="restantesDe(linha.user_id)"
              class="m-0 text-xs text-n-slate-10"
            >
              {{
                t('AGENTS_RODIZIO.TIMELINE.SHOWING', {
                  n: leadsDe(linha.user_id).length,
                  total: faixaDe(linha.user_id).total,
                })
              }}
            </p>
          </template>
        </div>
      </li>
    </ul>
  </section>
</template>
