<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import CampaignsAPI from 'dashboard/api/campaigns';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';

// Operacao do disparo pela tela. Ate aqui isso era rake + CSV por SSH: os endpoints
// existiam desde a Fase 2a (audience_preview / recipients / start / pause) e nao
// tinham chamador nenhum no front.

const props = defineProps({
  campaignId: { type: [String, Number], required: true },
  dispatchStatus: { type: String, default: 'draft' },
  // { pending, sent, delivered, read, replied, failed, skipped, ... } vindo do /stats
  recipients: { type: Object, default: () => ({}) },
  // Config vigente do motor — o que a confirmação precisa afirmar antes do envio.
  campaign: { type: Object, default: () => ({}) },
  // O que o PRÓXIMO pendente vai receber, já renderizado pelo backend com a mesma lente
  // do envio. `null` quando não há template configurado.
  dispatchPreview: { type: Object, default: null },
  // Há alteração digitada e não salva no formulário do motor logo acima.
  settingsDirty: { type: Boolean, default: false },
});

const emit = defineEmits(['changed']);

const { t, te } = useI18n();

// Chave montada com valor do servidor imprime o CAMINHO DA CHAVE na tela no dia em que o
// backend acrescenta um motivo ou um estado novo. Numa superficie pt-BR isso conta como
// defeito, e o produto ainda promete que identificador tecnico nunca vira informacao de
// atendimento. Fallback legivel — mesmo padrao que o LeadRoutingDialog ja usa aqui do lado.
const rotulo = (chave, cru) => (te(chave) ? t(chave) : cru);

// Pilula cinza para TODO estado fazia campanha que explodiu ter a mesma cara de campanha
// que terminou bem. A cor passa a carregar o desfecho — junto do texto, nunca sozinha.
const CORES_STATUS = {
  running: 'bg-n-blue-3 text-n-blue-11',
  completed: 'bg-n-teal-3 text-n-teal-11',
  failed: 'bg-n-ruby-3 text-n-ruby-11',
  paused: 'bg-n-amber-3 text-n-amber-11',
};
const corStatus = computed(
  () => CORES_STATUS[props.dispatchStatus] || 'bg-n-alpha-2 text-n-slate-11'
);

const listText = ref('');
const preview = ref(null);
// De ONDE veio o resultado que esta na tela. "Conferir audiencia" (simulacao) e "Carregar
// destinatarios" (grava) escreviam no MESMO lugar e renderizavam o MESMO bloco: a unica
// diferenca era um toast que sumia. Numa tela cujo proximo clique manda mensagem, "ja
// carreguei esta lista?" e "qual audiencia estou vendo?" precisam ser respondiveis pelos
// pixels, nao pela memoria de quem clicou.
const previewMeta = ref(null);
const busy = ref('');

const labels = useMapGetter('labels/getLabels');
const teams = useMapGetter('teams/getTeams');
const inboxes = useMapGetter('inboxes/getInboxes');
const todasCampanhas = useMapGetter('campaigns/getAllCampaigns');

// Repescar (ou evitar) quem recebeu um disparo anterior só faz sentido contra campanha que
// de fato enviou alguma coisa.
const campanhasAnteriores = computed(() =>
  (todasCampanhas.value || []).filter(
    c => Number(c.id) !== Number(props.campaignId)
  )
);

// Ordem de leitura do funil — nao alfabetica.
const STATUS_ORDER = [
  'pending',
  'processing',
  'sent',
  'delivered',
  'read',
  'replied',
  'failed',
  'skipped',
  'cancelled',
];

const isRunning = computed(() => props.dispatchStatus === 'running');

const totalRecipients = computed(() =>
  Object.values(props.recipients || {}).reduce(
    (sum, n) => sum + Number(n || 0),
    0
  )
);

const pendingCount = computed(() => Number(props.recipients?.pending || 0));

const confirmRef = ref(null);

// Retomar não é iniciar. O mesmo rótulo nos dois casos escondia que a campanha já tinha
// disparado antes — e o operador não tem como saber, porque a tela nunca disse.
const isPaused = computed(() => props.dispatchStatus === 'paused');

// O gate era `!totalRecipients` — o TOTAL, que inclui quem JÁ recebeu. Campanha concluída
// apresentava um "Iniciar disparo" habilitado sem ter o que enviar. Quem manda é o que
// ainda está pendente.
const podeIniciar = computed(() => pendingCount.value > 0);

const ritmo = computed(() => {
  const segundos = Number(props.campaign?.pacing_seconds);
  if (!Number.isFinite(segundos) || segundos < 1) return null;
  return { segundos, porMinuto: Math.floor(60 / segundos) };
});

