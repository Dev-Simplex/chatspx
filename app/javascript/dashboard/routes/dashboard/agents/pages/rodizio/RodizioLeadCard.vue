<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useElementSize } from '@vueuse/core';
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

const { t } = useI18n();

// Ordem dos blocos na barra, a cor e o nome de cada um. Computed, e não constante solta, porque
// o nome é traduzido — e a chave fica escrita por extenso: chave montada em runtime já sumiu de
// tela neste projeto e o lint reclama dela com razão.
//
// Sobre as cores: nesta skin de WhatsApp o `blue` e o `teal` foram sobrescritos para o MESMO
// verde (idênticos no tema escuro), então azul não separa fase nenhuma — a da IA passou a ser
// cinza. As quatro usam texto PRETO porque branco reprova em contraste sobre os tons sólidos
// (medido: 1,6 a 3,9), enquanto preto passa em todos (5,4 a 13,3).
const FASES = computed(() => [
  {
    chave: 'ia',
    classe: 'bg-n-slate-9 text-n-black',
    nome: t('AGENTS_RODIZIO.TIMELINE.PHASE.IA'),
  },
  {
    chave: 'espera',
    classe: 'bg-n-amber-9 text-n-black',
    nome: t('AGENTS_RODIZIO.TIMELINE.PHASE.ESPERA'),
  },
  {
    chave: 'atendimento',
    classe: 'bg-n-teal-9 text-n-black',
    nome: t('AGENTS_RODIZIO.TIMELINE.PHASE.ATENDIMENTO'),
  },
]);
const PERDIDO = 'bg-n-ruby-9 text-n-black';

// O rótulo do bloco é decidido em PIXELS, medindo a barra — não em porcentagem dela. A conta em
// porcentagem mentia: 30% de uma barra que ocupa 8% da tela são uns 20 px, e o texto saía
// cortado no meio da palavra ("admi", "ad"). Em tela estreita isso acontecia em quase todo lead.
//
// Dois degraus: cabendo nome e tempo, mostra os dois; cabendo só o tempo, mostra o tempo; não
// cabendo nada, o bloco fica limpo — o tooltip e o total ao lado continuam contando tudo.
const PX_NOME_E_TEMPO = 104;
const PX_SO_TEMPO = 56;

const barra = ref(null);
const { width: larguraDaBarra } = useElementSize(barra);

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
      const largura = proporcao(segundos, totalVivo.value);
      const perdeu = fase.chave === 'espera' && props.lead.perdido_em;
      const pixels = (largura / 100) * larguraDaBarra.value;
      const duracaoDoBloco = tempo(segundos);
      let rotulo = '';
      if (pixels >= PX_NOME_E_TEMPO) {
        rotulo = `${dono(fase.chave)} · ${duracaoDoBloco}`;
      } else if (pixels >= PX_SO_TEMPO) {
        rotulo = duracaoDoBloco;
      }

      return {
        chave: fase.chave,
        // Espera que terminou sem ninguém pegar é o defeito que a tela existe para mostrar.
        classe: perdeu ? PERDIDO : fase.classe,
        largura: `${largura}%`,
        rotulo,
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
  <div
    class="flex flex-col gap-2 p-3 bg-white border rounded-lg dark:bg-n-solid-3 border-n-weak"
  >
    <div class="flex flex-wrap items-baseline justify-between gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ titulo }}
        <span class="text-xs font-normal tabular-nums text-n-slate-10">
          {{ contexto }}
        </span>
      </span>
      <span
        v-if="agora"
        class="px-2 py-0.5 text-xs font-medium rounded-full whitespace-nowrap tabular-nums"
        :class="agora.classe"
      >
        {{ selo }}
      </span>
      <span v-else class="text-xs font-medium" :class="corDesfecho">
        {{ desfecho }}
      </span>
    </div>

    <!-- flex-wrap: em tela estreita o total desce uma linha em vez de espremer a barra. -->
    <div class="flex flex-wrap items-center gap-2">
      <!-- `v-tooltip` (floating-vue, global no dashboard) no lugar do `title`: o balão nativo
           do navegador demora a aparecer e ignora o tema da tela. -->
      <!-- `min-w`: com o teto de 24 h na escala, um lead de dez minutos virava um fio de poucos
           pixels, sem texto nenhum. O piso garante que toda barra caiba pelo menos a duração —
           e o total ao lado desfaz qualquer dúvida de quem é maior. -->
      <div
        ref="barra"
        class="flex h-7 overflow-hidden rounded-md ring-1 ring-inset ring-n-black/10 min-w-[7rem] max-w-full"
        :style="{ width: largura }"
      >
        <div
          v-for="fase in fases"
          :key="fase.chave"
          v-tooltip.top="fase.titulo"
          class="flex items-center px-2 overflow-hidden text-[11px] font-medium tracking-tight tabular-nums whitespace-nowrap min-w-[3px]"
          :class="fase.classe"
          :style="{ width: fase.largura }"
        >
          {{ fase.rotulo }}
        </div>
      </div>
      <span class="text-xs whitespace-nowrap tabular-nums text-n-slate-10">
        {{ total }}
      </span>
    </div>

    <div
      class="flex flex-wrap text-xs tabular-nums gap-x-4 gap-y-1 text-n-slate-10"
    >
      <span v-for="marco in marcos" :key="marco.chave">
        {{ marco.texto }}
      </span>
    </div>
  </div>
</template>
