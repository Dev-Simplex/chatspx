<script setup>
import { useRoute } from 'vue-router';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { duracao, instante } from './tempo';

const props = defineProps({
  // Um lead serializado pelo LinhaDoTempoService: marcos, fases, situação e desfecho.
  lead: { type: Object, required: true },
  // Segundos que valem 100% da barra. Vem de fora porque TODAS as barras da lista dividem a
  // mesma escala — é o que deixa comparar um lead com o outro de bater o olho.
  escala: { type: Number, default: 1 },
  // Segundos desde que a resposta chegou do servidor. A fase aberta continua correndo na tela
  // entre uma recarga e outra: o lead que espera há 38 min não pode ficar parado em 38 min.
  decorrido: { type: Number, default: 0 },
});
const route = useRoute();
// O lead abre a conversa dele (antes o #id era so texto).
const conversaUrl = computed(
  () =>
    `/app/accounts/${route.params.accountId}/conversations/${props.lead.display_id}`
);

const { t } = useI18n();

// Ordem dos blocos na barra, a cor e o nome de cada um. Computed, e não constante solta, porque
// o nome é traduzido — e a chave fica escrita por extenso: chave montada em runtime já sumiu de
// tela neste projeto e o lint reclama dela com razão.
//
// Sobre as cores: nesta skin de WhatsApp o `blue` e o `teal` foram sobrescritos para o MESMO
// verde (idênticos no tema escuro), então azul não separa fase nenhuma — a da IA passou a ser
// cinza. Os nomes e tempos ficam fora da barra, ao lado de uma bolinha da mesma cor.
const FASES = computed(() => [
  {
    chave: 'ia',
    classe: 'bg-n-slate-9',
    nome: t('AGENTS_RODIZIO.TIMELINE.PHASE.IA'),
  },
  {
    chave: 'espera',
    classe: 'bg-n-amber-9',
    nome: t('AGENTS_RODIZIO.TIMELINE.PHASE.ESPERA'),
  },
  {
    chave: 'atendimento',
    classe: 'bg-n-teal-9',
    nome: t('AGENTS_RODIZIO.TIMELINE.PHASE.ATENDIMENTO'),
  },
]);
const PERDIDO = 'bg-n-ruby-9';

const conversa = id => `#${id}`;

// O que ainda corre: espera de quem ninguém pegou, atendimento de quem não terminou. Lead
// encerrado não anda mais, e somar o relógio nele seria mentira.
const emAndamento = computed(() => props.lead.situacao !== 'encerrado');

const decorridoDa = chave =>
  emAndamento.value && props.lead.situacao === chave ? props.decorrido : 0;

const fasesVivas = computed(() => ({
  ia: props.lead.fases?.ia || 0,
  espera: (props.lead.fases?.espera || 0) + decorridoDa('espera'),
  atendimento:
    (props.lead.fases?.atendimento || 0) + decorridoDa('atendimento'),
}));

const totalVivo = computed(
  () =>
    (props.lead.total_segundos || 0) + (emAndamento.value ? props.decorrido : 0)
);

const naSituacaoHa = computed(
  () =>
    (props.lead.segundos_na_situacao || 0) +
    (emAndamento.value ? props.decorrido : 0)
);
const tempo = segundos => duracao(t, segundos);
const proporcao = (parte, todo) => (todo > 0 ? ((parte || 0) / todo) * 100 : 0);

const inicial = computed(() =>
  (props.lead.contato || props.lead.telefone || '#')
    .trim()
    .charAt(0)
    .toUpperCase()
);

// Quem é o lead. O nome do contato manda; sem nome, o número; sem os dois, o #id da conversa.
const titulo = computed(
  () =>
    props.lead.contato || props.lead.telefone || conversa(props.lead.display_id)
);

// "+55 11 98888-7777 · #4821 · WhatsApp · Apto 2 dorm" — montado aqui porque texto solto no
// template é erro de lint no projeto.
const contexto = computed(() =>
  [
    props.lead.contato ? props.lead.telefone : null,
    conversa(props.lead.display_id),
    props.lead.canal,
    props.lead.produto,
  ]
    .filter(Boolean)
    .join(' · ')
);

