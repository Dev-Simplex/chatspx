<script setup>
import { ref, onMounted, onBeforeUnmount, computed, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import CampaignsAPI from 'dashboard/api/campaigns';
import StatsCard from 'dashboard/components-next/agents/StatsCard.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import DispatchPanel from 'dashboard/components-next/Campaigns/DispatchPanel.vue';
import DispatchSettings from 'dashboard/components-next/Campaigns/DispatchSettings.vue';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  campaignId: { type: [String, Number], default: null },
});

const route = useRoute();
const router = useRouter();
const { t, te } = useI18n();

const loading = ref(true);
const data = ref(null);
// Sobe do formulário do motor para o painel de disparo: iniciar com a configuração
// antiga, achando que salvou, é o erro que esta tela não pode deixar passar calado.
const settingsDirty = ref(false);

const campaignId = computed(() => props.campaignId || route.params.campaignId);

// Só vale enquanto a campanha está parada por ele: o Iniciar limpa o motivo no backend.
const startError = computed(() =>
  data.value?.dispatch_status === 'failed'
    ? data.value?.campaign?.dispatch_config?.start_error
    : null
);

const KNOWN_CODES = ['131026', '130472', '131049', 'outro'];
// Codigo fora da lista aparecia sozinho, cru, como `131052` — identificador tecnico nao e
// informacao de atendimento neste produto. Agora ele sempre vem acompanhado de uma frase,
// nem que seja a de "nao catalogado": o numero serve para diagnosticar, o texto para ler.
const codeLabel = code =>
  KNOWN_CODES.includes(code)
    ? t(`CAMPAIGN.WHATSAPP.DETAIL.CODES.${code}`)
    : t('CAMPAIGN.WHATSAPP.DETAIL.CODES.unknown');

// `data.campaign.status` e `c.status` chegam como enum CRU do Rails e eram renderizados
// com `capitalize`: no topo da pagina havia uma pilula traduzida ("Disparando") a seis
// pixels de outra em ingles ("completed"), descrevendo conceitos diferentes e as duas
// chamadas de "status". Mapas explicitos, com o valor cru como ultimo recurso.
const campaignStatusLabel = code =>
  te(`CAMPAIGN.WHATSAPP.DETAIL.CAMPAIGN_STATUS.${code}`)
    ? t(`CAMPAIGN.WHATSAPP.DETAIL.CAMPAIGN_STATUS.${code}`)
    : code;

const conversationStatusLabel = code =>
  te(`CAMPAIGN.WHATSAPP.DETAIL.CONVERSATION_STATUS.${code}`)
    ? t(`CAMPAIGN.WHATSAPP.DETAIL.CONVERSATION_STATUS.${code}`)
    : code;

// `silent` evita piscar a tela inteira no polling do disparo em andamento.
const fetchStats = async ({ silent = false } = {}) => {
  if (!silent) loading.value = true;
  try {
    const res = await CampaignsAPI.getStats(campaignId.value);
    data.value = res.data;
  } catch (error) {
    useAlert(t('CAMPAIGN.WHATSAPP.DETAIL.ERROR'));
  } finally {
    loading.value = false;
  }
};

// O scheduler despacha um lote por minuto; 10s e o suficiente pra tela parecer viva
// sem martelar o servidor. So roda enquanto o disparo esta de fato correndo.
const POLL_MS = 10000;
let pollTimer = null;

const stopPolling = () => {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
};

watch(
  () => data.value?.dispatch_status,
  status => {
    stopPolling();
    if (status === 'running') {
      pollTimer = setInterval(() => fetchStats({ silent: true }), POLL_MS);
    }
  }
);

const goBack = () =>
  router.push({
    name: 'campaigns_whatsapp_index',
    params: { accountId: route.params.accountId },
  });

