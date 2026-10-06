<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { duracao, instante } from './tempo';
import { faixaDaEspera, FAIXAS } from './faixa';
import { linkDaConversa } from './conversa';

const props = defineProps({
  // Um lead serializado pelo LinhaDoTempoService: quem é, a situação e os marcos (`eventos`).
  lead: { type: Object, required: true },
  // Segundos desde que a resposta chegou do servidor. O que ainda corre (espera, atendimento)
  // continua correndo na tela entre uma recarga e outra.
  decorrido: { type: Number, default: 0 },
  // Minutos para pegar o lead, o mesmo limite do cartão "Sem movimento". Pinta a espera.
  limiar: { type: Number, default: 30 },
  accountId: { type: [Number, String], required: true },
});

const { t } = useI18n();
const tempo = segundos => duracao(t, segundos);

// O cartão é um rastreio de entrega: uma linha de marcos (chegou → entregue a X → repassado →
// pegou → resolvido), com quem e a hora em cada um e a duração escrita no conector entre eles.
// Substituiu a barra proporcional: um lead parado há um dia virava uma barra toda amarela e
// ninguém sabia o que estava olhando.

const emAberto = computed(() =>
  ['espera', 'atendimento'].includes(props.lead.situacao)
);
const correndo = computed(() => (emAberto.value ? props.decorrido : 0));
const naSituacao = computed(
  () => (props.lead.segundos_na_situacao || 0) + correndo.value
);

const titulo = computed(
  () => props.lead.contato || props.lead.telefone || `#${props.lead.display_id}`
);

// "+55 11 98888-7777 · #4821 · WhatsApp · Apto 2 dorm"
const contexto = computed(() =>
  [
    props.lead.contato ? props.lead.telefone : null,
    `#${props.lead.display_id}`,
    props.lead.canal,
    props.lead.produto,
  ]
    .filter(Boolean)
    .join(' · ')
);

const nomeDe = nome => nome || t('AGENTS_RODIZIO.TIMELINE.AI_SHORT');

// --- a espera, em destaque -------------------------------------------------------------

const espera = computed(
  () =>
    (props.lead.espera_segundos || 0) +
    (props.lead.situacao === 'espera' ? props.decorrido : 0)
);

const faixa = computed(() =>
  faixaDaEspera({
    segundos: espera.value,
    limiar: props.limiar,
    aindaEsperando: props.lead.situacao === 'espera',
    perdido: props.lead.situacao === 'perdido',
  })
);

// Precisa de ação: ninguém pegou e já passou do limite (ou expirou sem ninguém). O cartão ganha
// uma faixa vermelha na borda esquerda, para saltar aos olhos no meio da lista.
const precisaDeAcao = computed(
  () =>
    faixa.value === FAIXAS.atrasado &&
    !props.lead.pegou_em &&
    props.lead.situacao !== 'resolvido'
);

const link = computed(() =>
  linkDaConversa(props.accountId, props.lead.display_id)
);

// --- onde o lead está agora, em palavras -----------------------------------------------

const selo = computed(() => {
  const nome = nomeDe(props.lead.corretor);
  const quanto = tempo(naSituacao.value);
  if (props.lead.situacao === 'espera') {
    return t('AGENTS_RODIZIO.TIMELINE.NOW.WAITING', { nome, tempo: quanto });
  }
  if (props.lead.situacao === 'atendimento') {
    return t('AGENTS_RODIZIO.TIMELINE.NOW.IN_SERVICE', { nome, tempo: quanto });
  }
  if (props.lead.situacao === 'resolvido') {
    return t('AGENTS_RODIZIO.TIMELINE.NOW.RESOLVED', { tempo: quanto });
  }
  return t('AGENTS_RODIZIO.TIMELINE.NOW.LOST', { nome });
});

// --- os marcos ------------------------------------------------------------------------

