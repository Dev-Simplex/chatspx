<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import CampaignsAPI from 'dashboard/api/campaigns';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
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
});

const emit = defineEmits(['changed']);

const { t } = useI18n();

const listText = ref('');
const preview = ref(null);
const busy = ref('');

const labels = useMapGetter('labels/getLabels');
const teams = useMapGetter('teams/getTeams');
const inboxes = useMapGetter('inboxes/getInboxes');
const todasCampanhas = useMapGetter('campaigns/getAllCampaigns');

// Repescar (ou evitar) quem recebeu um disparo anterior só faz sentido contra campanha que
// de fato enviou alguma coisa.
const campanhasAnteriores = computed(() =>
  (todasCampanhas.value || []).filter(c => Number(c.id) !== Number(props.campaignId))
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
  Object.values(props.recipients || {}).reduce((sum, n) => sum + Number(n || 0), 0)
);

const pendingCount = computed(() => Number(props.recipients?.pending || 0));

const statusRows = computed(() =>
  STATUS_ORDER.filter(key => props.recipients?.[key]).map(key => ({
    key,
    count: Number(props.recipients[key]),
  }))
);

// Percentual concluido = tudo que saiu da fila (o pendente e o que falta).
const progress = computed(() => {
  const total = totalRecipients.value;
  if (!total) return 0;
  return Math.round(((total - pendingCount.value) / total) * 100);
});

// Cada linha vira { name, phone }. O telefone e o campo com 8+ digitos; o resto e
// nome. Sem essa deteccao, colar uma coluna so de numeros — o caso mais comum —
// exigiria formatar a planilha a mao antes. Linha de cabecalho cai sozinha, porque
// nao tem campo com 8 digitos.
const parseRows = text =>
  text
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
        name: parts.filter((_, i) => i !== phoneIndex).join(' ').trim(),
        phone: parts[phoneIndex],
      };
    })
    .filter(Boolean);

const parsedRows = computed(() => parseRows(listText.value));

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
  const conteudo = `﻿nome,telefone\nMaria Silva,66999998888\nJoão Souza,6699998888\n`;
  const url = URL.createObjectURL(new Blob([conteudo], { type: 'text/csv;charset=utf-8' }));
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
const podeSegmentar = computed(() => origem.value === 'segmento' && !semCriterio.value);
const podeEnviarPlanilha = computed(() => origem.value === 'planilha' && parsedRows.value.length > 0);
const pronto = computed(() => podeSegmentar.value || podeEnviarPlanilha.value);

