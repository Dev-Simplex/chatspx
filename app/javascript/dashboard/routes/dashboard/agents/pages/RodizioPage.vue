<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import DistribuicaoDashboardAPI from 'dashboard/api/distribuicaoDashboard';
import RodizioLeadCard from './rodizio/RodizioLeadCard.vue';
import RodizioLegenda from './rodizio/RodizioLegenda.vue';
import DownloadPdfButton from 'dashboard/components/reports/DownloadPdfButton.vue';
import { duracao, instante } from './rodizio/tempo';

defineOptions({ name: 'RodizioPage' });

const { t } = useI18n();
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
// A linha do tempo dos leads abre primeiro: é o que se quer ver sem clicar em nada. A tabela
// por consultor continua a uma aba de distância.
const aba = ref('leads');
// Relógio da tela. A resposta do backend é uma FOTOGRAFIA: o tempo de espera é calculado no
// instante do request e congelava ali — numa tela feita para vigiar lead parado, o número que
// para de crescer é justamente o que interessa. `agora` faz os tempos abertos correrem entre
// uma recarga e outra. `atualizadoEm` não vai para a tela: contador piscando a cada segundo é
// ruído, e o que o usuário quer ver é o tempo do LEAD correndo, não o da página.
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
// Filtros da linha do tempo: situação (um dos botões com contagem) e consultor. Vão ao backend,
// porque a contagem é do período inteiro, não só dos leads que cabem na tela.
const PASSO_LEADS = 50;
const filtroSituacao = ref('');
const filtroConsultor = ref('');
const limiteLeads = ref(PASSO_LEADS);

const abas = computed(() => [
  { value: 'leads', label: t('AGENTS_RODIZIO.TABS.BY_LEAD') },
  { value: 'consultores', label: t('AGENTS_RODIZIO.TABS.BY_AGENT') },
]);

// ------------------------------------------------------------------------ período
//
// A tela nasceu olhando só o mês corrente e sem dizer que era essa a janela: mês sem movimento
// mostrava "nenhum lead distribuído no período" e ninguém descobria QUAL período. Agora ele é
// escolhido, vai nas TRÊS chamadas (tabela, faixa e leads) e fica escrito no cabeçalho.
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
  // Só a PRIMEIRA carga mostra "carregando". Trocar o conteúdo por uma linha de texto desmonta a
  // tabela, a página encolhe e a rolagem volta ao topo — a cada recarga, no meio da leitura.
  loading.value = !data.value;
  loadError.value = false;
  detalhe.value = null;
  // Trocar de time ou de período muda quais leads contam: o que estava aberto vira mentira.
  expandido.value = null;
  timelines.value = {};
  // `leadsGerais` NÃO é zerado: zerar desmonta a lista e a rolagem vai ao topo. A resposta nova
  // substitui a antiga quando chega, como a tabela já faz.
  try {
    const { data: payload } = await DistribuicaoDashboardAPI.show(parametros());
    data.value = payload;
    atualizadoEm.value = new Date();
  } catch (e) {
    loadError.value = true;
  } finally {
    loading.value = false;
  }
  if (aba.value === 'leads') carregarLeads();
};

// Sempre reconsulta: o dado guardado é de quando a faixa foi aberta, e reabrir o consultor
// mostrava os números de minutos atrás sem nem bater na API. O guardado serve só para a faixa
// não piscar "carregando" enquanto a resposta nova não chega.
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

// Recarga de fundo, a cada minuto: traz lead novo e mudança de status sem piscar a tela, sem
// fechar a faixa aberta e sem perder o período escolhido. Falhou? A tela segue com o que tinha
// e a próxima volta tenta de novo — recarga de fundo não pode transformar uma falha de rede em
// tela de erro.
const atualizarEmSilencio = async () => {
  if (document.hidden) return;

  try {
    const { data: payload } = await DistribuicaoDashboardAPI.show(parametros());
    data.value = payload;
    atualizadoEm.value = new Date();
    // A tela de erro sai sozinha quando a recarga volta a funcionar: sem isto, quem viu a
    // primeira carga falhar ficava preso no aviso mesmo com o dado já na mão.
    loadError.value = false;
  } catch (e) {
    return;
  }
  if (aba.value === 'leads') carregarLeads();
  if (expandido.value) buscarFaixa(expandido.value);
};

// Trocar o preset recarrega na hora; no personalizado só quando as duas pontas existem, senão a
// tela recarregaria a cada dígito digitado na primeira data.
const hoje = comoISO(new Date());

