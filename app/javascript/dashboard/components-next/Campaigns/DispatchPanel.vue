<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import CampaignsAPI from 'dashboard/api/campaigns';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useAlert } from 'dashboard/composables';

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

const onFile = event => {
  const file = event.target.files?.[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = () => {
    listText.value = String(reader.result || '');
  };
  reader.readAsText(file);
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

const doPreview = async () => {
  const rows = parsedRows.value;
  if (!rows.length) return;
  const res = await run(
    'preview',
    () => CampaignsAPI.audiencePreview(props.campaignId, rows),
    'CAMPAIGN.WHATSAPP.DISPATCH.PREVIEW_ERROR'
  );
  if (res) preview.value = res.data;
};

const doUpload = async () => {
  const rows = parsedRows.value;
  if (!rows.length) return;
  const res = await run(
    'upload',
    () => CampaignsAPI.uploadRecipients(props.campaignId, rows),
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

    <!-- Lista -->
    <label class="block mb-1 text-xs font-medium text-n-slate-11">
      {{ t('CAMPAIGN.WHATSAPP.DISPATCH.LIST_LABEL') }}
    </label>
    <textarea
      v-model="listText"
      rows="5"
      :placeholder="t('CAMPAIGN.WHATSAPP.DISPATCH.LIST_PLACEHOLDER')"
      class="w-full px-3 py-2 text-sm border rounded-lg resize-y border-n-weak bg-n-alpha-1 text-n-slate-12 placeholder:text-n-slate-10"
    />

    <div class="flex flex-wrap items-center gap-3 mt-2">
      <input
        type="file"
        accept=".csv,.txt"
        class="text-xs text-n-slate-11 file:mr-2 file:px-2 file:py-1 file:text-xs file:border-0 file:rounded-md file:bg-n-alpha-2 file:text-n-slate-12"
        @change="onFile"
      />
      <span class="text-xs text-n-slate-10">
        {{
          t('CAMPAIGN.WHATSAPP.DISPATCH.PARSED', { count: parsedRows.length })
        }}
      </span>
      <div class="flex gap-2 ms-auto">
        <button
          class="px-3 py-1.5 text-sm font-medium rounded-lg bg-n-alpha-2 text-n-slate-12 disabled:opacity-50"
          :disabled="!parsedRows.length || busy === 'preview'"
          @click="doPreview"
        >
          {{ t('CAMPAIGN.WHATSAPP.DISPATCH.PREVIEW') }}
        </button>
        <button
          class="px-3 py-1.5 text-sm font-medium rounded-lg bg-n-brand text-white disabled:opacity-50"
          :disabled="!parsedRows.length || busy === 'upload'"
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