// Cor do círculo de cada marco: cinza o que é rotina, vermelho o que deu errado (prazo
// estourado), verde o que andou (pegou, respondeu, resolveu).
const TOM = {
  neutro: 'bg-n-slate-3 text-n-slate-11',
  ruim: 'bg-n-ruby-3 text-n-ruby-11',
  bom: 'bg-n-teal-3 text-n-teal-11',
};

const porQue = evento => {
  const nome = nomeDe(evento.de);
  if (evento.status_anterior === 'substituido') {
    return t('AGENTS_RODIZIO.TIMELINE.WHY.SUBSTITUIDO', { nome });
  }
  if (evento.motivo === 'escalado_gestor') {
    return t('AGENTS_RODIZIO.TIMELINE.WHY.ESCALADO', { nome });
  }
  return t('AGENTS_RODIZIO.TIMELINE.WHY.REPASSE', { nome });
};

// As classes de ícone ficam escritas por extenso: o Tailwind só gera o que encontra no código.
const MARCO = {
  chegou: () => ({
    icone: 'i-lucide-message-circle',
    tom: TOM.neutro,
    rotulo: t('AGENTS_RODIZIO.TIMELINE.STEP.ARRIVED'),
  }),
  designado: evento => ({
    icone: 'i-lucide-user-check',
    tom: TOM.neutro,
    rotulo: t('AGENTS_RODIZIO.TIMELINE.STEP.DESIGNATED', {
      nome: nomeDe(evento.quem),
    }),
    detalhe: t('AGENTS_RODIZIO.TIMELINE.WHY.RODIZIO'),
  }),
  repassado: evento => ({
    icone: 'i-lucide-repeat-2',
    tom: TOM.ruim,
    rotulo: t('AGENTS_RODIZIO.TIMELINE.STEP.PASSED', {
      nome: nomeDe(evento.quem),
    }),
    detalhe: porQue(evento),
  }),
  expirou: evento => ({
    icone: 'i-lucide-timer-off',
    tom: TOM.ruim,
    rotulo: t('AGENTS_RODIZIO.TIMELINE.STEP.EXPIRED', {
      nome: nomeDe(evento.quem),
    }),
  }),
  pegou: evento => ({
    icone: 'i-lucide-hand',
    tom: TOM.bom,
    rotulo: t('AGENTS_RODIZIO.TIMELINE.STEP.TAKEN', {
      nome: nomeDe(evento.quem),
    }),
  }),
  respondeu: () => ({
    icone: 'i-lucide-reply',
    tom: TOM.bom,
    rotulo: t('AGENTS_RODIZIO.TIMELINE.STEP.FIRST_REPLY'),
  }),
  resolvido: evento => ({
    icone: 'i-lucide-circle-check',
    tom: TOM.bom,
    rotulo: evento.quem
      ? t('AGENTS_RODIZIO.TIMELINE.STEP.RESOLVED_BY', { nome: evento.quem })
      : t('AGENTS_RODIZIO.TIMELINE.STEP.RESOLVED'),
  }),
};

const segundosEntre = (de, ate) =>
  Math.max(Math.round((new Date(ate) - new Date(de)) / 1000), 0);

// O conector diz o que aconteceu ENTRE dois marcos: antes de alguém ser escolhido a IA cobria;
// depois, o lead esperava alguém pegar; depois de pegar, era atendimento. Só a ESPERA tem cor
// (a da faixa): é a única medida que a tela julga, e cor em tudo vira enfeite.
const CONECTOR = {
  ia: { barra: 'bg-n-slate-6', texto: 'text-n-slate-10', chave: 'IA' },
  espera: null,
  atendimento: {
    barra: 'bg-n-slate-9',
    texto: 'text-n-slate-11',
    chave: 'SERVICE',
  },
  fim: { barra: 'bg-n-slate-6', texto: 'text-n-slate-10', chave: null },
};

