<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import DistribuicaoDashboardAPI from 'dashboard/api/distribuicaoDashboard';
import DownloadPdfButton from 'dashboard/components/reports/DownloadPdfButton.vue';
import RodizioLeadCard from './rodizio/RodizioLeadCard.vue';
import RodizioLegenda from './rodizio/RodizioLegenda.vue';
import RodizioResumo from './rodizio/RodizioResumo.vue';
import RodizioPorConsultor from './rodizio/RodizioPorConsultor.vue';
import { duracao, instante } from './rodizio/tempo';

defineOptions({ name: 'RodizioPage' });

const { t, locale } = useI18n();
const router = useRouter();
const { accountId } = useAccount();

const loading = ref(true);
const loadError = ref(false);
const data = ref(null);
const teamId = ref('');
const detalhe = ref(null);
const detalheLoading = ref(false);
const expandido = ref(null);
const timelines = ref({});
const timelineLoading = ref(false);
// A linha do tempo dos leads abre primeiro: é o que se quer ver sem clicar em nada.
const aba = ref('leads');
const secaoDasAbas = ref(null);
// Relógio da tela. A resposta do backend é uma FOTOGRAFIA: o tempo de espera é calculado no
// instante do request e congelava ali. `agora` faz os tempos abertos correrem entre uma recarga
// e outra; o contador da página em si não vai para a tela (seria ruído piscando).
const agora = ref(new Date());
const atualizadoEm = ref(null);
let relogio = null;
let recarga = null;

// Segundos desde a última resposta — é o que se soma à fase aberta de cada lead.
const decorrido = computed(() =>
  atualizadoEm.value
    ? Math.max(Math.round((agora.value - atualizadoEm.value) / 1000), 0)
    : 0
);

const leadsGerais = ref(null);
const leadsLoading = ref(false);
// Filtros da linha do tempo: situação e consultor. Vão ao backend, porque a contagem é do
// período inteiro, não só dos leads que cabem na tela.
const PASSO_LEADS = 50;
const filtroSituacao = ref('');
const filtroConsultor = ref('');
const limiteLeads = ref(PASSO_LEADS);

const abas = computed(() => [
  {
    value: 'leads',
    icone: 'i-lucide-route',
    label: t('AGENTS_RODIZIO.TABS.BY_LEAD'),
  },
  {
    value: 'consultores',
    icone: 'i-lucide-users',
    label: t('AGENTS_RODIZIO.TABS.BY_AGENT'),
  },
]);

// ------------------------------------------------------------------------ período

const periodo = ref('mes');
// Último preset escolhido, para "Escolher datas" nascer com esse intervalo em vez de vazio.
let periodoAnterior = 'mes';
const de = ref('');
const ate = ref('');

const periodos = computed(() => [
  { value: 'mes', label: t('AGENTS_RODIZIO.PERIOD.MONTH') },
  { value: 'mes_passado', label: t('AGENTS_RODIZIO.PERIOD.LAST_MONTH') },
  { value: 'dias_7', label: t('AGENTS_RODIZIO.PERIOD.DAYS_7') },
  { value: 'dias_30', label: t('AGENTS_RODIZIO.PERIOD.DAYS_30') },
  { value: 'personalizado', label: t('AGENTS_RODIZIO.PERIOD.CUSTOM') },
]);

const comoISO = quando =>
  `${quando.getFullYear()}-${String(quando.getMonth() + 1).padStart(2, '0')}-${String(quando.getDate()).padStart(2, '0')}`;

const diasAtras = n => {
  const quando = new Date();
  quando.setDate(quando.getDate() - n);
  return quando;
};

const INTERVALOS = {
  mes: () => {
    const hoje = new Date();
    return [
      new Date(hoje.getFullYear(), hoje.getMonth(), 1),
      new Date(hoje.getFullYear(), hoje.getMonth() + 1, 0),
    ];
  },
  mes_passado: () => {
    const hoje = new Date();
    return [
      new Date(hoje.getFullYear(), hoje.getMonth() - 1, 1),
      new Date(hoje.getFullYear(), hoje.getMonth(), 0),
    ];
  },
  dias_7: () => [diasAtras(6), new Date()],
  dias_30: () => [diasAtras(29), new Date()],
};