// A janela de silêncio é por hora cheia (o motor compara `Time.current.hour`). Mostrá-la
// resolvida na confirmação é a frase mais barata que existe contra disparar no horário
// errado — o campo tem as duas pontas configuráveis e a janela nunca aparecia montada.
const janelaSilencio = computed(() => {
  const quiet = props.campaign?.dispatch_config?.quiet_hours;
  if (!quiet || quiet.start === null || quiet.start === undefined) return null;
  const hora = valor => `${String(valor).padStart(2, '0')}:00`;
  return { inicio: hora(quiet.start), fim: hora(quiet.end) };
});

// Variável que o template exige e o parâmetro não preenche. É exatamente o defeito que
// mandou 124 mensagens com "Oi , sou a Kettlen" — e ele fica visível ANTES do envio.
const faltamVariaveis = computed(
  () => (props.dispatchPreview?.missing || []).length > 0
);

// Chip que sumia ao zerar fazia a regua RE-FLUIR a cada poll: os rotulos apareciam e
// mudavam de lugar sob o olho de quem estava lendo, de dez em dez segundos. Uma vez visto,
// o estado fica — inclusive zerado, que tambem e informacao ("nenhum falhou").
const estadosVistos = ref([]);
watch(
  () => props.recipients,
  valor => {
    const novos = STATUS_ORDER.filter(
      key => Number(valor?.[key] || 0) > 0 && !estadosVistos.value.includes(key)
    );
    if (novos.length) estadosVistos.value = [...estadosVistos.value, ...novos];
  },
  { immediate: true, deep: true }
);

const statusRows = computed(() =>
  STATUS_ORDER.filter(key => estadosVistos.value.includes(key)).map(key => ({
    key,
    count: Number(props.recipients?.[key] || 0),
  }))
);

// Percentual concluido = tudo que saiu da fila (o pendente e o que falta).
const progress = computed(() => {
  const total = totalRecipients.value;
  if (!total) return 0;
  return Math.round(((total - pendingCount.value) / total) * 100);
});

const soma = chaves =>
  chaves.reduce(
    (total, chave) => total + Number(props.recipients?.[chave] || 0),
    0
  );

// "Processado" NAO e "entregue". A barra tinha uma faixa so, pintada de marca, alimentada
// por tudo que saiu da fila — entao uma rodada em que TODAS as mensagens falharam
// renderizava barra cheia e "100%", e a tela parecia vitoria no instante do desastre. Num
// produto cujo principio e degradar com honestidade, existia uma barra incapaz de dizer
// que deu errado. Os tres destinos agora ocupam faixas distintas, e a cor diz qual e qual.
const entregues = computed(() =>
  soma(['sent', 'delivered', 'read', 'replied'])
);
const falhados = computed(() => soma(['failed']));
const descartados = computed(() => soma(['cancelled', 'skipped']));

const fatia = valor =>
  totalRecipients.value ? (valor / totalRecipients.value) * 100 : 0;

const faixas = computed(() => ({
  entregues: fatia(entregues.value),
  falhados: fatia(falhados.value),
  descartados: fatia(descartados.value),
}));

// Cada linha vira { name, phone }. O telefone e o campo com 8+ digitos; o resto e
// nome. Sem essa deteccao, colar uma coluna so de numeros — o caso mais comum —
// exigiria formatar a planilha a mao antes. Linha de cabecalho cai sozinha, porque
// nao tem campo com 8 digitos.
// Linha sem campo de 8+ digitos nao vira destinatario — e ate aqui ela sumia calada. Com
// 2.600 linhas e 300 telefones digitados errado, a tela dizia "2300 linhas reconhecidas" e
// nunca mencionava as 300: e a mesma falha que o comentario do truncamento, la embaixo,
// condena com todas as letras. Agora o descarte e CONTADO e aparece.
const parseRows = text => {
  const analisadas = text
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(Boolean)
    .map(line => {
      const parts = line.split(/[,;\t]/).map(part => part.trim());
      const phoneIndex = parts.findIndex(
        part => (part.match(/\d/g) || []).length >= 8
      );
      if (phoneIndex === -1) return null;
      return {
        name: parts
          .filter((_, i) => i !== phoneIndex)
          .join(' ')
          .trim(),
        phone: parts[phoneIndex],
      };
    });
  const rows = analisadas.filter(Boolean);
  return { rows, ignoradas: analisadas.length - rows.length };
};

const parseResult = computed(() => parseRows(listText.value));
const parsedRows = computed(() => parseResult.value.rows);
// A primeira linha costuma ser cabecalho e cai aqui legitimamente; por isso o aviso conta,
// mas nao bloqueia — quem decide se 300 descartes sao aceitaveis e quem colou a lista.
const linhasIgnoradas = computed(() => parseResult.value.ignoradas);

// Planilha binária (.xlsx/.xls) lida como texto vira bytes, o parser não acha telefone e o
// resultado é "0 linhas" sem dizer por quê — o operador conclui que a lista está errada.
// Recusar dizendo o que fazer é melhor que aceitar e produzir lixo em silêncio. Ler xlsx de
// verdade exigiria uma dependência nova de front, e o modelo em CSV resolve o mesmo problema.
const BINARIO = /\.(xlsx|xls|ods|numbers)$/i;