onMounted(fetchStats);
onBeforeUnmount(stopPolling);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-y-auto bg-n-surface-1">
    <div class="w-full max-w-5xl px-6 py-6 mx-auto">
      <button
        class="flex items-center gap-1 mb-4 text-sm text-n-slate-11 hover:text-n-slate-12"
        @click="goBack"
      >
        <i class="i-lucide-arrow-left size-4" />
        {{ t('CAMPAIGN.WHATSAPP.DETAIL.BACK') }}
      </button>

      <div v-if="loading" class="flex justify-center py-16">
        <Spinner />
      </div>

      <template v-else-if="data">
        <div class="flex items-start justify-between gap-3 mb-6">
          <div class="min-w-0">
            <h1 class="text-xl font-semibold truncate text-n-slate-12">
              {{ data.campaign.title }}
            </h1>
            <p class="text-sm text-n-slate-11">
              {{
                t('CAMPAIGN.WHATSAPP.DETAIL.DELIVERY_RATE', {
                  rate: data.delivery_rate,
                })
              }}
              ·
              {{
                t('CAMPAIGN.WHATSAPP.DETAIL.READ_RATE', {
                  rate: data.read_rate,
                })
              }}
            </p>
          </div>
          <span
            class="px-2 py-1 text-xs font-medium rounded-md shrink-0 bg-n-alpha-2 text-n-slate-11"
          >
            {{ campaignStatusLabel(data.campaign.status) }}
          </span>
        </div>

        <div class="grid grid-cols-2 gap-3 mb-6 md:grid-cols-5">
          <StatsCard
            :value="data.total"
            :label="t('CAMPAIGN.WHATSAPP.DETAIL.KPI.TOTAL')"
            fallback-icon="i-lucide-send"
          />
          <StatsCard
            :value="data.reached"
            :label="t('CAMPAIGN.WHATSAPP.DETAIL.KPI.REACHED')"
            fallback-icon="i-lucide-check-check"
          />
          <StatsCard
            :value="data.read"
            :label="t('CAMPAIGN.WHATSAPP.DETAIL.KPI.READ')"
            fallback-icon="i-lucide-eye"
          />
          <StatsCard
            :value="data.replied"
            :label="t('CAMPAIGN.WHATSAPP.DETAIL.KPI.REPLIED')"
            fallback-icon="i-lucide-message-circle"
          />
          <StatsCard
            :value="data.failed"
            :label="t('CAMPAIGN.WHATSAPP.DETAIL.KPI.FAILED')"
            fallback-icon="i-lucide-triangle-alert"
          />
        </div>

        <DispatchSettings
          class="mb-6"
          :campaign-id="campaignId"
          :campaign="data.campaign"
          @changed="fetchStats({ silent: true })"
          @dirty="settingsDirty = $event"
        />
        <!-- Agendamento que chegou na hora sem o que o Iniciar exige: o scheduler nao
             dispara e deixa o motivo aqui, em vez de a campanha ficar muda. -->
        <p
          v-if="startError"
          role="alert"
          class="px-4 py-3 mb-6 text-sm border rounded-xl border-n-ruby-6 bg-n-ruby-2 text-n-ruby-11"
        >
          {{
            t('CAMPAIGN.WHATSAPP.DISPATCH.START_BLOCKED', {
              reason: startError,
            })
          }}
        </p>
        <DispatchPanel
          class="mb-6"
          :campaign-id="campaignId"
          :dispatch-status="data.dispatch_status"
          :recipients="data.recipients"
          :campaign="data.campaign"
          :dispatch-preview="data.dispatch_preview"
          :settings-dirty="settingsDirty"
          @changed="fetchStats({ silent: true })"
        />

        <div class="grid grid-cols-1 gap-4 mb-6 md:grid-cols-2">
          <div
            class="p-4 bg-white border rounded-xl border-n-weak dark:bg-n-solid-2"
          >
            <h2 class="mb-3 text-sm font-medium text-n-slate-12">
              {{ t('CAMPAIGN.WHATSAPP.DETAIL.DISTRIBUTION') }}
            </h2>
            <!-- As chaves DETAIL.AGENT/COUNT/CODE/REASON existiam traduzidas nos dois
                 idiomas e nao eram referenciadas por markup nenhum: as tabelas subiam sem
                 <thead>. Agora sao usadas. -->
            <table class="w-full text-sm">
              <thead>
                <tr class="text-xs text-left text-n-slate-10">
                  <th class="py-1 font-normal">
                    {{ t('CAMPAIGN.WHATSAPP.DETAIL.AGENT') }}
                  </th>
                  <th class="py-1 font-normal text-right">
                    {{ t('CAMPAIGN.WHATSAPP.DETAIL.COUNT') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="d in data.distribution"
                  :key="d.id"
                  class="border-b border-n-weak last:border-0"
                >
                  <td class="py-2 text-n-slate-12">{{ d.name }}</td>
                  <td
                    class="py-2 font-medium text-right tabular-nums text-n-slate-12"
                  >
                    {{ d.count }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div
            class="p-4 bg-white border rounded-xl border-n-weak dark:bg-n-solid-2"
          >
            <h2 class="mb-3 text-sm font-medium text-n-slate-12">
              {{ t('CAMPAIGN.WHATSAPP.DETAIL.FAILURES') }}
            </h2>
            <table class="w-full text-sm">
              <thead>
                <tr class="text-xs text-left text-n-slate-10">
                  <th class="py-1 font-normal">
                    {{ t('CAMPAIGN.WHATSAPP.DETAIL.REASON') }}
                  </th>
                  <th class="py-1 font-normal text-right">
                    {{ t('CAMPAIGN.WHATSAPP.DETAIL.COUNT') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="f in data.failures"
                  :key="f.code"
                  class="border-b border-n-weak last:border-0"
                >
                  <td class="py-2 text-n-slate-11">
                    {{ codeLabel(f.code) }}
                    <code class="text-xs text-n-slate-10">{{ f.code }}</code>
                  </td>
                  <td
                    class="py-2 font-medium text-right tabular-nums text-n-slate-12"
                  >
                    {{ f.count }}
                  </td>
                </tr>
                <tr v-if="!data.failures.length">
                  <td class="py-2 text-n-slate-10" colspan="2">
                    {{ t('CAMPAIGN.WHATSAPP.DETAIL.NO_FAILURES') }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div
          class="p-4 bg-white border rounded-xl border-n-weak dark:bg-n-solid-2"
        >
          <h2 class="mb-3 text-sm font-medium text-n-slate-12">
            {{ t('CAMPAIGN.WHATSAPP.DETAIL.CONVERSATIONS') }}
          </h2>
          <table class="w-full text-sm">
            <thead>
              <tr class="text-xs text-left text-n-slate-10">
                <th class="py-1 font-normal">
                  {{ t('CAMPAIGN.WHATSAPP.DETAIL.TABLE.CONTACT') }}
                </th>
                <th class="py-1 font-normal">
                  {{ t('CAMPAIGN.WHATSAPP.DETAIL.TABLE.LAST_REPLY') }}
                </th>
                <th class="py-1 font-normal">
                  {{ t('CAMPAIGN.WHATSAPP.DETAIL.AGENT') }}
                </th>
                <th class="py-1 font-normal">
                  {{ t('CAMPAIGN.WHATSAPP.DETAIL.TABLE.STATUS') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="c in data.recent"
                :key="c.id"
                class="border-b border-n-weak last:border-0"
              >
                <td class="py-2 whitespace-nowrap text-n-slate-12">
                  {{ c.name || '—' }}
                </td>
                <td class="max-w-xs py-2 truncate text-n-slate-11">
                  {{ c.last_reply }}
                </td>
                <td class="py-2 whitespace-nowrap text-n-slate-11">
                  {{ c.agent || t('CAMPAIGN.WHATSAPP.DETAIL.NO_AGENT') }}
                </td>
                <td class="py-2 text-xs text-n-slate-10">
                  {{ conversationStatusLabel(c.status) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </template>
    </div>
  </section>
</template>