// O fim do dia vai junto no `ate`: o backend compara `created_at` contra o INSTANTE, e uma data
// solta vira meia-noite — o lead de hoje ficaria de fora do próprio período.
const parametros = () => {
  const params = teamId.value ? { team_id: teamId.value } : {};
  const [inicio, fim] =
    periodo.value === 'personalizado'
      ? [de.value, ate.value]
      : INTERVALOS[periodo.value]().map(comoISO);

  return inicio && fim
    ? { ...params, de: inicio, ate: `${fim}T23:59:59` }
    : params;
};

const carregarLeads = async () => {
  leadsLoading.value = !leadsGerais.value;
  try {
    const { data: payload } = await DistribuicaoDashboardAPI.leads({
      ...parametros(),
      situacao: filtroSituacao.value || undefined,
      user_id: filtroConsultor.value || undefined,
      limite: limiteLeads.value,
    });
    leadsGerais.value = payload;
  } catch (e) {
    leadsGerais.value = { leads: [], total: 0 };
  } finally {
    leadsLoading.value = false;
  }
};

const carregar = async () => {
  // Só a PRIMEIRA carga mostra "carregando": trocar o conteúdo por uma linha de texto desmonta
  // a lista e a rolagem volta ao topo a cada recarga.
  loading.value = !data.value;
  loadError.value = false;
  detalhe.value = null;
  // Trocar de time ou de período muda quais leads contam: o que estava aberto vira mentira.
  expandido.value = null;
  timelines.value = {};
  try {
    const { data: payload } = await DistribuicaoDashboardAPI.show(parametros());
    data.value = payload;
    atualizadoEm.value = new Date();
  } catch (e) {
    loadError.value = true;
  } finally {
    loading.value = false;
  }
  // Sempre: os números do topo saem desta resposta, qualquer que seja a aba aberta.
  carregarLeads();
};

// Sempre reconsulta; o guardado serve só para a faixa não piscar "carregando".
const buscarFaixa = async userId => {
  timelineLoading.value = !timelines.value[userId];
  try {
    const { data: payload } = await DistribuicaoDashboardAPI.linhaDoTempo(
      userId,
      parametros()
    );
    timelines.value = { ...timelines.value, [userId]: payload };
    atualizadoEm.value = new Date();
  } catch (e) {
    if (!timelines.value[userId]) {
      timelines.value = {
        ...timelines.value,
        [userId]: { leads: [], total: 0 },
      };
    }
  } finally {
    timelineLoading.value = false;
  }
};

// Recarga de fundo, a cada minuto, sem piscar e sem perder período, filtro ou faixa aberta.
// Falha de rede aqui não vira tela de erro: a próxima volta tenta de novo.
const atualizarEmSilencio = async () => {
  if (document.hidden) return;

  try {
    const { data: payload } = await DistribuicaoDashboardAPI.show(parametros());
    data.value = payload;
    atualizadoEm.value = new Date();
    loadError.value = false;
  } catch (e) {
    return;
  }
  carregarLeads();
  if (expandido.value) buscarFaixa(expandido.value);
};

const hoje = comoISO(new Date());

const trocarIntervalo = () => {
  if (de.value && ate.value) carregar();
};

const trocarPeriodo = () => {
  if (periodo.value === 'personalizado') {
    const [inicio, fim] = (INTERVALOS[periodoAnterior] || INTERVALOS.mes)().map(
      comoISO
    );
    de.value = de.value || inicio;
    ate.value = ate.value || fim;
    trocarIntervalo();
    return;
  }
  periodoAnterior = periodo.value;
  carregar();
};

// --- o período e o time, escritos como gente fala ----------------------------------------
//
// "Outubro de 2026 · Todos os times". A data vem do que o BACKEND usou, mas só a parte da data
// ("2026-10-31"): converter o instante para o fuso do navegador mostrava "01/11" no fim do mês.
const idioma = computed(() =>
  String(locale.value || 'pt-BR').replace('_', '-')
);

const dataDoBackend = valor => {
  const [ano, mes, dia] = String(valor).slice(0, 10).split('-').map(Number);
  return new Date(ano, mes - 1, dia);
};

const dataCurta = quando =>
  quando.toLocaleDateString(idioma.value, {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  });