const onFile = event => {
  const file = event.target.files?.[0];
  if (!file) return;
  if (BINARIO.test(file.name)) {
    useAlert(t('CAMPAIGN.WHATSAPP.DISPATCH.NOT_CSV'));
    event.target.value = '';
    return;
  }
  const reader = new FileReader();
  reader.onload = () => {
    listText.value = String(reader.result || '');
  };
  reader.readAsText(file);
};

// Modelo pra baixar: o operador sanitiza contra um formato conhecido em vez de descobrir o
// formato pelo erro. Vai com BOM porque o Excel abre CSV sem BOM em Latin-1 e estraga os
// acentos do nome — e aí o "João" que volta no upload não é o mesmo que saiu.
const baixarModelo = () => {
  const conteudo = `\uFEFFnome,telefone\nMaria Silva,66999998888\nJoão Souza,6699998888\n`;
  const url = URL.createObjectURL(
    new Blob([conteudo], { type: 'text/csv;charset=utf-8' })
  );
  const link = document.createElement('a');
  link.href = url;
  link.download = 'modelo-lista-disparo.csv';
  link.click();
  URL.revokeObjectURL(url);
};

const run = async (key, fn, errorKey) => {
  busy.value = key;
  try {
    return await fn();
  } catch (error) {
    // O backend recusa start sem destinatario e sem template com uma frase util —
    // mostra ELA, nao um generico que esconde o motivo.
    const message = error?.response?.data?.error;
    useAlert(message || t(errorKey));
    return null;
  } finally {
    busy.value = '';
  }
};

// Planilha ou base. A escolha muda só DE ONDE saem as linhas: a higiene, o preview e o
// carregamento são os mesmos nos dois caminhos, porque o backend resolve o segmento em rows
// antes de entregar ao mesmo serviço.
const origem = ref('planilha');
const segmento = ref({
  labels: [],
  team_id: null,
  inbox_id: null,
  status: null,
  campaign_id: null,
  sem_campanha: false,
  excluir_campanha: false,
  ultima_atividade_dias: null,
});

// Trocar planilha <-> base NAO limpava o resultado: o numero da planilha continuava na
// tela, sem rotulo nenhum, enquanto o construtor de segmento ja estava ativo. Nao existia
// watcher — e o proximo clique do fluxo e o que envia.
watch(origem, () => {
  preview.value = null;
  previewMeta.value = null;
});

const semCriterio = computed(() => {
  const s = segmento.value;
  return (
    !s.labels.length &&
    !s.team_id &&
    !s.inbox_id &&
    !s.status &&
    !s.campaign_id &&
    !s.sem_campanha &&
    !s.ultima_atividade_dias
  );
});

// Sem critério nenhum o segmento seria "a base inteira" — e disparo para a base inteira
// nunca é o que alguém quis fazer de propósito.
const podeSegmentar = computed(
  () => origem.value === 'segmento' && !semCriterio.value
);
const podeEnviarPlanilha = computed(
  () => origem.value === 'planilha' && parsedRows.value.length > 0
);
const pronto = computed(() => podeSegmentar.value || podeEnviarPlanilha.value);

const filtrosLimpos = () => {
  const s = { ...segmento.value };
  // Mesmo defeito do pacing: `min` num input fora de um <form> nao e aplicado por ninguem.
  // Recencia <= 0 nao significa nada e viraria filtro silenciosamente inutil.
  const dias = Number(s.ultima_atividade_dias);
  if (!Number.isFinite(dias) || dias < 1) s.ultima_atividade_dias = null;
  else s.ultima_atividade_dias = dias;
  Object.keys(s).forEach(k => {
    if (
      s[k] === null ||
      s[k] === false ||
      s[k] === '' ||
      (Array.isArray(s[k]) && !s[k].length)
    )
      delete s[k];
  });
  return s;
};

const doPreview = async () => {
  if (!pronto.value) return;
  const res = await run(
    'preview',
    () =>
      origem.value === 'segmento'
        ? CampaignsAPI.segmentPreview(props.campaignId, filtrosLimpos())
        : CampaignsAPI.audiencePreview(props.campaignId, parsedRows.value),
    'CAMPAIGN.WHATSAPP.DISPATCH.PREVIEW_ERROR'
  );
  if (!res) return;
  preview.value = res.data;
  previewMeta.value = { modo: 'simulacao', origem: origem.value };
};

const doUpload = async () => {
  if (!pronto.value) return;
  const res = await run(
    'upload',
    () =>
      origem.value === 'segmento'
        ? CampaignsAPI.segmentRecipients(props.campaignId, filtrosLimpos())
        : CampaignsAPI.uploadRecipients(props.campaignId, parsedRows.value),
    'CAMPAIGN.WHATSAPP.DISPATCH.UPLOAD_ERROR'
  );
  if (!res) return;
  preview.value = res.data;
  previewMeta.value = { modo: 'carregado', origem: origem.value };
  listText.value = '';
  useAlert(
    t('CAMPAIGN.WHATSAPP.DISPATCH.UPLOAD_DONE', {
      count: res.data.stats?.inseridos ?? 0,
    })
  );
  emit('changed');
};