const filtrosLimpos = () => {
  const s = { ...segmento.value };
  Object.keys(s).forEach(k => {
    if (s[k] === null || s[k] === false || s[k] === '' || (Array.isArray(s[k]) && !s[k].length)) delete s[k];
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
  if (res) preview.value = res.data;
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
  listText.value = '';
  useAlert(
    t('CAMPAIGN.WHATSAPP.DISPATCH.UPLOAD_DONE', {
      count: res.data.stats?.inseridos ?? 0,
    })
  );
  emit('changed');
};

const doStart = async () => {
  const res = await run(
    'start',
    () => CampaignsAPI.startDispatch(props.campaignId),
    'CAMPAIGN.WHATSAPP.DISPATCH.START_ERROR'
  );
  if (res) emit('changed');
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
          class="px-2 py-1 text-xs font-medium rounded-md bg-n-alpha-2 text-n-slate-11"
        >
          {{ t(`CAMPAIGN.WHATSAPP.DISPATCH.STATUS.${dispatchStatus}`) }}
        </span>
        <button
          v-if="!isRunning"
          class="px-3 py-1.5 text-sm font-medium rounded-lg bg-n-brand text-white disabled:opacity-50"
          :disabled="busy === 'start' || !totalRecipients"
          @click="doStart"
        >
          {{ t('CAMPAIGN.WHATSAPP.DISPATCH.START') }}
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

    <!-- Progresso: so aparece quando ha destinatario carregado -->
    <div v-if="totalRecipients" class="mb-5">
      <div class="flex items-center justify-between mb-1 text-xs text-n-slate-11">
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
      <div class="w-full h-2 overflow-hidden rounded-full bg-n-alpha-2">
        <div
          class="h-full transition-all bg-n-brand"
          :style="{ width: `${progress}%` }"
        />
      </div>
      <div class="flex flex-wrap gap-x-4 gap-y-1 mt-2 text-xs text-n-slate-11">
        <span v-for="row in statusRows" :key="row.key">
          {{ t(`CAMPAIGN.WHATSAPP.DISPATCH.RECIPIENT_STATUS.${row.key}`) }}
          <strong class="tabular-nums text-n-slate-12">{{ row.count }}</strong>
        </span>
      </div>
    </div>

    <!-- De onde vem o público -->
    <div class="flex gap-2 mb-3">
      <button
        v-for="opcao in ['planilha', 'segmento']"
        :key="opcao"
        class="px-3 py-1 text-xs font-medium rounded-lg"
        :class="
          origem === opcao
            ? 'bg-n-brand text-white'
            : 'bg-n-alpha-2 text-n-slate-11'
        "
        @click="origem = opcao"
      >
        {{ t(`CAMPAIGN.WHATSAPP.DISPATCH.SOURCE.${opcao.toUpperCase()}`) }}
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

      <label class="text-sm">
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
        <label
          v-if="segmento.campaign_id"
          class="flex items-center gap-2 mt-1 text-xs cursor-pointer text-n-slate-11"
        >
          <input v-model="segmento.excluir_campanha" type="checkbox" />
          {{ t('CAMPAIGN.WHATSAPP.DISPATCH.SEGMENT.CAMPAIGN_EXCLUDE') }}
        </label>
      </label>

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
        <label class="flex items-center gap-2 text-xs cursor-pointer text-n-slate-11">
          <input v-model="segmento.sem_campanha" type="checkbox" />
          {{ t('CAMPAIGN.WHATSAPP.DISPATCH.SEGMENT.NEVER') }}
        </label>
      </div>

      <p v-if="semCriterio" class="text-xs sm:col-span-2 text-n-amber-11">
        {{ t('CAMPAIGN.WHATSAPP.DISPATCH.SEGMENT.EMPTY') }}
      </p>
    </div>

    <!-- Lista -->
    <div v-if="origem === 'planilha'" class="flex items-center justify-between mb-1">
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
      <input
        v-if="origem === 'planilha'"
        type="file"
        accept=".csv,.txt"
        class="text-xs text-n-slate-11 file:mr-2 file:px-2 file:py-1 file:text-xs file:border-0 file:rounded-md file:bg-n-alpha-2 file:text-n-slate-12"
        @change="onFile"
      />
      <span v-if="origem === 'planilha'" class="text-xs text-n-slate-10">
        {{
          t('CAMPAIGN.WHATSAPP.DISPATCH.PARSED', { count: parsedRows.length })
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
        <button
          class="px-3 py-1.5 text-sm font-medium rounded-lg bg-n-brand text-white disabled:opacity-50"
          :disabled="!pronto || busy === 'upload'"
          @click="doUpload"
        >
          {{ t('CAMPAIGN.WHATSAPP.DISPATCH.UPLOAD') }}
        </button>
      </div>
    </div>

    <div v-if="busy === 'preview' || busy === 'upload'" class="flex py-6 justify-center">
      <Spinner />
    </div>

    <!-- Audiencia limpa: o motivo de cada descarte e a razao de a tela existir -->
    <div v-else-if="preview" class="mt-5">
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

      <table
        v-if="Object.keys(preview.stats.por_motivo || {}).length"
        class="w-full mb-3 text-sm"
      >
        <tbody>
          <tr
            v-for="(count, reason) in preview.stats.por_motivo"
            :key="reason"
            class="border-b border-n-weak last:border-0"
          >
            <td class="py-1.5 text-n-slate-11">
              {{ t(`CAMPAIGN.WHATSAPP.DISPATCH.REASONS.${reason}`) }}
            </td>
            <td class="py-1.5 font-medium text-right tabular-nums text-n-slate-12">
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
          <tbody>
            <tr
              v-for="(row, index) in preview.rejected_sample"
              :key="`${row.phone}-${index}`"
              class="border-b border-n-weak last:border-0"
            >
              <td class="py-1 text-n-slate-12">{{ row.name || '—' }}</td>
              <td class="py-1 text-n-slate-11">{{ row.phone }}</td>
              <td class="py-1 text-xs text-right text-n-slate-10">
                {{ t(`CAMPAIGN.WHATSAPP.DISPATCH.REASONS.${row.reason}`) }}
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
  </div>
</template>