const periodoLegivel = computed(() => {
  const janela = data.value?.periodo;
  if (!janela?.de) return '';
  const inicio = dataDoBackend(janela.de);
  const fim = dataDoBackend(janela.ate);
  if (['mes', 'mes_passado'].includes(periodo.value)) {
    const nome = inicio.toLocaleDateString(idioma.value, {
      month: 'long',
      year: 'numeric',
    });
    return nome.charAt(0).toUpperCase() + nome.slice(1);
  }
  const intervalo = t('AGENTS_RODIZIO.PERIOD.RANGE', {
    de: dataCurta(inicio),
    ate: dataCurta(fim),
  });
  const preset = periodos.value.find(item => item.value === periodo.value);
  return periodo.value === 'personalizado'
    ? intervalo
    : `${preset.label} (${intervalo})`;
});

const times = computed(() => data.value?.times || []);

const timeLegivel = computed(
  () =>
    times.value.find(time => String(time.id) === String(teamId.value))?.name ||
    t('AGENTS_RODIZIO.ALL_TEAMS')
);

onMounted(() => {
  carregar();
  // 10 s move os ponteiros na tela; 60 s vai ao servidor.
  relogio = setInterval(() => {
    agora.value = new Date();
  }, 10000);
  recarga = setInterval(atualizarEmSilencio, 60000);
});

onBeforeUnmount(() => {
  clearInterval(relogio);
  clearInterval(recarga);
});

const linhas = computed(() => data.value?.linhas || []);
const totais = computed(() => data.value?.totais || {});
const parados = computed(
  () => data.value?.sem_movimento || { total: 0, leads: [], limiar_minutos: 0 }
);

// O PDF pede à API exatamente o que a tela pediu (período e time): é a tela no papel.
const filtrosDoPdf = computed(() => parametros());

// O limite que pinta a espera de cada lead: o mesmo do cartão de parados.
const limiar = computed(() => parados.value.limiar_minutos || 30);

const abrirDetalhe = async lead => {
  detalhe.value = { lead, designacoes: [] };
  detalheLoading.value = true;
  try {
    const { data: payload } = await DistribuicaoDashboardAPI.designacoes(
      lead.conversation_id
    );
    detalhe.value = { lead, designacoes: payload.designacoes || [] };
  } catch (e) {
    detalhe.value = { lead, designacoes: [] };
  } finally {
    detalheLoading.value = false;
  }
};

// ------------------------------------------------------------------- por consultor

const alternarConsultor = async linha => {
  if (expandido.value === linha.user_id) {
    expandido.value = null;
    return;
  }
  expandido.value = linha.user_id;
  await buscarFaixa(linha.user_id);
};

// -------------------------------------------------------------- linha do tempo

const leadsDaConta = computed(() => leadsGerais.value?.leads || []);
const geral = computed(() => leadsGerais.value?.geral || {});

const restantesDaConta = computed(() =>
  Math.max((leadsGerais.value?.total || 0) - leadsDaConta.value.length, 0)
);

const mediaEsperaDaConta = computed(() => {
  const segundos = leadsGerais.value?.media_espera_segundos;
  return segundos ? duracao(t, segundos) : '';
});

// Os botões de situação, cada um com quantos leads tem. Esperando + Em atendimento + Resolvidos
// somam "Todos" (o raro lead que expirou sem ninguém pegar só aparece no recorte de baixo).
// "Expirados/repassados" é um recorte por cima delas, por isso vem separado por um traço.
const situacoes = computed(() => {
  const contagem = leadsGerais.value?.contagem || {};
  return [
    {
      value: '',
      label: t('AGENTS_RODIZIO.LEADS.FILTER.TODOS'),
      total: contagem.todos,
    },
    {
      value: 'espera',
      label: t('AGENTS_RODIZIO.LEADS.FILTER.ESPERA'),
      total: contagem.espera,
      ponto: 'bg-n-amber-9',
    },
    {
      value: 'atendimento',
      label: t('AGENTS_RODIZIO.LEADS.FILTER.ATENDIMENTO'),
      total: contagem.atendimento,
      ponto: 'bg-n-slate-9',
    },
    {
      value: 'resolvido',
      label: t('AGENTS_RODIZIO.LEADS.FILTER.RESOLVIDO'),
      total: contagem.resolvido,
      ponto: 'bg-n-teal-9',
    },
  ];
});