// O botão não dispara mais: ele abre a confirmação. Antes, um clique começava a enviar
// para a lista inteira — sem contagem, sem template à vista, sem janela, sem desfazer —
// num botão idêntico ao de carregar planilha, doze linhas de markup ao lado. O repo já
// confirma apagar um RASCUNHO de campanha; mandar mensagem para milhares de estranhos
// não pedia nada.
const doStart = async () => {
  const res = await run(
    'start',
    () => CampaignsAPI.startDispatch(props.campaignId),
    'CAMPAIGN.WHATSAPP.DISPATCH.START_ERROR'
  );
  // Falhou: o motivo do backend ja virou toast e o dialogo FICA aberto, com os fatos a
  // vista, pra corrigir e tentar de novo. Fechar aqui devolveria o operador a tela sem
  // contexto nenhum do que ele tinha acabado de confirmar.
  if (!res) return;
  confirmRef.value?.close();
  emit('changed');
};

const doPause = async () => {
  const res = await run(
    'pause',
    () => CampaignsAPI.pauseDispatch(props.campaignId),
    'CAMPAIGN.WHATSAPP.DISPATCH.PAUSE_ERROR'
  );
  if (res) emit('changed');
};
</script>

<template>
  <div class="p-4 bg-white border rounded-xl border-n-weak dark:bg-n-solid-2">
    <div class="flex flex-wrap items-center justify-between gap-3 mb-4">
      <h2 class="text-sm font-medium text-n-slate-12">
        {{ t('CAMPAIGN.WHATSAPP.DISPATCH.TITLE') }}
      </h2>
      <div class="flex items-center gap-2">
        <span
          class="px-2 py-1 text-xs font-medium rounded-md"
          :class="corStatus"
        >
          {{
            rotulo(
              `CAMPAIGN.WHATSAPP.DISPATCH.STATUS.${dispatchStatus}`,
              dispatchStatus
            )
          }}
        </span>
        <button
          v-if="!isRunning"
          class="px-3 py-1.5 text-sm font-medium rounded-lg bg-n-brand text-white disabled:opacity-50"
          :disabled="busy === 'start' || !podeIniciar"
          @click="confirmRef?.open()"
        >
          {{
            isPaused
              ? t('CAMPAIGN.WHATSAPP.DISPATCH.RESUME')
              : t('CAMPAIGN.WHATSAPP.DISPATCH.START')
          }}
        </button>
        <button
          v-else
          class="px-3 py-1.5 text-sm font-medium rounded-lg bg-n-alpha-2 text-n-slate-12 disabled:opacity-50"
          :disabled="busy === 'pause'"
          @click="doPause"
        >
          {{ t('CAMPAIGN.WHATSAPP.DISPATCH.PAUSE') }}
        </button>
      </div>
    </div>

    <!--
      Progresso: so aparece quando ha destinatario carregado. `aria-live="polite"` porque o
      bloco se atualiza sozinho a cada 10s e, sem ele, a tela de quem usa leitor fica MUDA
      exatamente durante o disparo — que e a unica razao de estar nesta pagina.
    -->
    <div v-if="totalRecipients" class="mb-5" aria-live="polite">
      <div
        class="flex items-center justify-between mb-1 text-xs text-n-slate-11"
      >
        <span>
          {{
            t('CAMPAIGN.WHATSAPP.DISPATCH.PROGRESS', {
              done: totalRecipients - pendingCount,
              total: totalRecipients,
            })
          }}
        </span>
        <span class="tabular-nums">{{ progress }}%</span>
      </div>
      <!--
        Tres faixas, nao uma. `role="progressbar"` porque antes eram duas <div> com largura
        inline: sem papel, sem valor e sem nome acessivel, invisivel para tecnologia
        assistiva (o repo faz certo no ProgressRing.vue).
      -->
      <div
        class="flex w-full h-2 overflow-hidden rounded-full bg-n-alpha-2"
        role="progressbar"
        :aria-valuenow="progress"
        aria-valuemin="0"
        aria-valuemax="100"
        :aria-label="t('CAMPAIGN.WHATSAPP.DISPATCH.PROGRESS_LABEL')"
      >
        <div
          class="h-full transition-all bg-n-teal-9"
          :style="{ width: `${faixas.entregues}%` }"
        />
        <div
          class="h-full transition-all bg-n-ruby-9"
          :style="{ width: `${faixas.falhados}%` }"
        />
        <div
          class="h-full transition-all bg-n-amber-9"
          :style="{ width: `${faixas.descartados}%` }"
        />
      </div>
      <p v-if="falhados" class="mt-1 text-xs text-n-ruby-11">
        {{ t('CAMPAIGN.WHATSAPP.DISPATCH.FAILED_NOTE', { count: falhados }) }}
      </p>
      <div class="flex flex-wrap gap-x-4 gap-y-1 mt-2 text-xs text-n-slate-11">
        <span v-for="row in statusRows" :key="row.key">
          {{
            rotulo(
              `CAMPAIGN.WHATSAPP.DISPATCH.RECIPIENT_STATUS.${row.key}`,
              row.key
            )
          }}
          <strong class="tabular-nums text-n-slate-12">{{ row.count }}</strong>
        </span>
      </div>
    </div>

    <!--
      De onde vem o publico. `aria-pressed` porque o estado selecionado era carregado SO
      pela cor de fundo: quem usa leitor de tela ouvia dois botoes sem marca nenhuma e nao
      tinha como saber qual estava ativo. O produto diz que cor nunca e o unico portador de
      significado, e o `aria-pressed` ja e usado certo em outros pontos desta base.
    -->
    <div
      class="flex gap-2 mb-3"
      role="group"
      :aria-label="t('CAMPAIGN.WHATSAPP.DISPATCH.SOURCE.GROUP')"
    >
      <button
        v-for="opcao in ['planilha', 'segmento']"
        :key="opcao"
        type="button"
        :aria-pressed="origem === opcao"
        class="px-3 py-1 text-xs font-medium rounded-lg"
        :class="
          origem === opcao
            ? 'bg-n-brand text-white'
            : 'bg-n-alpha-2 text-n-slate-11'
        "
        @click="origem = opcao"
      >
        {{
          rotulo(
            `CAMPAIGN.WHATSAPP.DISPATCH.SOURCE.${opcao.toUpperCase()}`,
            opcao
          )
        }}
      </button>
    </div>

    <!-- Público montado sobre a base. Desemboca no mesmo preview da planilha. -->
    <div v-if="origem === 'segmento'" class="grid gap-3 mb-3 sm:grid-cols-2">
      <label class="text-sm">
        <span class="block mb-1 text-xs text-n-slate-11">
          {{ t('CAMPAIGN.WHATSAPP.DISPATCH.SEGMENT.LABELS') }}
        </span>
        <select
          v-model="segmento.labels"
          multiple
          size="4"
          class="w-full text-sm rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
        >
          <option v-for="label in labels" :key="label.id" :value="label.title">
            {{ label.title }}
          </option>
        </select>
      </label>

      <div class="grid gap-3">
        <label class="text-sm">
          <span class="block mb-1 text-xs text-n-slate-11">
            {{ t('CAMPAIGN.WHATSAPP.DISPATCH.SEGMENT.TEAM') }}
          </span>
          <select
            v-model="segmento.team_id"
            class="w-full text-sm rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          >
            <option :value="null">
              {{ t('CAMPAIGN.WHATSAPP.DISPATCH.SEGMENT.ANY') }}
            </option>
            <option v-for="team in teams" :key="team.id" :value="team.id">
              {{ team.name }}
            </option>
          </select>
        </label>

        <label class="text-sm">
          <span class="block mb-1 text-xs text-n-slate-11">
            {{ t('CAMPAIGN.WHATSAPP.DISPATCH.SEGMENT.INBOX') }}
          </span>
          <select
            v-model="segmento.inbox_id"
            class="w-full text-sm rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          >
            <option :value="null">
              {{ t('CAMPAIGN.WHATSAPP.DISPATCH.SEGMENT.ANY') }}
            </option>
            <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
              {{ inbox.name }}
            </option>
          </select>
        </label>
      </div>

      <!--
        Os dois <label> sao IRMAOS, nao aninhados. Antes o da caixa de exclusao ficava
        DENTRO do label do select: <label> dentro de <label> e HTML invalido, a associacao
        fica indefinida e clicar no texto de dentro podia focar o select de fora.
      -->
      <div class="text-sm">
        <label class="block">
          <span class="block mb-1 text-xs text-n-slate-11">
            {{ t('CAMPAIGN.WHATSAPP.DISPATCH.SEGMENT.CAMPAIGN') }}
          </span>
          <select
            v-model="segmento.campaign_id"
            class="w-full text-sm rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          >
            <option :value="null">
              {{ t('CAMPAIGN.WHATSAPP.DISPATCH.SEGMENT.ANY') }}
            </option>
            <option
              v-for="camp in campanhasAnteriores"
              :key="camp.id"
              :value="camp.id"
            >
              {{ camp.title }}
            </option>
          </select>
        </label>
        <label
          v-if="segmento.campaign_id"
          class="flex items-center gap-2 mt-1 text-xs cursor-pointer text-n-slate-11"
        >
          <input v-model="segmento.excluir_campanha" type="checkbox" />
          {{ t('CAMPAIGN.WHATSAPP.DISPATCH.SEGMENT.CAMPAIGN_EXCLUDE') }}
        </label>
      </div>

      <div class="grid gap-3">
        <label class="text-sm">
          <span class="block mb-1 text-xs text-n-slate-11">
            {{ t('CAMPAIGN.WHATSAPP.DISPATCH.SEGMENT.RECENCY') }}
          </span>
          <input
            v-model="segmento.ultima_atividade_dias"
            type="number"
            min="1"
            class="w-full text-sm rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
        <label
          class="flex items-center gap-2 text-xs cursor-pointer text-n-slate-11"
        >
          <input v-model="segmento.sem_campanha" type="checkbox" />
          {{ t('CAMPAIGN.WHATSAPP.DISPATCH.SEGMENT.NEVER') }}
        </label>
      </div>

      <p v-if="semCriterio" class="text-xs sm:col-span-2 text-n-amber-11">
        {{ t('CAMPAIGN.WHATSAPP.DISPATCH.SEGMENT.EMPTY') }}
      </p>
    </div>

    <!-- Lista -->
    <div
      v-if="origem === 'planilha'"
      class="flex items-center justify-between mb-1"
    >
      <label class="text-xs font-medium text-n-slate-11">
        {{ t('CAMPAIGN.WHATSAPP.DISPATCH.LIST_LABEL') }}
      </label>
      <button
        class="text-xs underline text-n-slate-11 hover:text-n-slate-12"
        @click="baixarModelo"
      >
        {{ t('CAMPAIGN.WHATSAPP.DISPATCH.TEMPLATE_DOWNLOAD') }}
      </button>
    </div>
    <textarea
      v-if="origem === 'planilha'"
      v-model="listText"
      rows="5"
      :placeholder="t('CAMPAIGN.WHATSAPP.DISPATCH.LIST_PLACEHOLDER')"
      class="w-full px-3 py-2 text-sm border rounded-lg resize-y border-n-weak bg-n-alpha-1 text-n-slate-12 placeholder:text-n-slate-10"
    />

    <div class="flex flex-wrap items-center gap-3 mt-2">
      <!-- `aria-label`: o campo de arquivo nao tinha nome acessivel nenhum. -->
      <input
        v-if="origem === 'planilha'"
        type="file"
        accept=".csv,.txt"
        :aria-label="t('CAMPAIGN.WHATSAPP.DISPATCH.FILE_LABEL')"
        class="text-xs text-n-slate-11 file:mr-2 file:px-2 file:py-1 file:text-xs file:border-0 file:rounded-md file:bg-n-alpha-2 file:text-n-slate-12"
        @change="onFile"
      />
      <span v-if="origem === 'planilha'" class="text-xs text-n-slate-10">
        {{
          t('CAMPAIGN.WHATSAPP.DISPATCH.PARSED', { count: parsedRows.length })
        }}
      </span>
      <!--
        Linha que nao virou destinatario. Sem isto, 300 telefones digitados errado sumiam e
        a tela dizia so "2300 linhas reconhecidas" — lista que PARECE limpa porque foi
        cortada em silencio, que e o que o proprio arquivo condena mais abaixo.
      -->
      <span
        v-if="origem === 'planilha' && linhasIgnoradas"
        class="text-xs text-n-amber-11"
      >
        {{
          t('CAMPAIGN.WHATSAPP.DISPATCH.IGNORED_LINES', {
            count: linhasIgnoradas,
          })
        }}
      </span>
      <div class="flex gap-2 ms-auto">
        <button
          class="px-3 py-1.5 text-sm font-medium rounded-lg bg-n-alpha-2 text-n-slate-12 disabled:opacity-50"
          :disabled="!pronto || busy === 'preview'"
          @click="doPreview"
        >
          {{ t('CAMPAIGN.WHATSAPP.DISPATCH.PREVIEW') }}
        </button>
        <!-- Contorno, nao verde solido: carregar lista e o verde do disparo eram o MESMO
             botao a doze linhas de distancia, e um manda mensagem pra milhares de pessoas. -->
        <button
          class="px-3 py-1.5 text-sm font-medium border rounded-lg border-n-brand text-n-brand disabled:opacity-50"
          :disabled="!pronto || busy === 'upload'"
          @click="doUpload"
        >
          {{ t('CAMPAIGN.WHATSAPP.DISPATCH.UPLOAD') }}
        </button>
      </div>
    </div>

    <div
      v-if="busy === 'preview' || busy === 'upload'"
      class="flex py-6 justify-center"
    >
      <Spinner />
    </div>

    <!-- Audiencia limpa: o motivo de cada descarte e a razao de a tela existir -->
    <div v-else-if="preview" class="mt-5">
      <!--
        Procedencia do resultado. Simulacao e carga escrevem no mesmo lugar e desenham o
        mesmo bloco; sem este cabecalho, "ja carreguei?" e "de onde veio isto?" viviam num
        toast que sumia — e o proximo clique do fluxo e o que envia mensagem.
      -->
      <p
        v-if="previewMeta"
        class="mb-2 text-xs font-medium"
        :class="
          previewMeta.modo === 'carregado'
            ? 'text-n-teal-11'
            : 'text-n-slate-11'
        "
      >
        {{
          t(
            `CAMPAIGN.WHATSAPP.DISPATCH.ORIGIN.${previewMeta.modo.toUpperCase()}`,
            {
              source: t(
                `CAMPAIGN.WHATSAPP.DISPATCH.SOURCE.${previewMeta.origem.toUpperCase()}`
              ),
            }
          )
        }}
      </p>
      <div class="flex flex-wrap gap-4 mb-3 text-sm">
        <span class="text-n-slate-11">
          {{ t('CAMPAIGN.WHATSAPP.DISPATCH.AUDIENCE.TOTAL') }}
          <strong class="tabular-nums text-n-slate-12">
            {{ preview.stats.total }}
          </strong>
        </span>
        <span class="text-n-teal-11">
          {{ t('CAMPAIGN.WHATSAPP.DISPATCH.AUDIENCE.ACCEPTED') }}
          <strong class="tabular-nums">{{ preview.stats.aceitos }}</strong>
        </span>
        <span class="text-n-amber-11">
          {{ t('CAMPAIGN.WHATSAPP.DISPATCH.AUDIENCE.REJECTED') }}
          <strong class="tabular-nums">{{ preview.stats.descartados }}</strong>
        </span>
      </div>

      <!-- Sem <thead>, quem usa leitor de tela ouve "Telefone invalido, 12" sem saber o
           que a segunda coluna significa. -->
      <table
        v-if="Object.keys(preview.stats.por_motivo || {}).length"
        class="w-full mb-3 text-sm"
      >
        <thead>
          <tr class="text-xs text-left text-n-slate-10">
            <th class="py-1 font-normal">
              {{ t('CAMPAIGN.WHATSAPP.DISPATCH.TABLE.REASON') }}
            </th>
            <th class="py-1 font-normal text-right">
              {{ t('CAMPAIGN.WHATSAPP.DISPATCH.TABLE.COUNT') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="(count, reason) in preview.stats.por_motivo"
            :key="reason"
            class="border-b border-n-weak last:border-0"
          >
            <td class="py-1.5 text-n-slate-11">
              {{
                rotulo(`CAMPAIGN.WHATSAPP.DISPATCH.REASONS.${reason}`, reason)
              }}
            </td>
            <td
              class="py-1.5 font-medium text-right tabular-nums text-n-slate-12"
            >
              {{ count }}
            </td>
          </tr>
        </tbody>
      </table>

      <details v-if="preview.rejected_sample?.length" class="text-sm">
        <summary class="cursor-pointer text-n-slate-11">
          {{ t('CAMPAIGN.WHATSAPP.DISPATCH.SHOW_REJECTED') }}
        </summary>
        <table class="w-full mt-2">
          <thead>
            <tr class="text-xs text-left text-n-slate-10">
              <th class="py-1 font-normal">
                {{ t('CAMPAIGN.WHATSAPP.DISPATCH.TABLE.NAME') }}
              </th>
              <th class="py-1 font-normal">
                {{ t('CAMPAIGN.WHATSAPP.DISPATCH.TABLE.PHONE') }}
              </th>
              <th class="py-1 font-normal text-right">
                {{ t('CAMPAIGN.WHATSAPP.DISPATCH.TABLE.REASON') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(row, index) in preview.rejected_sample"
              :key="`${row.phone}-${index}`"
              class="border-b border-n-weak last:border-0"
            >
              <td class="py-1 text-n-slate-12">{{ row.name || '—' }}</td>
              <td class="py-1 text-n-slate-11">{{ row.phone }}</td>
              <td class="py-1 text-xs text-right text-n-slate-10">
                {{
                  rotulo(
                    `CAMPAIGN.WHATSAPP.DISPATCH.REASONS.${row.reason}`,
                    row.reason
                  )
                }}
              </td>
            </tr>
          </tbody>
        </table>
        <!-- Truncamento explicito: audiencia que PARECE limpa porque a lista foi
             cortada em silencio e pior do que audiencia suja. -->
        <p v-if="preview.rejected_omitted" class="mt-2 text-xs text-n-slate-10">
          {{
            t('CAMPAIGN.WHATSAPP.DISPATCH.OMITTED', {
              count: preview.rejected_omitted,
            })
          }}
        </p>
      </details>
    </div>

    <!--
      Confirmacao do disparo. Ela existe para dizer, ANTES do envio, os fatos que o
      componente ja tinha e nunca mostrava: para quantos, com qual template, em que ritmo,
      respeitando qual janela — e como a mensagem vai chegar no telefone da pessoa.
    -->
    <Dialog
      ref="confirmRef"
      type="alert"
      :title="
        isPaused
          ? t('CAMPAIGN.WHATSAPP.DISPATCH.CONFIRM.TITLE_RESUME')
          : t('CAMPAIGN.WHATSAPP.DISPATCH.CONFIRM.TITLE')
      "
      :description="t('CAMPAIGN.WHATSAPP.DISPATCH.CONFIRM.IRREVERSIBLE')"
      :confirm-button-label="
        isPaused
          ? t('CAMPAIGN.WHATSAPP.DISPATCH.RESUME')
          : t('CAMPAIGN.WHATSAPP.DISPATCH.START')
      "
      :is-loading="busy === 'start'"
      :disable-confirm-button="busy === 'start'"
      @confirm="doStart"
    >
      <div class="flex flex-col gap-4">
        <dl class="grid gap-1.5 text-sm">
          <div class="flex justify-between gap-4">
            <dt class="text-n-slate-11">
              {{ t('CAMPAIGN.WHATSAPP.DISPATCH.CONFIRM.RECIPIENTS') }}
            </dt>
            <dd class="font-medium tabular-nums text-n-slate-12">
              {{ pendingCount }}
            </dd>
          </div>
          <div class="flex justify-between gap-4">
            <dt class="text-n-slate-11">
              {{ t('CAMPAIGN.WHATSAPP.DISPATCH.CONFIRM.TEMPLATE') }}
            </dt>
            <dd
              class="font-medium text-end"
              :class="
                dispatchPreview?.template_name
                  ? 'text-n-slate-12'
                  : 'text-n-ruby-11'
              "
            >
              {{
                dispatchPreview?.template_name ||
                t('CAMPAIGN.WHATSAPP.DISPATCH.CONFIRM.NO_TEMPLATE')
              }}
            </dd>
          </div>
          <div v-if="ritmo" class="flex justify-between gap-4">
            <dt class="text-n-slate-11">
              {{ t('CAMPAIGN.WHATSAPP.DISPATCH.CONFIRM.PACING') }}
            </dt>
            <dd class="font-medium text-n-slate-12">
              {{
                t('CAMPAIGN.WHATSAPP.DISPATCH.CONFIRM.PACING_VALUE', {
                  seconds: ritmo.segundos,
                  rate: ritmo.porMinuto,
                })
              }}
            </dd>
          </div>
          <div class="flex justify-between gap-4">
            <dt class="text-n-slate-11">
              {{ t('CAMPAIGN.WHATSAPP.DISPATCH.CONFIRM.QUIET') }}
            </dt>
            <dd class="font-medium text-end text-n-slate-12">
              {{
                janelaSilencio
                  ? t('CAMPAIGN.WHATSAPP.DISPATCH.CONFIRM.QUIET_VALUE', {
                      start: janelaSilencio.inicio,
                      end: janelaSilencio.fim,
                    })
                  : t('CAMPAIGN.WHATSAPP.DISPATCH.CONFIRM.NO_QUIET')
              }}
            </dd>
          </div>
        </dl>

        <!--
          A mensagem como ela chega no telefone da pessoa. Sai da nossa conta, entao no
          aparelho dela e uma mensagem RECEBIDA — por isso a bolha e a de entrada.
        -->
        <div>
          <p class="mb-1.5 text-xs text-n-slate-11">
            {{
              dispatchPreview?.contact_name
                ? t('CAMPAIGN.WHATSAPP.DISPATCH.CONFIRM.PREVIEW_FOR', {
                    name: dispatchPreview.contact_name,
                  })
                : t('CAMPAIGN.WHATSAPP.DISPATCH.CONFIRM.PREVIEW')
            }}
          </p>
          <div class="p-3 rounded-lg bg-wa-pane-light dark:bg-wa-pane-dark">
            <div
              v-if="dispatchPreview?.body"
              class="max-w-[85%] rounded-lg rounded-tl-none px-3 py-2 text-sm whitespace-pre-line bg-wa-surface-light dark:bg-wa-surface-dark text-n-slate-12 shadow-sm"
            >
              {{ dispatchPreview.body }}
            </div>
            <p v-else class="text-xs text-wa-text-muted">
              {{ t('CAMPAIGN.WHATSAPP.DISPATCH.CONFIRM.NO_BODY') }}
            </p>
          </div>
        </div>

        <!--
          Variavel que o template exige e o parametro nao preenche. E o defeito que mandou
          124 mensagens comecando com "Oi ,": o status nao acusa, porque a Meta aceita.
        -->
        <p v-if="faltamVariaveis" class="text-xs text-n-ruby-11">
          {{
            t('CAMPAIGN.WHATSAPP.DISPATCH.CONFIRM.MISSING', {
              vars: dispatchPreview.missing.join(', '),
            })
          }}
        </p>

        <p v-if="settingsDirty" class="text-xs text-n-amber-11">
          {{ t('CAMPAIGN.WHATSAPP.DISPATCH.CONFIRM.DIRTY') }}
        </p>
      </div>
    </Dialog>
  </div>
</template>
