<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import LeadCampaignsAPI from 'dashboard/api/leadCampaigns';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CampaignLayout from 'dashboard/components-next/Campaigns/CampaignLayout.vue';

defineOptions({ name: 'LeadCampaignsPage' });

const { t } = useI18n();

const loading = ref(true);
const loadError = ref(false);
const payload = ref(null);
const de = ref('');
const ate = ref('');

const carregar = async () => {
  loading.value = true;
  loadError.value = false;
  try {
    const params = {};
    if (de.value) params.de = de.value;
    if (ate.value) params.ate = ate.value;
    const { data } = await LeadCampaignsAPI.show(params);
    payload.value = data;
  } catch (error) {
    loadError.value = true;
  } finally {
    loading.value = false;
  }
};

onMounted(carregar);

const habilitado = computed(() => payload.value?.habilitado === true);
const isAdmin = computed(() => payload.value?.admin === true);
const campanhas = computed(() => payload.value?.campanhas || []);
const totais = computed(() => payload.value?.totais || {});
const hooks = computed(() => payload.value?.hooks || []);

// Strings compostas ficam no script: texto solto no template (os separadores) é erro de
// lint no projeto, e nada pode escapar do i18n.
const SEPARADOR = ' · ';

const distribuicao = mapa =>
  Object.entries(mapa || {})
    .sort((a, b) => b[1] - a[1])
    .map(([nome, total]) => `${nome} ${total}`)
    .join(SEPARADOR);

const templatesEnviados = linha =>
  (linha.templates_enviados || [])
    .map(item => `${item.nome} ${item.leads}`)
    .join(SEPARADOR);

const semDado = t('CAMPAIGN.LEAD_ADS.EMPTY_VALUE');

const identificador = linha => linha.campaign_id || semDado;

const nomeCampanha = linha => linha.nome || t('CAMPAIGN.LEAD_ADS.NO_CAMPAIGN');

const atendimento = linha => {
  const partes = [linha.agente?.nome, linha.time?.nome].filter(Boolean);
  return partes.length ? partes.join(SEPARADOR) : semDado;
};

const rotuloOrigem = linha => {
  if (linha.origem === 'override')
    return t('CAMPAIGN.LEAD_ADS.SOURCE.OVERRIDE');
  if (linha.origem === 'padrao') return t('CAMPAIGN.LEAD_ADS.SOURCE.DEFAULT');
  return t('CAMPAIGN.LEAD_ADS.SOURCE.UNKNOWN');
};

// Os tokens `n-*` já viram do tema (claro/escuro) sozinhos — não precisam de par `dark:`.
const classeOrigem = linha =>
  linha.origem === 'override'
    ? 'bg-n-teal-3 text-n-teal-11'
    : 'bg-n-alpha-2 text-n-slate-11';

// Template configurado que o canal não conhece: a abertura simplesmente não sai, e hoje
// isso só aparece no log do worker.
const templateAusente = linha =>
  Boolean(linha.template) && linha.template_sincronizado === false;

const resumoHook = hook =>
  [hook.pagina, hook.inbox?.name, hook.template]
    .filter(Boolean)
    .join(SEPARADOR);
</script>