const conector = (fase, segundos) => {
  const estilo = CONECTOR[fase] || {
    barra: faixa.value.barra,
    texto: faixa.value.texto,
    chave: 'WAIT',
  };
  const quanto = tempo(segundos);
  return {
    barra: estilo.barra,
    texto: estilo.texto,
    // Rótulos escritos por extenso, um por fase: chave montada em runtime já sumiu de tela aqui.
    rotulo:
      {
        IA: t('AGENTS_RODIZIO.TIMELINE.GAP.IA', { tempo: quanto }),
        WAIT: t('AGENTS_RODIZIO.TIMELINE.GAP.WAIT', { tempo: quanto }),
        SERVICE: t('AGENTS_RODIZIO.TIMELINE.GAP.SERVICE', { tempo: quanto }),
      }[estilo.chave] || quanto,
  };
};

// Em que fase o lead está DEPOIS de cada marco.
const faseDepois = (tipo, faseAtual) => {
  if (tipo === 'chegou') return 'ia';
  if (tipo === 'designado' || tipo === 'repassado') return 'espera';
  if (tipo === 'pegou') return 'atendimento';
  if (tipo === 'expirou' || tipo === 'resolvido') return 'fim';
  return faseAtual;
};

// O marco que ainda não aconteceu, para o lead em aberto: "Falta Gelson pegar". Tracejado,
// porque é o próximo passo, não um fato.
const pendente = computed(() => {
  if (props.lead.situacao === 'espera') {
    return {
      icone: 'i-lucide-hourglass',
      tom: `border border-dashed ${faixa.value.borda} ${faixa.value.texto}`,
      rotulo: t('AGENTS_RODIZIO.TIMELINE.STEP.PENDING_TAKE', {
        nome: nomeDe(props.lead.corretor),
      }),
    };
  }
  if (props.lead.situacao === 'atendimento') {
    return {
      icone: 'i-lucide-circle-check',
      tom: 'border border-dashed border-n-slate-7 text-n-slate-10',
      rotulo: t('AGENTS_RODIZIO.TIMELINE.STEP.PENDING_RESOLVE'),
    };
  }
  return null;
});

// Quanto já corre desde o último marco até agora. Conta pelo relógio do SERVIDOR (o tempo na
// situação que veio na resposta + o que passou desde ela), não pelo do computador de quem olha:
// assim o conector e o selo nunca discordam.
const correndoDesde = ultimo => {
  const inicio = [...(props.lead.eventos || [])]
    .reverse()
    .find(evento =>
      props.lead.situacao === 'espera'
        ? ['designado', 'repassado'].includes(evento.tipo)
        : evento.tipo === 'pegou'
    );
  const jaPassou = inicio ? segundosEntre(inicio.em, ultimo.em) : 0;
  return Math.max(naSituacao.value - jaPassou, 0);
};

const passos = computed(() => {
  const eventos = props.lead.eventos || [];
  let fase = 'ia';
  const lista = eventos.map((evento, indice) => {
    fase = faseDepois(evento.tipo, fase);
    const proximo = eventos[indice + 1];
    let ligacao = null;
    if (proximo) {
      ligacao = conector(fase, segundosEntre(evento.em, proximo.em));
    } else if (pendente.value) {
      ligacao = conector(fase, correndoDesde(evento));
    }
    return {
      chave: `${evento.tipo}-${indice}`,
      ...MARCO[evento.tipo](evento),
      hora: instante(evento.em),
      atual: !proximo,
      conector: ligacao,
    };
  });
  if (pendente.value) {
    lista.push({ chave: 'pendente', ...pendente.value, pendente: true });
  }
  return lista;
});
</script>

