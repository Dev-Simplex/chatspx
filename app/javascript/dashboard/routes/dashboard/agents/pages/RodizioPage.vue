<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import DistribuicaoDashboardAPI from 'dashboard/api/distribuicaoDashboard';
import RodizioLeadCard from './rodizio/RodizioLeadCard.vue';
import { duracao } from './rodizio/tempo';

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
const aba = ref('consultores');
const leadsGerais = ref(null);
const leadsLoading = ref(false);

const abas = computed(() => [
  { value: 'consultores', label: t('AGENTS_RODIZIO.TABS.BY_AGENT') },
  { value: 'leads', label: t('AGENTS_RODIZIO.TABS.BY_LEAD') },
]);

// ------------------------------------------------------------------------ período
//
// A tela nasceu olhando só o mês corrente e sem dizer que era essa a janela: mês sem movimento
// mostrava "nenhum lead distribuído no período" e ninguém descobria QUAL período. Agora ele é
// escolhido, vai nas TRÊS chamadas (tabela, faixa e leads) e fica escrito no cabeçalho.
const periodo = ref('mes');
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
  leadsLoading.value = true;
  try {
    const { data: payload } =
      await DistribuicaoDashboardAPI.leads(parametros());
    leadsGerais.value = payload;
  } catch (e) {
    leadsGerais.value = { leads: [], total: 0 };
  } finally {
    leadsLoading.value = false;
  }
};

const carregar = async () => {
  loading.value = true;
  loadError.value = false;
  detalhe.value = null;
  // Trocar de time ou de período muda quais leads contam: o que estava aberto vira mentira.
  expandido.value = null;
  timelines.value = {};
  leadsGerais.value = null;
  try {
    const { data: payload } = await DistribuicaoDashboardAPI.show(parametros());
    data.value = payload;
  } catch (e) {
    loadError.value = true;
  } finally {
    loading.value = false;
  }
  if (aba.value === 'leads') carregarLeads();
};

// Trocar o preset recarrega na hora; no personalizado só quando as duas pontas existem, senão a
// tela recarregaria a cada dígito digitado na primeira data.
const trocarPeriodo = () => {
  if (periodo.value !== 'personalizado') carregar();
};