<template>
  <CampaignLayout :header-title="t('CAMPAIGN.LEAD_ADS.HEADER_TITLE')">
    <div class="flex flex-col gap-5">
      <div class="flex flex-wrap items-end justify-between gap-3">
        <p class="max-w-xl text-sm text-n-slate-11">
          {{ t('CAMPAIGN.LEAD_ADS.SUBTITLE') }}
        </p>
        <div class="flex flex-wrap items-end gap-2">
          <label class="flex flex-col gap-1 text-xs text-n-slate-10">
            {{ t('CAMPAIGN.LEAD_ADS.FILTER.FROM') }}
            <input
              v-model="de"
              type="date"
              class="h-9 px-2 text-sm bg-white border rounded-lg dark:bg-n-solid-2 border-n-weak text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1 text-xs text-n-slate-10">
            {{ t('CAMPAIGN.LEAD_ADS.FILTER.TO') }}
            <input
              v-model="ate"
              type="date"
              class="h-9 px-2 text-sm bg-white border rounded-lg dark:bg-n-solid-2 border-n-weak text-n-slate-12"
            />
          </label>
          <button
            type="button"
            class="h-9 px-3 text-sm text-white rounded-lg bg-n-brand transition-shadow hover:shadow-md"
            @click="carregar"
          >
            {{ t('CAMPAIGN.LEAD_ADS.FILTER.APPLY') }}
          </button>
        </div>
      </div>

      <div
        v-if="loading"
        class="flex items-center justify-center py-10 text-n-slate-11"
      >
        <Spinner />
      </div>

      <p v-else-if="loadError" class="py-10 text-sm text-center text-n-ruby-11">
        {{ t('CAMPAIGN.LEAD_ADS.ERROR') }}
      </p>

      <div
        v-else-if="!habilitado"
        class="px-6 py-10 text-center bg-white border rounded-xl dark:bg-n-solid-2 border-n-weak"
      >
        <p class="text-sm font-medium text-n-slate-12">
          {{ t('CAMPAIGN.LEAD_ADS.DISABLED.TITLE') }}
        </p>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ t('CAMPAIGN.LEAD_ADS.DISABLED.SUBTITLE') }}
        </p>
      </div>

      <template v-else>
        <section class="flex flex-wrap gap-3">
          <div
            class="px-4 py-3 bg-white border rounded-xl dark:bg-n-solid-2 border-n-weak"
          >
            <p class="text-xs uppercase text-n-slate-10">
              {{ t('CAMPAIGN.LEAD_ADS.TOTALS.LEADS') }}
            </p>
            <p class="text-2xl font-medium text-n-slate-12">
              {{ totais.leads || 0 }}
            </p>
          </div>
          <div
            class="px-4 py-3 bg-white border rounded-xl dark:bg-n-solid-2 border-n-weak"
          >
            <p class="text-xs uppercase text-n-slate-10">
              {{ t('CAMPAIGN.LEAD_ADS.TOTALS.CAMPAIGNS') }}
            </p>
            <p class="text-2xl font-medium text-n-slate-12">
              {{ totais.campanhas || 0 }}
            </p>
          </div>
          <div
            v-for="hook in hooks"
            :key="hook.id"
            class="px-4 py-3 bg-white border rounded-xl dark:bg-n-solid-2 border-n-weak"
          >
            <p class="text-xs uppercase text-n-slate-10">
              {{
                hook.habilitado
                  ? t('CAMPAIGN.LEAD_ADS.HOOK.ACTIVE')
                  : t('CAMPAIGN.LEAD_ADS.HOOK.INACTIVE')
              }}
            </p>
            <p class="text-sm font-medium text-n-slate-12">{{ hook.app_id }}</p>
            <p class="text-xs text-n-slate-11">{{ resumoHook(hook) }}</p>
          </div>
        </section>

        <p
          v-if="campanhas.length === 0"
          class="px-6 py-10 text-sm text-center bg-white border rounded-xl dark:bg-n-solid-2 border-n-weak text-n-slate-11"
        >
          {{ t('CAMPAIGN.LEAD_ADS.EMPTY_PERIOD') }}
        </p>

        <section v-else class="overflow-x-auto">
          <table class="w-full text-sm border rounded-xl border-n-weak">
            <thead class="bg-n-solid-1 dark:bg-n-solid-2 text-n-slate-11">
              <tr>
                <th class="px-3 py-2 font-medium text-left">
                  {{ t('CAMPAIGN.LEAD_ADS.TABLE.CAMPAIGN') }}
                </th>
                <th class="px-3 py-2 font-medium text-right">
                  {{ t('CAMPAIGN.LEAD_ADS.TABLE.LEADS') }}
                </th>
                <th v-if="isAdmin" class="px-3 py-2 font-medium text-left">
                  {{ t('CAMPAIGN.LEAD_ADS.TABLE.CONFIGURED_TEMPLATE') }}
                </th>
                <th class="px-3 py-2 font-medium text-left">
                  {{ t('CAMPAIGN.LEAD_ADS.TABLE.SENT_TEMPLATE') }}
                </th>
                <th v-if="isAdmin" class="px-3 py-2 font-medium text-left">
                  {{ t('CAMPAIGN.LEAD_ADS.TABLE.ASSIGNED_TO') }}
                </th>
                <th class="px-3 py-2 font-medium text-left">
                  {{ t('CAMPAIGN.LEAD_ADS.TABLE.LEAD_TYPE') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(linha, indice) in campanhas"
                :key="`${linha.campaign_id || linha.nome}-${indice}`"
                class="border-t border-n-weak"
              >
                <td class="px-3 py-2 align-top">
                  <p class="font-medium text-n-slate-12">
                    {{ nomeCampanha(linha) }}
                  </p>
                  <p class="text-xs text-n-slate-10">
                    {{ identificador(linha) }}
                  </p>
                  <p class="flex flex-wrap gap-1 mt-1">
                    <span
                      v-if="isAdmin"
                      class="px-1.5 py-0.5 text-xs rounded"
                      :class="classeOrigem(linha)"
                    >
                      {{ rotuloOrigem(linha) }}
                    </span>
                    <span
                      v-if="linha.bloqueada"
                      class="px-1.5 py-0.5 text-xs rounded bg-n-amber-3 text-n-amber-11"
                    >
                      {{ t('CAMPAIGN.LEAD_ADS.TABLE.BLOCKED') }}
                    </span>
                    <span
                      v-if="linha.id_ambiguo"
                      class="px-1.5 py-0.5 text-xs rounded bg-n-alpha-2 text-n-slate-11"
                    >
                      {{ t('CAMPAIGN.LEAD_ADS.TABLE.AMBIGUOUS_ID') }}
                    </span>
                  </p>
                </td>
                <td
                  class="px-3 py-2 font-medium text-right align-top text-n-slate-12"
                >
                  {{ linha.leads }}
                </td>
                <td v-if="isAdmin" class="px-3 py-2 align-top text-n-slate-11">
                  <span>{{ linha.template || semDado }}</span>
                  <span
                    v-if="templateAusente(linha)"
                    class="block text-xs text-n-ruby-11"
                  >
                    {{ t('CAMPAIGN.LEAD_ADS.TABLE.TEMPLATE_MISSING') }}
                  </span>
                </td>
                <td class="px-3 py-2 align-top text-n-slate-11">
                  {{ templatesEnviados(linha) || semDado }}
                </td>
                <td v-if="isAdmin" class="px-3 py-2 align-top text-n-slate-11">
                  {{ atendimento(linha) }}
                </td>
                <td class="px-3 py-2 align-top text-n-slate-11">
                  {{ distribuicao(linha.tipos) || semDado }}
                </td>
              </tr>
            </tbody>
          </table>
        </section>

        <p class="text-xs text-n-slate-10">
          {{ t('CAMPAIGN.LEAD_ADS.FOOTNOTE') }}
        </p>
      </template>
    </div>
  </CampaignLayout>
</template>