// --- onde o lead está AGORA -------------------------------------------------------
//
// O selo é a resposta às três perguntas de quem acompanha: com quem está, em que pé, e há
// quanto tempo. A situação vem do backend (mesma regra que ORDENA a lista), para o selo e a
// ordem nunca discordarem.
const AGORA = {
  espera: {
    chave: 'WAITING_WITH',
    classe: 'bg-n-amber-3 text-n-amber-11',
  },
  atendimento: {
    chave: 'IN_SERVICE_WITH',
    classe: 'bg-n-teal-3 text-n-teal-11',
  },
};

const agora = computed(() => AGORA[props.lead.situacao] || null);

const selo = computed(() => {
  if (!agora.value) return '';
  const nome = props.lead.corretor || t('AGENTS_RODIZIO.TIMELINE.AI_SHORT');
  return props.lead.situacao === 'espera'
    ? t('AGENTS_RODIZIO.TIMELINE.NOW.WAITING_WITH', {
        nome,
        tempo: tempo(naSituacaoHa.value),
      })
    : t('AGENTS_RODIZIO.TIMELINE.NOW.IN_SERVICE_WITH', {
        nome,
        tempo: tempo(naSituacaoHa.value),
      });
});

// Lead encerrado não tem selo: quem conta o fim é o desfecho, e ele precisa dizer de quem era.
const desfecho = computed(() => {
  const nome = props.lead.corretor || t('AGENTS_RODIZIO.TIMELINE.AI_SHORT');
  if (props.lead.perdido_em) {
    return props.lead.repassado_para
      ? t('AGENTS_RODIZIO.TIMELINE.OUTCOME.PASSED', {
          nome,
          destino: props.lead.repassado_para,
        })
      : t('AGENTS_RODIZIO.TIMELINE.OUTCOME.EXPIRED', { nome });
  }
  return t('AGENTS_RODIZIO.TIMELINE.OUTCOME.RESOLVED', {
    nome,
    tempo: tempo(props.lead.total_segundos),
  });
});

const corDesfecho = computed(() =>
  props.lead.perdido_em ? 'text-n-ruby-11' : 'text-n-teal-11'
);

// --- a barra ----------------------------------------------------------------------

// Quem estava com o lead naquele trecho: antes da designação é a IA, depois é o corretor. Só o
// primeiro nome, porque o bloco é estreito.
const dono = fase =>
  fase === 'ia'
    ? t('AGENTS_RODIZIO.TIMELINE.AI_SHORT')
    : (props.lead.corretor || '').split(' ')[0] ||
      t('AGENTS_RODIZIO.TIMELINE.AI_SHORT');

const fases = computed(() =>
  FASES.value
    .filter(fase => (fasesVivas.value[fase.chave] || 0) > 0)
    .map(fase => {
      const segundos = fasesVivas.value[fase.chave];
      // Espera que terminou sem ninguém pegar é o defeito que a tela existe para mostrar.
      const perdeu = fase.chave === 'espera' && props.lead.perdido_em;
      const duracaoDoBloco = tempo(segundos);
      return {
        chave: fase.chave,
        classe: perdeu ? PERDIDO : fase.classe,
        largura: `${proporcao(segundos, totalVivo.value)}%`,
        nome: fase.nome,
        duracao: duracaoDoBloco,
        titulo: `${fase.nome} · ${dono(fase.chave)} · ${duracaoDoBloco}`,
      };
    })
);

// A barra nunca passa de 100%: um lead de quatro dias ao lado de um de dez minutos achatava
// todos os outros em um fio. Quem passa da escala fica cheio, e o total em texto ao lado conta
// a verdade — a barra compara, o número mede.
const largura = computed(
  () => `${Math.min(100, proporcao(totalVivo.value, props.escala))}%`
);

const total = computed(() => tempo(totalVivo.value));