const contagemRepassados = computed(
  () => leadsGerais.value?.contagem?.repassado || 0
);

// "Gelson de Paula (4)": quantos leads do período passaram por cada um.
const consultoresDoFiltro = computed(() =>
  (leadsGerais.value?.consultores || []).map(pessoa => ({
    ...pessoa,
    rotulo: `${pessoa.nome} (${pessoa.total})`,
  }))
);

const filtrar = () => {
  limiteLeads.value = PASSO_LEADS;
  carregarLeads();
};

const escolherSituacao = valor => {
  filtroSituacao.value = valor;
  filtrar();
};

const limparFiltros = () => {
  filtroSituacao.value = '';
  filtroConsultor.value = '';
  filtrar();
};

const mostrarMais = () => {
  limiteLeads.value += PASSO_LEADS;
  carregarLeads();
};

// Do resumo do topo direto para os leads que esperam, já filtrados.
const verEsperando = () => {
  aba.value = 'leads';
  filtroConsultor.value = '';
  escolherSituacao('espera');
  secaoDasAbas.value?.scrollIntoView({ behavior: 'smooth', block: 'start' });
};

// Lista vazia diz POR QUE está vazia, e de um jeito que ajuda: "ninguém esperando" é boa notícia.
const VAZIOS = computed(() => ({
  espera: {
    icone: 'i-lucide-party-popper',
    texto: t('AGENTS_RODIZIO.LEADS.EMPTY_BY.ESPERA'),
  },
  atendimento: {
    icone: 'i-lucide-inbox',
    texto: t('AGENTS_RODIZIO.LEADS.EMPTY_BY.ATENDIMENTO'),
  },
  resolvido: {
    icone: 'i-lucide-inbox',
    texto: t('AGENTS_RODIZIO.LEADS.EMPTY_BY.RESOLVIDO'),
  },
  repassado: {
    icone: 'i-lucide-circle-check',
    texto: t('AGENTS_RODIZIO.LEADS.EMPTY_BY.REPASSADO'),
  },
}));

const vazio = computed(() => {
  if (filtroConsultor.value) {
    return {
      icone: 'i-lucide-user-search',
      texto: t('AGENTS_RODIZIO.LEADS.EMPTY_FILTER'),
      limpar: true,
    };
  }
  return (
    VAZIOS.value[filtroSituacao.value] || {
      icone: 'i-lucide-calendar-x',
      texto: t('AGENTS_RODIZIO.LEADS.EMPTY'),
    }
  );
});

// --- "Por que este?" -------------------------------------------------------------
//
// O painel conta, em frases, quem levou, por qual regra, quem concorreu e o que valia na hora.
// O JSON continua ali, fechado, para quem for investigar.
const MOTIVO_DA_ESCOLHA = computed(() => ({
  rodizio: t('AGENTS_RODIZIO.DETAIL.REASON.RODIZIO'),
  continuidade: t('AGENTS_RODIZIO.DETAIL.REASON.CONTINUIDADE'),
  preferencia_cliente: t('AGENTS_RODIZIO.DETAIL.REASON.PREFERENCIA'),
  manual_gestor: t('AGENTS_RODIZIO.DETAIL.REASON.MANUAL'),
  repasse_sla: t('AGENTS_RODIZIO.DETAIL.REASON.REPASSE'),
  escalado_gestor: t('AGENTS_RODIZIO.DETAIL.REASON.ESCALADO'),
  sem_pool: t('AGENTS_RODIZIO.DETAIL.REASON.SEM_POOL'),
  fila: t('AGENTS_RODIZIO.DETAIL.REASON.FILA'),
}));

const SITUACAO_DA_DESIGNACAO = computed(() => ({
  designado: {
    texto: t('AGENTS_RODIZIO.DETAIL.STATUS.DESIGNADO'),
    classe: 'bg-n-amber-3 text-n-amber-11',
  },
  assumido: {
    texto: t('AGENTS_RODIZIO.DETAIL.STATUS.ASSUMIDO'),
    classe: 'bg-n-teal-3 text-n-teal-11',
  },
  engajado: {
    texto: t('AGENTS_RODIZIO.DETAIL.STATUS.ENGAJADO'),
    classe: 'bg-n-teal-3 text-n-teal-11',
  },
  expirado: {
    texto: t('AGENTS_RODIZIO.DETAIL.STATUS.EXPIRADO'),
    classe: 'bg-n-ruby-3 text-n-ruby-11',
  },
  substituido: {
    texto: t('AGENTS_RODIZIO.DETAIL.STATUS.SUBSTITUIDO'),
    classe: 'bg-n-slate-3 text-n-slate-11',
  },
}));