const trocarIntervalo = () => {
  if (de.value && ate.value) carregar();
};

const trocarPeriodo = () => {
  if (periodo.value === 'personalizado') {
    // Entra já preenchido com o intervalo que estava na tela: escolher "datas" não pode começar
    // com dois campos vazios e a tela sem dado.
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

// O período que o backend de fato usou — é ele que vale, não o que a tela pediu.
const periodoLegivel = computed(() => {
  const janela = data.value?.periodo;
  if (!janela?.de) return '';
  const curto = valor =>
    new Date(valor).toLocaleDateString([], {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
    });
  return t('AGENTS_RODIZIO.PERIOD.RANGE', {
    de: curto(janela.de),
    ate: curto(janela.ate),
  });
});

onMounted(() => {
  carregar();
  // 10 s move os ponteiros na tela; 60 s vai ao servidor. Separados porque o relógio é de graça
  // e o request não é.
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
const times = computed(() => data.value?.times || []);
const parados = computed(
  () => data.value?.sem_movimento || { total: 0, leads: [], limiar_minutos: 0 }
);

// O PDF pede à API exatamente o que a tela pediu (período e time): é a tela no papel.
const filtrosDoPdf = computed(() => parametros());

const motivo = (linha, chave) => linha.motivos?.[chave] || 0;

// "WhatsApp 12 · Site 3" — os canais que a gestão já lê na planilha manual.
const canais = linha =>
  Object.entries(linha.canais || {})
    .map(([nome, total]) => `${nome} ${total}`)
    .join(' · ');

const produtos = linha =>
  Object.entries(linha.produtos || {})
    .map(([nome, total]) => `${nome} ${total}`)
    .join(' · ');

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

// Montado aqui, e não no template, porque texto solto em template é erro de lint no projeto —
// nada de string crua fora do i18n. O "#" saiu a pedido: o número do lead se lê sozinho.
const conversa = displayId => `${displayId}`;

// ---------------------------------------------------------------- linha do tempo

// O limite que pinta a espera de cada lead: o mesmo do cartão "Sem movimento".
const limiar = computed(() => parados.value.limiar_minutos || 30);

const timelineDe = userId => timelines.value[userId] || { leads: [], total: 0 };
const leadsDe = userId => timelineDe(userId).leads || [];

// Abre e fecha a faixa. O resultado fica guardado por consultor: reabrir não bate na API de novo.
const alternarConsultor = async linha => {
  if (expandido.value === linha.user_id) {
    expandido.value = null;
    return;
  }
  expandido.value = linha.user_id;
  await buscarFaixa(linha.user_id);
};

// "8399 min esperando" é um número que ninguém lê. Vira "5 d 19h", no mesmo formato do resto da
// tela, e continua correndo com o relógio local — o lead parado é o que mais precisa disso.
const esperaDoParado = lead =>
  duracao(t, (lead.minutos_parado || 0) * 60 + decorrido.value);

const mediaEspera = userId => {
  const segundos = timelineDe(userId).media_espera_segundos;
  return segundos ? duracao(t, segundos) : '';
};

const restantes = userId =>
  Math.max((timelineDe(userId).total || 0) - leadsDe(userId).length, 0);

// ---------------------------------------------------------------------- aba Leads

// A tabela responde "quem recebeu quanto"; esta aba responde "onde está cada lead, com quem, e
// há quanto tempo" — sem precisar adivinhar em quem ele caiu para poder clicar. Do que chegou por
// último para o primeiro; os parados se acham pelo filtro "Esperando".
const leadsDaConta = computed(() => leadsGerais.value?.leads || []);

const restantesDaConta = computed(() =>
  Math.max((leadsGerais.value?.total || 0) - leadsDaConta.value.length, 0)
);

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
    },
    {
      value: 'atendimento',
      label: t('AGENTS_RODIZIO.LEADS.FILTER.ATENDIMENTO'),
      total: contagem.atendimento,
    },
    {
      value: 'resolvido',
      label: t('AGENTS_RODIZIO.LEADS.FILTER.RESOLVIDO'),
      total: contagem.resolvido,
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

const mostrarMais = () => {
  limiteLeads.value += PASSO_LEADS;
  carregarLeads();
};

const mediaEsperaDaConta = computed(() => {
  const segundos = leadsGerais.value?.media_espera_segundos;
  return segundos ? duracao(t, segundos) : '';
});

const irParaAba = valor => {
  aba.value = valor;
  if (valor === 'leads' && !leadsGerais.value) carregarLeads();
};

// --- "Por que este?" -------------------------------------------------------------
//
// O painel mostrava o snapshot da política em JSON cru: linha de log na tela de quem gerencia.
// O que importa ali são quatro respostas — quem levou, por qual regra, quem concorreu e o que
// valia na hora —, e elas viram frase. O JSON continua ali, fechado, para quem for investigar.
//
// Os mapas são computed com a chave escrita por extenso: chave montada em runtime já sumiu de
// tela neste projeto, e o lint reclama dela com razão.
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

// Este painel só CONTA o que já aconteceu. Quem MONTA a política é a tela do time: ela é
// por time, e a lista de times é onde se escolhe qual configurar.
const irParaPolitica = () =>
  router.push({
    name: 'settings_teams_list',
    params: { accountId: accountId.value },
  });
</script>

<template>
  <!-- `w-full h-full` porque esta tela deixou de ser filha do AgentsPageView: agora
       ela e o proprio filho do <main> do Dashboard (flex row, overflow-hidden), e sem
       isso encolheria para a largura do conteudo e nao rolaria. -->
  <div class="flex flex-col w-full h-full gap-6 p-6 overflow-y-auto">
    <header class="flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 class="text-xl font-medium text-n-slate-12">
          {{ t('AGENTS_RODIZIO.TITLE') }}
        </h1>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ t('AGENTS_RODIZIO.SUBTITLE') }}
          <span v-if="periodoLegivel" class="tabular-nums text-n-slate-10">
            {{ periodoLegivel }}
          </span>
        </p>
      </div>
      <div class="flex items-center gap-2">
        <!-- `mb-0` mata o `mb-4` que a regra global de `select` traz pelo `field-base`: com ela a
             caixa sobe metade da margem e desalinha da linha dos botões. -->
        <select
          v-model="periodo"
          class="h-9 px-2 mb-0 text-sm bg-white border rounded-lg dark:bg-n-solid-2 border-n-weak text-n-slate-12"
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
          class="h-9 px-2 mb-0 text-sm bg-white border rounded-lg dark:bg-n-solid-2 border-n-weak text-n-slate-12"
          @change="carregar"
        >
          <option value="">{{ t('AGENTS_RODIZIO.ALL_TEAMS') }}</option>
          <option v-for="time in times" :key="time.id" :value="time.id">
            {{ time.name }} ({{ time.modo_posse }})
          </option>
        </select>
        <button
          class="h-9 px-3 text-sm rounded-lg bg-n-brand text-white transition-shadow hover:shadow-md whitespace-nowrap"
          @click="carregar"
        >
          {{ t('AGENTS_RODIZIO.RELOAD') }}
        </button>
        <DownloadPdfButton report-type="rodizio" :filters="filtrosDoPdf" />
        <button
          class="h-9 px-3 text-sm rounded-lg border border-n-weak text-n-slate-11 whitespace-nowrap"
          @click="irParaPolitica"
        >
          {{ t('AGENTS_RODIZIO.CONFIGURE') }}
        </button>
      </div>
    </header>

    <!-- As duas datas ganham linha própria: espremidas na fila de botões elas ficavam de alturas
         diferentes, sem rótulo, e a segunda aparecia como "dd/mm/aaaa" solto no meio da barra.
         Aqui cabem rótulo, limites (fim nunca antes do início, nada no futuro) e o aviso de que
         falta escolher — e a linha some quando o período não é personalizado. -->
    <div
      v-if="periodo === 'personalizado'"
      class="flex flex-wrap items-center justify-end gap-3 px-3 py-2 -mt-2 border rounded-xl border-n-weak bg-n-solid-1 dark:bg-n-solid-2"
    >
      <label class="flex items-center gap-2 m-0 text-sm text-n-slate-11">
        {{ t('AGENTS_RODIZIO.PERIOD.FROM') }}
        <input
          v-model="de"
          type="date"
          :max="ate || hoje"
          class="h-9 px-2 mb-0 text-sm bg-white border rounded-lg dark:bg-n-solid-3 border-n-weak text-n-slate-12"
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
          class="h-9 px-2 mb-0 text-sm bg-white border rounded-lg dark:bg-n-solid-3 border-n-weak text-n-slate-12"
          @change="trocarIntervalo"
        />
      </label>
      <span v-if="!de || !ate" class="text-xs text-n-slate-10">
        {{ t('AGENTS_RODIZIO.PERIOD.PICK_BOTH') }}
      </span>
    </div>

    <p v-if="loading" class="text-sm text-n-slate-11">
      {{ t('AGENTS_RODIZIO.LOADING') }}
    </p>
    <p v-else-if="loadError" class="text-sm text-n-ruby-11">
      {{ t('AGENTS_RODIZIO.ERROR') }}
    </p>

    <template v-else>
      <section class="flex flex-wrap gap-4">
        <div
          class="px-4 py-2 bg-white border rounded-xl dark:bg-n-solid-2 border-n-weak"
        >
          <p class="text-xs uppercase text-n-slate-10">
            {{ t('AGENTS_RODIZIO.TOTAL_RECEIVED') }}
          </p>
          <p class="text-xl font-medium text-n-slate-12">
            {{ totais.recebidos || 0 }}
          </p>
        </div>
        <div
          class="px-4 py-2 bg-white border rounded-xl dark:bg-n-solid-2 border-n-weak"
        >
          <p class="text-xs uppercase text-n-slate-10">
            {{ t('AGENTS_RODIZIO.STALLED.TITLE') }}
          </p>
          <p class="text-xl font-medium text-n-slate-12">
            {{ parados.total }}
          </p>
          <p class="text-xs text-n-slate-10">
            {{
              t('AGENTS_RODIZIO.STALLED.THRESHOLD', {
                min: parados.limiar_minutos,
              })
            }}
          </p>
        </div>
        <!-- A lista fica ao lado do número, e não abaixo da tabela: lá embaixo ela tirava altura
             da tabela, que é a seção que encolhe quando a tela não cabe. Pelo mesmo motivo é
             baixa: título e explicação numa linha só, e três leads visíveis antes de rolar. -->
        <div
          class="flex flex-col flex-1 min-w-[20rem] gap-1 px-4 py-2 bg-white border rounded-xl dark:bg-n-solid-2 border-n-weak"
        >
          <div class="flex flex-wrap items-baseline gap-x-2">
            <h2 class="text-xs uppercase text-n-slate-10">
              {{ t('AGENTS_RODIZIO.STALLED.LIST_TITLE') }}
            </h2>
            <p class="text-xs text-n-slate-10">
              {{ t('AGENTS_RODIZIO.STALLED.SUBTITLE') }}
            </p>
          </div>
          <p v-if="!parados.leads.length" class="text-sm text-n-slate-10">
            {{ t('AGENTS_RODIZIO.STALLED.NONE') }}
          </p>
          <!-- `bg-n-slate-3` no claro, e não `n-solid-1`: nesta skin o solid-1 claro é branco, igual
               ao cartão, e a linha sem borda sumia no fundo. -->
          <ul v-else class="flex flex-col gap-1 overflow-y-auto max-h-24">
            <li
              v-for="lead in parados.leads"
              :key="lead.conversation_id"
              class="flex flex-wrap items-center gap-3 px-2 py-1 rounded-md bg-n-slate-3 dark:bg-n-solid-3"
            >
              <span class="text-sm font-medium text-n-slate-12">
                {{ lead.corretor || t('AGENTS_RODIZIO.DETAIL.NOBODY') }}
              </span>
              <span
                class="px-2 py-0.5 text-xs rounded-full whitespace-nowrap tabular-nums bg-n-amber-3 text-n-amber-11"
              >
                {{
                  t('AGENTS_RODIZIO.STALLED.WAITING', {
                    tempo: esperaDoParado(lead),
                  })
                }}
              </span>
              <span v-if="lead.produto" class="text-xs text-n-slate-10">
                {{ lead.produto }}
              </span>
              <span class="text-xs tabular-nums text-n-slate-10">
                {{ conversa(lead.display_id) }}
              </span>
              <button
                class="ml-auto text-xs underline text-n-slate-11"
                @click="abrirDetalhe(lead)"
              >
                {{ t('AGENTS_RODIZIO.DETAIL.OPEN') }}
              </button>
            </li>
          </ul>
        </div>
      </section>

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

      <!-- Abas em vez de mais uma seção embaixo: a `section.overflow-x-auto` da tabela é a única
           que encolhe nesta coluna flex, então todo bloco novo abaixo dela rouba altura da
           tabela e a espreme numa caixa com rolagem própria. -->
      <div class="flex gap-1 p-1 rounded-lg bg-n-slate-3 w-fit">
        <button
          v-for="item in abas"
          :key="item.value"
          class="px-3 py-1 text-sm rounded-md"
          :class="
            aba === item.value
              ? 'bg-white dark:bg-n-solid-3 text-n-slate-12 font-medium'
              : 'text-n-slate-11'
          "
          @click="irParaAba(item.value)"
        >
          {{ item.label }}
        </button>
      </div>

      <section v-if="aba === 'leads'" class="flex flex-col gap-3">
        <div class="flex flex-wrap items-baseline justify-between gap-2">
          <p class="m-0 text-sm font-medium text-n-slate-12">
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
                : 'bg-white dark:bg-n-solid-2 border-n-weak text-n-slate-11'
            "
            @click="escolherSituacao(item.value)"
          >
            {{ item.label }}
            <span class="text-xs tabular-nums opacity-80">
              {{ item.total || 0 }}
            </span>
          </button>
          <span class="w-px h-5 bg-n-slate-6" />
          <button
            v-tooltip.top="t('AGENTS_RODIZIO.LEADS.FILTER.REPASSADO_HINT')"
            class="inline-flex items-center gap-1.5 h-8 px-3 text-sm border rounded-full"
            :class="
              filtroSituacao === 'repassado'
                ? 'bg-n-slate-12 text-n-slate-1 border-n-slate-12 font-medium'
                : 'bg-white dark:bg-n-solid-2 border-n-weak text-n-slate-11'
            "
            @click="escolherSituacao('repassado')"
          >
            <span class="i-lucide-repeat-2 size-3.5" />
            {{ t('AGENTS_RODIZIO.LEADS.FILTER.REPASSADO') }}
            <span class="text-xs tabular-nums opacity-80">
              {{ contagemRepassados }}
            </span>
          </button>
          <select
            v-model="filtroConsultor"
            class="h-8 px-2 mb-0 ml-auto text-sm bg-white border rounded-lg w-auto dark:bg-n-solid-2 border-n-weak text-n-slate-12"
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

        <p v-if="leadsLoading" class="text-sm text-n-slate-10">
          {{ t('AGENTS_RODIZIO.LOADING') }}
        </p>
        <p v-else-if="!leadsDaConta.length" class="text-sm text-n-slate-10">
          {{
            filtroSituacao || filtroConsultor
              ? t('AGENTS_RODIZIO.LEADS.EMPTY_FILTER')
              : t('AGENTS_RODIZIO.LEADS.EMPTY')
          }}
        </p>
        <template v-else>
          <RodizioLeadCard
            v-for="lead in leadsDaConta"
            :key="lead.id"
            :lead="lead"
            :decorrido="decorrido"
            :limiar="limiar"
          />
          <div v-if="restantesDaConta" class="flex items-center gap-3">
            <button
              class="h-8 px-3 text-sm border rounded-lg border-n-weak text-n-slate-12"
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

      <section v-show="aba === 'consultores'" class="overflow-x-auto">
        <table class="w-full text-sm border rounded-xl border-n-weak">
          <thead class="bg-n-solid-1 dark:bg-n-solid-2 text-n-slate-11">
            <tr>
              <th class="px-3 py-2 font-medium text-left">
                {{ t('AGENTS_RODIZIO.TABLE.CONSULTANT') }}
              </th>
              <th class="px-3 py-2 font-medium text-right">
                {{ t('AGENTS_RODIZIO.TABLE.RECEIVED') }}
              </th>
              <th class="px-3 py-2 font-medium text-right">
                {{ t('AGENTS_RODIZIO.TABLE.ROTATION') }}
              </th>
              <th class="px-3 py-2 font-medium text-right">
                {{ t('AGENTS_RODIZIO.TABLE.CONTINUITY') }}
              </th>
              <th class="px-3 py-2 font-medium text-right">
                {{ t('AGENTS_RODIZIO.TABLE.PREFERENCE') }}
              </th>
              <th class="px-3 py-2 font-medium text-right">
                {{ t('AGENTS_RODIZIO.TABLE.HANDOFF') }}
              </th>
              <th class="px-3 py-2 font-medium text-right">
                {{ t('AGENTS_RODIZIO.TABLE.MANUAL') }}
              </th>
              <th class="px-3 py-2 font-medium text-right">
                {{ t('AGENTS_RODIZIO.TABLE.OPEN') }}
              </th>
              <th class="px-3 py-2 font-medium text-left">
                {{ t('AGENTS_RODIZIO.TABLE.CHANNELS') }}
              </th>
              <th class="px-3 py-2 font-medium text-left">
                {{ t('AGENTS_RODIZIO.TABLE.PRODUCTS') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="!linhas.length">
              <td colspan="10" class="px-3 py-6 text-center text-n-slate-10">
                {{ t('AGENTS_RODIZIO.EMPTY') }}
              </td>
            </tr>
            <template v-for="linha in linhas" :key="linha.user_id">
              <tr
                class="border-t border-n-weak"
                :class="{
                  'bg-n-solid-1 dark:bg-n-solid-2': expandido === linha.user_id,
                }"
              >
                <td class="px-3 py-2 text-n-slate-12">
                  <button
                    class="inline-flex items-center gap-2 text-left hover:underline underline-offset-4"
                    :aria-expanded="expandido === linha.user_id"
                    :title="t('AGENTS_RODIZIO.TIMELINE.OPEN')"
                    @click="alternarConsultor(linha)"
                  >
                    <span
                      class="transition-transform duration-200 i-lucide-chevron-right size-3.5 text-n-slate-10"
                      :class="{ 'rotate-90': expandido === linha.user_id }"
                    />
                    {{ linha.nome || linha.user_id }}
                  </button>
                </td>
                <td class="px-3 py-2 text-right text-n-slate-12">
                  {{ linha.recebidos }}
                </td>
                <td class="px-3 py-2 text-right text-n-slate-11">
                  {{ motivo(linha, 'rodizio') }}
                </td>
                <td class="px-3 py-2 text-right text-n-slate-11">
                  {{ motivo(linha, 'continuidade') }}
                </td>
                <td class="px-3 py-2 text-right text-n-slate-11">
                  {{ motivo(linha, 'preferencia_cliente') }}
                </td>
                <td class="px-3 py-2 text-right text-n-slate-11">
                  {{ motivo(linha, 'repasse_sla') }}
                </td>
                <!-- "Gestor" = chegou ao gestor, a mao ou escalado; as colunas somam "Recebidos". -->
                <td class="px-3 py-2 text-right text-n-slate-11">
                  {{
                    motivo(linha, 'escalado_gestor') +
                    motivo(linha, 'manual_gestor')
                  }}
                </td>
                <td class="px-3 py-2 text-right text-n-slate-11">
                  {{ linha.abertos }}
                </td>
                <td class="px-3 py-2 text-n-slate-10">{{ canais(linha) }}</td>
                <td class="px-3 py-2 text-n-slate-10">{{ produtos(linha) }}</td>
              </tr>

              <!-- A faixa abre ABAIXO da linha, e não como balão preso ao nome: a barra precisa
                   da largura da tabela, e balão dentro de célula sai cortado. -->
              <tr v-if="expandido === linha.user_id">
                <td colspan="10" class="p-0">
                  <div
                    class="flex flex-col gap-3 px-4 py-4 border-t bg-n-solid-1 dark:bg-n-solid-2 border-n-weak"
                  >
                    <div
                      class="flex flex-wrap items-baseline justify-between gap-2"
                    >
                      <p class="text-sm font-medium text-n-slate-12">
                        {{
                          t('AGENTS_RODIZIO.TIMELINE.TITLE', {
                            nome: linha.nome || linha.user_id,
                          })
                        }}
                      </p>
                      <p
                        v-if="mediaEspera(linha.user_id)"
                        class="text-xs text-n-slate-11"
                      >
                        {{
                          t('AGENTS_RODIZIO.TIMELINE.AVG_WAIT', {
                            tempo: mediaEspera(linha.user_id),
                          })
                        }}
                      </p>
                    </div>

                    <p v-if="timelineLoading" class="text-sm text-n-slate-10">
                      {{ t('AGENTS_RODIZIO.LOADING') }}
                    </p>
                    <p
                      v-else-if="!leadsDe(linha.user_id).length"
                      class="text-sm text-n-slate-10"
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
                      />

                      <p
                        v-if="restantes(linha.user_id)"
                        class="text-xs text-n-slate-10"
                      >
                        {{
                          t('AGENTS_RODIZIO.TIMELINE.SHOWING', {
                            n: leadsDe(linha.user_id).length,
                            total: timelineDe(linha.user_id).total,
                          })
                        }}
                      </p>
                    </template>
                  </div>
                </td>
              </tr>
            </template>
          </tbody>
        </table>
      </section>
    </template>
  </div>
</template>