<template>
  <!-- O cartão inteiro abre a conversa, em outra aba: quem vigia o rodízio não perde o filtro
       nem a rolagem desta tela. -->
  <a
    :href="link"
    target="_blank"
    rel="noopener noreferrer"
    class="relative flex flex-col gap-2.5 py-2.5 pl-4 pr-3 overflow-hidden no-underline transition-shadow bg-white border rounded-lg group dark:bg-n-solid-2 border-n-weak hover:shadow-md hover:border-n-slate-7"
  >
    <span
      v-if="precisaDeAcao"
      class="absolute inset-y-0 left-0 w-1"
      :class="FAIXAS.atrasado.barra"
    />
    <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
      <span class="min-w-0 text-sm font-semibold text-n-slate-12">
        {{ titulo }}
        <span class="ml-1 text-xs font-normal tabular-nums text-n-slate-10">
          {{ contexto }}
        </span>
        <span
          v-tooltip.top="t('AGENTS_RODIZIO.TIMELINE.OPEN_HINT')"
          class="inline-block ml-1 align-middle transition-opacity opacity-0 i-lucide-external-link size-3.5 text-n-slate-10 group-hover:opacity-100"
        />
      </span>
      <!-- Situação e espera andam juntas: em tela estreita descem de linha as duas, nunca uma só. -->
      <span class="flex flex-wrap items-center justify-end gap-2 ml-auto">
        <span class="text-sm font-medium tabular-nums text-n-slate-12">
          {{ selo }}
        </span>
        <span
          v-tooltip.top="t('AGENTS_RODIZIO.TIMELINE.WAIT_HINT')"
          class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-semibold rounded-full whitespace-nowrap tabular-nums"
          :class="faixa.selo"
        >
          <span class="i-lucide-clock size-3" />
          {{ t('AGENTS_RODIZIO.TIMELINE.WAIT', { tempo: tempo(espera) }) }}
        </span>
      </span>
    </div>

    <!-- Rastreio: vertical em tela estreita, horizontal a partir de 768 px. O `pt-4` reserva o
         espaço do texto que fica sobre o conector na versão horizontal. -->
    <ol class="flex flex-col p-0 m-0 list-none md:flex-row md:pt-4">
      <li
        v-for="passo in passos"
        :key="passo.chave"
        class="flex min-w-0 gap-2 md:flex-col md:gap-1"
        :class="passo.conector ? 'md:flex-1' : 'md:flex-none md:w-40'"
      >
        <div class="flex flex-col items-center shrink-0 md:flex-row">
          <span
            class="flex items-center justify-center rounded-full size-6 shrink-0"
            :class="[passo.tom, { 'ring-2 ring-current': passo.atual }]"
          >
            <span class="size-3.5" :class="passo.icone" />
          </span>
          <div
            v-if="passo.conector"
            class="relative flex-1 w-0.5 min-h-[0.75rem] rounded-full md:w-auto md:h-0.5 md:min-h-0 md:mx-1"
            :class="passo.conector.barra"
          >
            <span
              class="absolute inset-x-0 hidden text-center truncate bottom-1.5 text-[11px] font-medium tabular-nums md:block"
              :class="passo.conector.texto"
            >
              {{ passo.conector.rotulo }}
            </span>
          </div>
        </div>
        <div class="min-w-0 pb-2 md:pb-0 md:pr-2">
          <p
            class="m-0 text-xs leading-4 text-n-slate-12"
            :class="[
              passo.conector ? 'truncate' : 'break-words',
              passo.atual || passo.pendente ? 'font-semibold' : 'font-medium',
            ]"
          >
            {{ passo.rotulo }}
          </p>
          <p
            v-if="passo.hora || passo.detalhe"
            class="m-0 text-[11px] leading-4 truncate tabular-nums text-n-slate-10"
          >
            {{ [passo.hora, passo.detalhe].filter(Boolean).join(' · ') }}
          </p>
          <p
            v-if="passo.conector"
            class="m-0 mt-0.5 text-[11px] font-medium tabular-nums md:hidden"
            :class="passo.conector.texto"
          >
            {{ passo.conector.rotulo }}
          </p>
        </div>
      </li>
    </ol>
  </a>
</template>