const situacaoDaDesignacao = registro =>
  SITUACAO_DA_DESIGNACAO.value[registro.status] || {
    texto: registro.status || '—',
    classe: 'bg-n-slate-3 text-n-slate-11',
  };

// "escolhida pelo rodízio · casa-condominio · 10/09/2026 às 12:52"
const comoAEscolhaAconteceu = registro =>
  [
    MOTIVO_DA_ESCOLHA.value[registro.motivo] || registro.motivo,
    registro.produto,
    registro.designado_em ? instante(registro.designado_em) : null,
  ]
    .filter(Boolean)
    .join(' · ');

const quemConcorreu = registro => {
  const nomes = registro.candidatos_nomes || registro.candidatos || [];
  return nomes.length ? nomes.join(', ') : '—';
};

// A regra que valia NA HORA, em frases. É para isso que o snapshot existe — e é o que o JSON
// escondia: posse e repasse são o que explica "por que ninguém pegou e nada aconteceu".
const regraEmPalavras = registro => {
  const regra = registro.regra_aplicada || {};
  const repasse = regra.repasse || {};
  const minutos = repasse.sla_minutos;
  const frases = [];

  if (regra.modo_posse === 'designacao') {
    frases.push(t('AGENTS_RODIZIO.DETAIL.RULE.POSSE_DESIGNACAO'));
  } else if (regra.modo_posse === 'assignee') {
    frases.push(t('AGENTS_RODIZIO.DETAIL.RULE.POSSE_ASSIGNEE'));
  }

  if (minutos) {
    frases.push(
      repasse.automatico
        ? t('AGENTS_RODIZIO.DETAIL.RULE.REPASSE_AUTO', { min: minutos })
        : t('AGENTS_RODIZIO.DETAIL.RULE.REPASSE_MANUAL', { min: minutos })
    );
  }

  return frases;
};

const registroTecnico = registro =>
  JSON.stringify(registro.regra_aplicada || {}, null, 2);

// Este painel só CONTA o que já aconteceu. Quem MONTA a política é a tela do time.
const irParaPolitica = () =>
  router.push({
    name: 'settings_teams_list',
    params: { accountId: accountId.value },
  });
</script>

