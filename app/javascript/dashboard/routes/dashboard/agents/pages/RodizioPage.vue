<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import DistribuicaoDashboardAPI from 'dashboard/api/distribuicaoDashboard';

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

const carregar = async () => {
  loading.value = true;
  loadError.value = false;
  detalhe.value = null;
  // Trocar de time ou de período muda quais leads contam: o que estava aberto vira mentira.
  expandido.value = null;
  timelines.value = {};
  try {
    const params = teamId.value ? { team_id: teamId.value } : {};
    const { data: payload } = await DistribuicaoDashboardAPI.show(params);
    data.value = payload;
  } catch (e) {
    loadError.value = true;
  } finally {
    loading.value = false;
  }
};

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

// ---------------------------------------------------------------- linha do tempo

// Ordem dos blocos na barra, a cor e o nome de cada um. Computed, e não constante solta, porque
// o nome é traduzido — e a chave fica escrita por extenso: chave montada em runtime já sumiu de
// tela neste projeto e o lint reclama dela com razão.
const FASES = computed(() => [
  {
    chave: 'ia',
    classe: 'bg-n-blue-3 text-n-blue-11',
    nome: t('AGENTS_RODIZIO.TIMELINE.PHASE.IA'),
  },
  {
    chave: 'espera',
    classe: 'bg-n-amber-3 text-n-amber-11',
    nome: t('AGENTS_RODIZIO.TIMELINE.PHASE.ESPERA'),
  },
  {
    chave: 'atendimento',
    classe: 'bg-n-teal-3 text-n-teal-11',
    nome: t('AGENTS_RODIZIO.TIMELINE.PHASE.ATENDIMENTO'),
  },
]);
const PERDIDO = 'bg-n-ruby-3 text-n-ruby-11';
// Abaixo disso o bloco não cabe o texto; o número continua no título e nos marcos.
const LARGURA_MINIMA_ROTULO = 12;

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
    const params = teamId.value ? { team_id: teamId.value } : {};
    const { data: payload } = await DistribuicaoDashboardAPI.linhaDoTempo(
      linha.user_id,
      params
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

// Formatador próprio em vez do `formatTime` dos relatórios: aquele arredonda 1h50 para "1h", e
// numa barra em que a diferença entre 2 min e 38 min é o assunto, isso apaga o dado.
const duracao = segundos => {
  const total = Math.round(segundos || 0);
  if (total < 60) return t('AGENTS_RODIZIO.TIMELINE.SECONDS', { n: total });

  const minutos = Math.round(total / 60);
  if (minutos < 60) return t('AGENTS_RODIZIO.TIMELINE.MINUTES', { n: minutos });

  const horas = Math.floor(minutos / 60);
  const resto = minutos % 60;
  if (horas < 24) {
    return resto
      ? t('AGENTS_RODIZIO.TIMELINE.HOURS_MINUTES', { h: horas, m: resto })
      : t('AGENTS_RODIZIO.TIMELINE.HOURS', { n: horas });
  }
  return t('AGENTS_RODIZIO.TIMELINE.DAYS', { n: Math.floor(horas / 24) });
};

const proporcao = (parte, todo) => (todo > 0 ? ((parte || 0) / todo) * 100 : 0);

// Todas as barras da faixa dividem a MESMA escala — a maior duração vira 100%. É o que deixa
// comparar um lead com o outro de bater o olho, em vez de cada barra se normalizar sozinha.
const escala = userId =>
  Math.max(...leadsDe(userId).map(lead => lead.total_segundos || 0), 1);

const larguraBarra = (lead, userId) =>
  `${proporcao(lead.total_segundos, escala(userId))}%`;

const fasesDo = lead =>
  FASES.value
    .filter(fase => (lead.fases?.[fase.chave] || 0) > 0)
    .map(fase => {
      const segundos = lead.fases[fase.chave];
      const largura = proporcao(segundos, lead.total_segundos);
      const perdeu = fase.chave === 'espera' && lead.perdido_em;
      return {
        chave: fase.chave,
        // Espera que terminou sem ninguém pegar é o defeito que a tela existe para mostrar.
        classe: perdeu ? PERDIDO : fase.classe,
        largura: `${largura}%`,
        rotulo: largura >= LARGURA_MINIMA_ROTULO ? duracao(segundos) : '',
        titulo: `${fase.nome} · ${duracao(segundos)}`,
      };
    });

// Um marco por instante gravado, na ordem em que aconteceram. O que não existe some da linha:
// lead que ninguém pegou não tem "pegou", e lead aberto não tem "resolvido".
const marcosDo = lead =>
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
    .filter(([campo]) => lead[campo])
    .map(([campo, texto]) => ({
      chave: campo,
      texto: texto(data_hora(lead[campo])),
    }));

const desfecho = lead => {
  if (lead.perdido_em) {
    return lead.repassado_para
      ? t('AGENTS_RODIZIO.TIMELINE.OUTCOME.PASSED', {
          nome: lead.repassado_para,
        })
      : t('AGENTS_RODIZIO.TIMELINE.OUTCOME.EXPIRED');
  }
  if (lead.resolvido_em) {
    return t('AGENTS_RODIZIO.TIMELINE.OUTCOME.RESOLVED', {
      tempo: duracao(lead.total_segundos),
    });
  }
  if (lead.em_curso) return t('AGENTS_RODIZIO.TIMELINE.OUTCOME.IN_SERVICE');
  return t('AGENTS_RODIZIO.TIMELINE.OUTCOME.WAITING', {
    tempo: duracao(lead.fases?.espera),
  });
};

const corDesfecho = lead => {
  if (lead.perdido_em) return 'text-n-ruby-11';
  if (!lead.resolvido_em && !lead.em_curso) return 'text-n-amber-11';
  return 'text-n-teal-11';
};

// "· WhatsApp · Apto 2 dorm" — montado aqui porque texto solto no template é erro de lint.
const contexto = lead => [lead.canal, lead.produto].filter(Boolean).join(' · ');

const mediaEspera = userId => {
  const segundos = timelineDe(userId).media_espera_segundos;
  return segundos ? duracao(segundos) : '';
};

const restantes = userId =>
  Math.max((timelineDe(userId).total || 0) - leadsDe(userId).length, 0);

// Montados aqui, e não no template, porque texto solto em template (o "#" e os "·")
// é erro de lint no projeto — nada de string crua fora do i18n.
const conversa = displayId => `#${displayId}`;

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
        </p>
      </div>
      <div class="flex items-center gap-2">
        <select
          v-model="teamId"
          class="h-9 px-2 text-sm bg-white border rounded-lg dark:bg-n-solid-2 border-n-weak text-n-slate-12"
          @change="carregar"
        >
          <option value="">{{ t('AGENTS_RODIZIO.ALL_TEAMS') }}</option>
          <option v-for="time in times" :key="time.id" :value="time.id">
            {{ time.name }} ({{ time.modo_posse }})
          </option>
        </select>
        <button
          class="h-9 px-3 text-sm rounded-lg bg-n-brand text-white transition-shadow hover:shadow-md"
          @click="carregar"
        >
          {{ t('AGENTS_RODIZIO.RELOAD') }}
        </button>
        <button
          class="h-9 px-3 text-sm rounded-lg border border-n-weak text-n-slate-11"
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
          class="px-4 py-3 bg-white border rounded-xl dark:bg-n-solid-2 border-n-weak"
        >
          <p class="text-xs uppercase text-n-slate-10">
            {{ t('AGENTS_RODIZIO.TOTAL_RECEIVED') }}
          </p>
          <p class="text-2xl font-medium text-n-slate-12">
            {{ totais.recebidos || 0 }}
          </p>
        </div>
        <div
          class="px-4 py-3 bg-white border rounded-xl dark:bg-n-solid-2 border-n-weak"
        >
          <p class="text-xs uppercase text-n-slate-10">
            {{ t('AGENTS_RODIZIO.STALLED.TITLE') }}
          </p>
          <p class="text-2xl font-medium text-n-slate-12">
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
      </section>

      <section class="overflow-x-auto">
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
                      <div
                        v-for="lead in leadsDe(linha.user_id)"
                        :key="lead.conversation_id"
                        class="flex flex-col gap-2 p-3 bg-white border rounded-lg dark:bg-n-solid-3 border-n-weak"
                      >
                        <div
                          class="flex flex-wrap items-baseline justify-between gap-2"
                        >
                          <span class="text-sm text-n-slate-12">
                            {{ conversa(lead.display_id) }}
                            <span class="text-xs text-n-slate-10">
                              {{ contexto(lead) }}
                            </span>
                          </span>
                          <span
                            class="text-xs font-medium"
                            :class="corDesfecho(lead)"
                          >
                            {{ desfecho(lead) }}
                          </span>
                        </div>

                        <div
                          class="flex h-6 overflow-hidden rounded"
                          :style="{ width: larguraBarra(lead, linha.user_id) }"
                        >
                          <div
                            v-for="fase in fasesDo(lead)"
                            :key="fase.chave"
                            class="flex items-center px-2 overflow-hidden text-[10px] whitespace-nowrap min-w-[3px]"
                            :class="fase.classe"
                            :style="{ width: fase.largura }"
                            :title="fase.titulo"
                          >
                            {{ fase.rotulo }}
                          </div>
                        </div>

                        <div
                          class="flex flex-wrap text-xs gap-x-4 gap-y-1 text-n-slate-10"
                        >
                          <span
                            v-for="marco in marcosDo(lead)"
                            :key="marco.chave"
                          >
                            {{ marco.texto }}
                          </span>
                        </div>
                      </div>

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

      <section class="flex flex-col gap-2">
        <h2 class="text-base font-medium text-n-slate-12">
          {{ t('AGENTS_RODIZIO.STALLED.LIST_TITLE') }}
        </h2>
        <p class="text-sm text-n-slate-11">
          {{ t('AGENTS_RODIZIO.STALLED.SUBTITLE') }}
        </p>
        <p v-if="!parados.leads.length" class="text-sm text-n-slate-10">
          {{ t('AGENTS_RODIZIO.STALLED.NONE') }}
        </p>
        <ul v-else class="flex flex-col gap-1">
          <li
            v-for="lead in parados.leads"
            :key="lead.conversation_id"
            class="flex flex-wrap items-center gap-3 px-3 py-2 bg-white border rounded-lg dark:bg-n-solid-2 border-n-weak"
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
              class="ml-auto text-sm underline text-n-slate-11"
              @click="abrirDetalhe(lead)"
            >
              {{ t('AGENTS_RODIZIO.DETAIL.OPEN') }}
            </button>
          </li>
        </ul>
      </section>

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
    </template>
  </div>
</template>