// Um marco por instante gravado, na ordem em que aconteceram. O que não existe some da linha:
// lead que ninguém pegou não tem "pegou", e lead aberto não tem "resolvido".
const marcos = computed(() =>
  [
    ['chegou_em', hora => t('AGENTS_RODIZIO.TIMELINE.MARK.ARRIVED', { hora })],
    [
      'designado_em',
      hora => t('AGENTS_RODIZIO.TIMELINE.MARK.DESIGNATED', { hora }),
    ],
    ['assumido_em', hora => t('AGENTS_RODIZIO.TIMELINE.MARK.TAKEN', { hora })],
    [
      'primeira_resposta_em',
      hora => t('AGENTS_RODIZIO.TIMELINE.MARK.FIRST_REPLY', { hora }),
    ],
    ['perdido_em', hora => t('AGENTS_RODIZIO.TIMELINE.MARK.LOST', { hora })],
    [
      'resolvido_em',
      hora => t('AGENTS_RODIZIO.TIMELINE.MARK.RESOLVED', { hora }),
    ],
  ]
    .filter(([campo]) => props.lead[campo])
    .map(([campo, texto]) => ({
      chave: campo,
      texto: texto(instante(props.lead[campo])),
    }))
);
</script>

<template>
  <article
    class="flex flex-col gap-3 p-4 border rounded-2xl border-n-weak bg-n-solid-1/70 dark:bg-n-solid-3/60"
  >
    <header class="flex flex-wrap items-center gap-3">
      <span
        class="flex items-center justify-center text-sm font-semibold rounded-full size-9 shrink-0 bg-n-alpha-2 text-n-slate-12"
      >
        {{ inicial }}
      </span>
      <div class="flex flex-col min-w-0 flex-1">
        <span class="text-sm font-semibold truncate text-n-slate-12">
          {{ titulo }}
        </span>
        <span class="text-xs truncate tabular-nums text-n-slate-10">
          {{ contexto }}
        </span>
      </div>
      <span
        v-if="agora"
        class="px-2.5 py-1 text-xs font-medium rounded-full whitespace-nowrap tabular-nums"
        :class="agora.classe"
      >
        {{ selo }}
      </span>
      <span
        v-else
        class="text-xs font-medium whitespace-nowrap"
        :class="corDesfecho"
      >
        {{ desfecho }}
      </span>
      <a
        :href="conversaUrl"
        target="_blank"
        rel="noopener noreferrer"
        class="flex items-center gap-1 px-2.5 h-7 text-xs font-semibold rounded-lg no-underline text-n-slate-12 bg-n-alpha-2 hover:bg-n-alpha-3"
      >
        {{ t('AGENTS_RODIZIO.OPEN_CONVERSATION') }}
        <span class="i-lucide-arrow-up-right size-3.5" />
      </a>
    </header>

    <!-- A trilha ocupa a linha toda e a parte cheia segue a escala comum da lista: o
         comprimento compara um lead com o outro, o total ao lado mede. -->
    <div class="flex items-center gap-3">
      <div class="flex-1 h-2 overflow-hidden rounded-full bg-n-alpha-2">
        <div class="flex h-full" :style="{ width: largura }">
          <!-- `v-tooltip` (floating-vue, global no dashboard): o balão nativo demora e ignora o tema. -->
          <div
            v-for="fase in fases"
            :key="fase.chave"
            v-tooltip.top="fase.titulo"
            class="h-full min-w-[3px]"
            :class="fase.classe"
            :style="{ width: fase.largura }"
          />
        </div>
      </div>
      <span
        class="text-sm font-semibold whitespace-nowrap tabular-nums text-n-slate-12"
      >
        {{ total }}
      </span>
    </div>

    <div
      class="flex flex-wrap items-center text-xs gap-x-4 gap-y-1 tabular-nums text-n-slate-11"
    >
      <span
        v-for="fase in fases"
        :key="fase.chave"
        class="inline-flex items-center gap-1.5"
      >
        <span class="rounded-full size-2" :class="fase.classe" />
        {{ fase.nome }}
        <span class="font-medium text-n-slate-12">{{ fase.duracao }}</span>
      </span>
    </div>

    <ol
      class="flex flex-wrap items-center p-0 m-0 text-xs list-none gap-x-1.5 gap-y-1 tabular-nums text-n-slate-10"
    >
      <li
        v-for="(marco, i) in marcos"
        :key="marco.chave"
        class="inline-flex items-center gap-1.5"
      >
        <span
          v-if="i > 0"
          class="i-lucide-chevron-right size-3 text-n-slate-9"
        />
        {{ marco.texto }}
      </li>
    </ol>
  </article>
</template>