const trocarIntervalo = () => {
  if (de.value && ate.value) carregar();
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

onMounted(carregar);

const linhas = computed(() => data.value?.linhas || []);
const totais = computed(() => data.value?.totais || {});
const times = computed(() => data.value?.times || []);
const parados = computed(
  () => data.value?.sem_movimento || { total: 0, leads: [], limiar_minutos: 0 }
);

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

const data_hora = valor => (valor ? new Date(valor).toLocaleString() : '—');

// Montado aqui, e não no template, porque texto solto em template é erro de lint no projeto —
// nada de string crua fora do i18n. O "#" saiu a pedido: o número do lead se lê sozinho.
const conversa = displayId => `${displayId}`;

// ---------------------------------------------------------------- linha do tempo

// A legenda da faixa: os três blocos da barra, na ordem e com a cor que o cartão usa. Vive aqui
// porque é uma por faixa, não uma por lead — a barra em si mora no RodizioLeadCard, e é lá que
// está escrito por que a fase da IA é cinza nesta skin.
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

// Teto da escala. Todas as barras dividem a mesma, e sem teto um lead de quatro dias achatava
// todos os outros num fio de um pixel — justo os de minutos, que são a maioria. Passando de
// 24 h a barra fica cheia e o total em texto, ao lado dela, conta a verdade.
const TETO_ESCALA = 24 * 60 * 60;

const escalaDe = leads =>
  Math.min(
    Math.max(...leads.map(lead => lead.total_segundos || 0), 1),
    TETO_ESCALA
  );

const timelineDe = userId => timelines.value[userId] || { leads: [], total: 0 };
const leadsDe = userId => timelineDe(userId).leads || [];

// Abre e fecha a faixa. O resultado fica guardado por consultor: reabrir não bate na API de novo.
const alternarConsultor = async linha => {
  if (expandido.value === linha.user_id) {
    expandido.value = null;
    return;
  }
  expandido.value = linha.user_id;
  if (timelines.value[linha.user_id]) return;

  timelineLoading.value = true;
  try {
    const { data: payload } = await DistribuicaoDashboardAPI.linhaDoTempo(
      linha.user_id,
      parametros()
    );
    timelines.value = { ...timelines.value, [linha.user_id]: payload };
  } catch (e) {
    timelines.value = {
      ...timelines.value,
      [linha.user_id]: { leads: [], total: 0 },
    };
  } finally {
    timelineLoading.value = false;
  }
};

const escalaDoConsultor = userId => escalaDe(leadsDe(userId));

const mediaEspera = userId => {
  const segundos = timelineDe(userId).media_espera_segundos;
  return segundos ? duracao(t, segundos) : '';
};

const restantes = userId =>
  Math.max((timelineDe(userId).total || 0) - leadsDe(userId).length, 0);

// ---------------------------------------------------------------------- aba Leads

// A tabela responde "quem recebeu quanto"; esta aba responde "onde está cada lead, com quem, e
// há quanto tempo" — sem precisar adivinhar em quem ele caiu para poder clicar. Mesma escala e
// mesmo cartão da faixa, e a ordem vem do backend: quem ninguém pegou primeiro.
const leadsDaConta = computed(() => leadsGerais.value?.leads || []);

const escalaDosLeads = computed(() => escalaDe(leadsDaConta.value));

const restantesDaConta = computed(() =>
  Math.max((leadsGerais.value?.total || 0) - leadsDaConta.value.length, 0)
);

const mediaEsperaDaConta = computed(() => {
  const segundos = leadsGerais.value?.media_espera_segundos;
  return segundos ? duracao(t, segundos) : '';
});

const irParaAba = valor => {
  aba.value = valor;
  if (valor === 'leads' && !leadsGerais.value) carregarLeads();
};

const resumoDesignacao = registro =>
  [registro.corretor || '—', registro.motivo, registro.status || '—'].join(
    ' · '
  );

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
        <template v-if="periodo === 'personalizado'">
          <input
            v-model="de"
            type="date"
            class="h-9 px-2 mb-0 text-sm bg-white border rounded-lg dark:bg-n-solid-2 border-n-weak text-n-slate-12"
            :aria-label="t('AGENTS_RODIZIO.PERIOD.FROM')"
            @change="trocarIntervalo"
          />
          <input
            v-model="ate"
            type="date"
            class="h-9 px-2 mb-0 text-sm bg-white border rounded-lg dark:bg-n-solid-2 border-n-weak text-n-slate-12"
            :aria-label="t('AGENTS_RODIZIO.PERIOD.TO')"
            @change="trocarIntervalo"
          />
        </template>
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
        <button
          class="h-9 px-3 text-sm rounded-lg border border-n-weak text-n-slate-11 whitespace-nowrap"
          @click="irParaPolitica"
        >
          {{ t('AGENTS_RODIZIO.CONFIGURE') }}
        </button>
      </div>
    </header>

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
              <span class="text-sm text-n-slate-12">
                {{ conversa(lead.display_id) }}
              </span>
              <span class="text-sm text-n-slate-11">{{
                lead.corretor || '—'
              }}</span>
              <span class="text-sm text-n-slate-10">
                {{
                  t('AGENTS_RODIZIO.STALLED.MINUTES', {
                    min: lead.minutos_parado,
                  })
                }}
              </span>
              <span v-if="lead.produto" class="text-xs text-n-slate-10">
                {{ lead.produto }}
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
            <p class="text-sm text-n-slate-12">
              {{ resumoDesignacao(registro) }}
            </p>
            <p class="text-xs text-n-slate-10">
              {{ t('AGENTS_RODIZIO.DETAIL.DESIGNATED_AT') }}
              {{ data_hora(registro.designado_em) }}
            </p>
            <p class="text-xs text-n-slate-10">
              {{ t('AGENTS_RODIZIO.DETAIL.CANDIDATES') }}
              {{ (registro.candidatos || []).join(', ') || '—' }}
            </p>
            <pre
              class="p-2 overflow-x-auto text-xs rounded-lg bg-n-solid-1 dark:bg-n-solid-3 text-n-slate-11"
              >{{ registro.regra_aplicada }}</pre
            >
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
          <p class="text-sm font-medium text-n-slate-12">
            {{ t('AGENTS_RODIZIO.LEADS.TITLE') }}
          </p>
          <p v-if="mediaEsperaDaConta" class="text-xs text-n-slate-11">
            {{
              t('AGENTS_RODIZIO.TIMELINE.AVG_WAIT', {
                tempo: mediaEsperaDaConta,
              })
            }}
          </p>
        </div>

        <p v-if="leadsLoading" class="text-sm text-n-slate-10">
          {{ t('AGENTS_RODIZIO.LOADING') }}
        </p>
        <p v-else-if="!leadsDaConta.length" class="text-sm text-n-slate-10">
          {{ t('AGENTS_RODIZIO.LEADS.EMPTY') }}
        </p>
        <template v-else>
          <RodizioLeadCard
            v-for="lead in leadsDaConta"
            :key="lead.conversation_id"
            :lead="lead"
            :escala="escalaDosLeads"
          />
          <p v-if="restantesDaConta" class="text-xs text-n-slate-10">
            {{
              t('AGENTS_RODIZIO.TIMELINE.SHOWING', {
                n: leadsDaConta.length,
                total: leadsGerais.total,
              })
            }}
          </p>
          <div
            class="flex flex-wrap items-center text-xs gap-x-4 gap-y-1 text-n-slate-11"
          >
            <span
              v-for="fase in FASES"
              :key="fase.chave"
              class="inline-flex items-center gap-1.5"
            >
              <span
                class="inline-block w-5 h-2.5 rounded-sm"
                :class="fase.classe"
              />
              {{ fase.nome }}
            </span>
            <span class="text-n-slate-10">
              {{ t('AGENTS_RODIZIO.TIMELINE.LEGEND') }}
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
              <td colspan="9" class="px-3 py-6 text-center text-n-slate-10">
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
                  {{ motivo(linha, 'manual_gestor') }}
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
                <td colspan="9" class="p-0">
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
                      <RodizioLeadCard
                        v-for="lead in leadsDe(linha.user_id)"
                        :key="lead.conversation_id"
                        :lead="lead"
                        :escala="escalaDoConsultor(linha.user_id)"
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

                      <div
                        class="flex flex-wrap items-center text-xs gap-x-4 gap-y-1 text-n-slate-11"
                      >
                        <span
                          v-for="fase in FASES"
                          :key="fase.chave"
                          class="inline-flex items-center gap-1.5"
                        >
                          <span
                            class="inline-block w-5 h-2.5 rounded-sm"
                            :class="fase.classe"
                          />
                          {{ fase.nome }}
                        </span>
                        <span class="text-n-slate-10">
                          {{ t('AGENTS_RODIZIO.TIMELINE.LEGEND') }}
                        </span>
                      </div>
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