<template>
  <!-- `w-full h-full`: esta tela é filha direta do <main> do Dashboard (flex row,
       overflow-hidden); sem isso encolheria para a largura do conteúdo e não rolaria. -->
  <div class="flex flex-col w-full h-full gap-5 px-6 py-5 overflow-y-auto">
    <header class="flex flex-wrap items-center justify-between gap-x-6 gap-y-3">
      <div class="min-w-0">
        <h1 class="m-0 text-xl font-semibold text-n-slate-12">
          {{ t('AGENTS_RODIZIO.TITLE') }}
        </h1>
        <p
          v-if="periodoLegivel"
          class="inline-flex items-center gap-1.5 m-0 mt-0.5 text-sm text-n-slate-11"
        >
          <span class="i-lucide-calendar size-3.5 text-n-slate-10" />
          <span class="font-medium text-n-slate-12">{{ periodoLegivel }}</span>
          <span class="rounded-full size-1 bg-n-slate-8" />
          {{ timeLegivel }}
        </p>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <!-- Período e time numa caixa só: são as duas perguntas de "o que estou vendo". -->
        <div
          class="flex items-center h-8 bg-white border divide-x rounded-lg dark:bg-n-solid-2 border-n-weak divide-n-weak"
        >
          <!-- `mb-0` e `border-0` matam a margem e a borda que a regra global de `select` traz. -->
          <select
            v-model="periodo"
            :aria-label="t('AGENTS_RODIZIO.PERIOD.LABEL')"
            class="h-full py-0 pl-2 pr-7 mb-0 text-sm bg-transparent border-0 rounded-l-lg w-auto text-n-slate-12"
            @change="trocarPeriodo"
          >
            <option
              v-for="item in periodos"
              :key="item.value"
              :value="item.value"
            >
              {{ item.label }}
            </option>
          </select>
          <select
            v-model="teamId"
            :aria-label="t('AGENTS_RODIZIO.TEAM_LABEL')"
            class="h-full py-0 pl-2 pr-7 mb-0 text-sm bg-transparent border-0 rounded-r-lg w-auto text-n-slate-12"
            @change="carregar"
          >
            <option value="">{{ t('AGENTS_RODIZIO.ALL_TEAMS') }}</option>
            <option v-for="time in times" :key="time.id" :value="time.id">
              {{ time.name }}
            </option>
          </select>
        </div>
        <button
          v-tooltip.top="t('AGENTS_RODIZIO.RELOAD_HINT')"
          :aria-label="t('AGENTS_RODIZIO.RELOAD')"
          class="flex items-center justify-center bg-white border rounded-lg size-8 dark:bg-n-solid-2 border-n-weak text-n-slate-11 hover:text-n-slate-12 hover:bg-n-slate-2"
          @click="carregar"
        >
          <span class="i-lucide-refresh-cw size-4" />
        </button>
        <!-- `shrink-0`: sem ele o botão encolhe na fila do cabeçalho e o texto some. -->
        <DownloadPdfButton
          class="shrink-0"
          report-type="rodizio"
          :filters="filtrosDoPdf"
        />
        <button
          class="inline-flex items-center h-8 gap-1.5 px-2.5 text-sm rounded-lg text-n-slate-11 hover:text-n-slate-12 hover:bg-n-slate-3 whitespace-nowrap"
          @click="irParaPolitica"
        >
          <span class="i-lucide-settings-2 size-4" />
          {{ t('AGENTS_RODIZIO.CONFIGURE') }}
        </button>
      </div>
    </header>

    <!-- Datas próprias em linha separada, com rótulo, limites e o aviso de que falta escolher. -->
    <div
      v-if="periodo === 'personalizado'"
      class="flex flex-wrap items-center justify-end gap-3 px-3 py-2 -mt-2 bg-white border rounded-xl border-n-weak dark:bg-n-solid-2"
    >
      <label class="flex items-center gap-2 m-0 text-sm text-n-slate-11">
        {{ t('AGENTS_RODIZIO.PERIOD.FROM') }}
        <input
          v-model="de"
          type="date"
          :max="ate || hoje"
          class="h-8 px-2 mb-0 text-sm bg-white border rounded-lg dark:bg-n-solid-3 border-n-weak text-n-slate-12"
          @change="trocarIntervalo"
        />
      </label>
      <label class="flex items-center gap-2 m-0 text-sm text-n-slate-11">
        {{ t('AGENTS_RODIZIO.PERIOD.TO') }}
        <input
          v-model="ate"
          type="date"
          :min="de"
          :max="hoje"
          class="h-8 px-2 mb-0 text-sm bg-white border rounded-lg dark:bg-n-solid-3 border-n-weak text-n-slate-12"
          @change="trocarIntervalo"
        />
      </label>
      <span v-if="!de || !ate" class="text-xs text-n-slate-10">
        {{ t('AGENTS_RODIZIO.PERIOD.PICK_BOTH') }}
      </span>
    </div>

    <p v-if="loading" class="m-0 text-sm text-n-slate-11">
      {{ t('AGENTS_RODIZIO.LOADING') }}
    </p>
    <p v-else-if="loadError" class="m-0 text-sm text-n-ruby-11">
      {{ t('AGENTS_RODIZIO.ERROR') }}
    </p>

    <template v-else>
      <RodizioResumo
        :parados="parados"
        :geral="geral"
        :totais="totais"
        :limiar="limiar"
        :decorrido="decorrido"
        :account-id="accountId"
        @ver-esperando="verEsperando"
        @por-que="abrirDetalhe"
      />

      <!-- O "Por que este?" abre logo abaixo da lista que o chamou, e não no pé da página. -->
      <section
        v-if="detalhe"
        class="flex flex-col gap-2 p-4 bg-white border rounded-xl dark:bg-n-solid-2 border-n-weak"
      >
        <div class="flex items-center justify-between">
          <h2 class="text-base font-medium text-n-slate-12">
            {{
              t('AGENTS_RODIZIO.DETAIL.TITLE', { id: detalhe.lead.display_id })
            }}
          </h2>
          <button class="text-sm text-n-slate-11" @click="detalhe = null">
            {{ t('AGENTS_RODIZIO.DETAIL.CLOSE') }}
          </button>
        </div>
        <p v-if="detalheLoading" class="text-sm text-n-slate-10">
          {{ t('AGENTS_RODIZIO.LOADING') }}
        </p>
        <!-- wrapper por causa do v-else: v-else e v-for no MESMO elemento é
             anti-padrão do Vue e dá bug de renderização -->
        <div v-else class="flex flex-col gap-3">
          <div
            v-for="registro in detalhe.designacoes"
            :key="registro.id"
            class="flex flex-col gap-1 pt-2 border-t border-n-weak"
          >
            <div class="flex flex-wrap items-center gap-2">
              <span class="text-sm font-medium text-n-slate-12">
                {{ registro.corretor || t('AGENTS_RODIZIO.DETAIL.NOBODY') }}
              </span>
              <span
                class="px-2 py-0.5 text-xs rounded-full whitespace-nowrap"
                :class="situacaoDaDesignacao(registro).classe"
              >
                {{ situacaoDaDesignacao(registro).texto }}
              </span>
            </div>
            <p class="text-xs text-n-slate-11">
              {{ comoAEscolhaAconteceu(registro) }}
            </p>
            <p class="text-xs text-n-slate-10">
              {{ t('AGENTS_RODIZIO.DETAIL.CANDIDATES') }}
              {{ quemConcorreu(registro) }}
            </p>
            <div v-if="regraEmPalavras(registro).length" class="mt-1">
              <p class="text-xs font-medium text-n-slate-11">
                {{ t('AGENTS_RODIZIO.DETAIL.RULE.TITLE') }}
              </p>
              <ul class="pl-4 m-0 list-disc">
                <li
                  v-for="frase in regraEmPalavras(registro)"
                  :key="frase"
                  class="text-xs text-n-slate-10"
                >
                  {{ frase }}
                </li>
              </ul>
            </div>
            <!-- O JSON não sumiu: virou a gaveta de quem for investigar. Fechado por padrão,
                 porque snapshot de política é linha de log, não resposta de tela. -->
            <details class="mt-1">
              <summary class="text-xs cursor-pointer text-n-slate-10">
                {{ t('AGENTS_RODIZIO.DETAIL.RAW') }}
              </summary>
              <pre
                class="p-2 mt-1 overflow-x-auto text-xs rounded-lg bg-n-solid-1 dark:bg-n-solid-3 text-n-slate-11"
                >{{ registroTecnico(registro) }}</pre
              >
            </details>
          </div>
        </div>
      </section>

      <div
        ref="secaoDasAbas"
        class="flex items-center gap-1 p-1 border rounded-lg bg-n-slate-3 dark:bg-n-solid-2 border-n-weak w-fit scroll-mt-4"
      >
        <button
          v-for="item in abas"
          :key="item.value"
          class="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm rounded-md"
          :class="
            aba === item.value
              ? 'bg-white dark:bg-n-solid-3 text-n-slate-12 font-medium shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="aba = item.value"
        >
          <span class="size-4" :class="item.icone" />
          {{ item.label }}
        </button>
      </div>

      <section v-if="aba === 'leads'" class="flex flex-col gap-3 -mt-1">
        <div class="flex flex-wrap items-baseline justify-between gap-2">
          <p class="m-0 text-sm text-n-slate-11">
            {{ t('AGENTS_RODIZIO.LEADS.TITLE') }}
          </p>
          <p v-if="mediaEsperaDaConta" class="m-0 text-xs text-n-slate-11">
            {{
              t('AGENTS_RODIZIO.TIMELINE.AVG_WAIT', {
                tempo: mediaEsperaDaConta,
              })
            }}
          </p>
        </div>

        <!-- Filtros: situação em botões com a contagem de cada uma, e o consultor ao lado. -->
        <div class="flex flex-wrap items-center gap-2">
          <button
            v-for="item in situacoes"
            :key="item.value"
            class="inline-flex items-center gap-1.5 h-8 px-3 text-sm border rounded-full"
            :class="
              filtroSituacao === item.value
                ? 'bg-n-slate-12 text-n-slate-1 border-n-slate-12 font-medium'
                : 'bg-white dark:bg-n-solid-2 border-n-weak text-n-slate-11 hover:text-n-slate-12'
            "
            @click="escolherSituacao(item.value)"
          >
            <span
              v-if="item.ponto"
              class="rounded-full size-2"
              :class="item.ponto"
            />
            {{ item.label }}
            <span class="text-xs font-semibold tabular-nums">
              {{ item.total || 0 }}
            </span>
          </button>
          <span class="w-px h-5 mx-1 bg-n-slate-6" />
          <button
            v-tooltip.top="t('AGENTS_RODIZIO.LEADS.FILTER.REPASSADO_HINT')"
            class="inline-flex items-center gap-1.5 h-8 px-3 text-sm border rounded-full"
            :class="
              filtroSituacao === 'repassado'
                ? 'bg-n-slate-12 text-n-slate-1 border-n-slate-12 font-medium'
                : 'bg-white dark:bg-n-solid-2 border-n-weak text-n-slate-11 hover:text-n-slate-12'
            "
            @click="escolherSituacao('repassado')"
          >
            <span class="i-lucide-repeat-2 size-3.5" />
            {{ t('AGENTS_RODIZIO.LEADS.FILTER.REPASSADO') }}
            <span class="text-xs font-semibold tabular-nums">
              {{ contagemRepassados }}
            </span>
          </button>
          <select
            v-model="filtroConsultor"
            :aria-label="t('AGENTS_RODIZIO.LEADS.ALL_AGENTS')"
            class="h-8 py-0 pl-3 pr-8 mb-0 ml-auto text-sm bg-white border rounded-full w-auto dark:bg-n-solid-2 border-n-weak text-n-slate-12"
            @change="filtrar"
          >
            <option value="">{{ t('AGENTS_RODIZIO.LEADS.ALL_AGENTS') }}</option>
            <option
              v-for="pessoa in consultoresDoFiltro"
              :key="pessoa.id"
              :value="pessoa.id"
            >
              {{ pessoa.rotulo }}
            </option>
          </select>
        </div>

        <RodizioLegenda :limiar="limiar" />

        <p v-if="leadsLoading" class="m-0 text-sm text-n-slate-10">
          {{ t('AGENTS_RODIZIO.LOADING') }}
        </p>
        <div
          v-else-if="!leadsDaConta.length"
          class="flex flex-col items-center gap-2 px-4 py-10 text-center border border-dashed rounded-xl border-n-weak"
        >
          <span class="size-6 text-n-slate-9" :class="vazio.icone" />
          <p class="m-0 text-sm text-n-slate-11">{{ vazio.texto }}</p>
          <button
            v-if="vazio.limpar"
            class="text-xs font-medium underline text-n-slate-11 underline-offset-2"
            @click="limparFiltros"
          >
            {{ t('AGENTS_RODIZIO.LEADS.CLEAR') }}
          </button>
        </div>
        <template v-else>
          <RodizioLeadCard
            v-for="lead in leadsDaConta"
            :key="lead.id"
            :lead="lead"
            :decorrido="decorrido"
            :limiar="limiar"
            :account-id="accountId"
          />
          <div v-if="restantesDaConta" class="flex items-center gap-3">
            <button
              class="h-8 px-3 text-sm bg-white border rounded-lg dark:bg-n-solid-2 border-n-weak text-n-slate-12 hover:bg-n-slate-2"
              @click="mostrarMais"
            >
              {{ t('AGENTS_RODIZIO.LEADS.MORE') }}
            </button>
            <span class="text-xs text-n-slate-10">
              {{
                t('AGENTS_RODIZIO.TIMELINE.SHOWING', {
                  n: leadsDaConta.length,
                  total: leadsGerais.total,
                })
              }}
            </span>
          </div>
        </template>
      </section>

      <RodizioPorConsultor
        v-else
        class="-mt-1"
        :linhas="linhas"
        :expandido="expandido"
        :faixas="timelines"
        :carregando-faixa="timelineLoading"
        :decorrido="decorrido"
        :limiar="limiar"
        :account-id="accountId"
        @alternar="alternarConsultor"
      />
    </template>
  </div>
</template>
