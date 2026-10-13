<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import CampaignsAPI from 'dashboard/api/campaigns';
import Button from 'dashboard/components-next/button/Button.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';
import { dateFormat } from 'shared/helpers/timeHelper';
import { useAlert } from 'dashboard/composables';

// Quem NAO recebeu e por que. As contagens do painel dizem quantos falharam; sem o nome e o
// motivo o operador nao consegue corrigir o cadastro nem reenviar. O motivo ja chega
// traduzido do backend (mesmo texto do CSV); o codigo cru fica ao lado para diagnostico.
const props = defineProps({
  campaignId: { type: [String, Number], required: true },
});

const route = useRoute();
const { t } = useI18n();

const FILTERS = [null, 'failed', 'blocked'];
const filterIndex = ref(0);
const page = ref(1);
const rows = ref([]);
const meta = ref({ total: 0, per_page: 25 });
const loading = ref(false);
const exporting = ref(false);

const tabs = computed(() => [
  { label: t('CAMPAIGN.WHATSAPP.UNDELIVERED.FILTER.ALL') },
  { label: t('CAMPAIGN.WHATSAPP.UNDELIVERED.FILTER.FAILED') },
  { label: t('CAMPAIGN.WHATSAPP.UNDELIVERED.FILTER.BLOCKED') },
]);

const statusLabel = status =>
  t(`CAMPAIGN.WHATSAPP.UNDELIVERED.STATUS.${status.toUpperCase()}`);

const conversationRoute = id => ({
  name: 'inbox_conversation',
  params: { accountId: route.params.accountId, conversation_id: id },
});

const contactRoute = id => ({
  name: 'contacts_edit',
  params: { accountId: route.params.accountId, contactId: id },
});

const fetchRows = async () => {
  loading.value = true;
  try {
    const { data } = await CampaignsAPI.getUndelivered(props.campaignId, {
      type: FILTERS[filterIndex.value],
      page: page.value,
    });
    rows.value = data.payload;
    meta.value = data.meta;
  } catch (error) {
    useAlert(t('CAMPAIGN.WHATSAPP.UNDELIVERED.ERROR'));
  } finally {
    loading.value = false;
  }
};

const onTabChanged = tab => {
  filterIndex.value = tabs.value.findIndex(item => item.label === tab.label);
  page.value = 1;
};

const exportCsv = async () => {
  exporting.value = true;
  try {
    const { data } = await CampaignsAPI.exportUndelivered(
      props.campaignId,
      FILTERS[filterIndex.value]
    );
    downloadCsvFile(`campanha-${props.campaignId}-nao-enviados.csv`, data);
  } catch (error) {
    useAlert(t('CAMPAIGN.WHATSAPP.UNDELIVERED.EXPORT_ERROR'));
  } finally {
    exporting.value = false;
  }
};

watch([filterIndex, page], fetchRows);
onMounted(fetchRows);
</script>

<template>
  <div class="p-4 bg-white border rounded-xl border-n-weak dark:bg-n-solid-2">
    <div class="flex flex-wrap items-center justify-between gap-3 mb-3">
      <div class="min-w-0">
        <h2 class="text-sm font-medium text-n-slate-12">
          {{ t('CAMPAIGN.WHATSAPP.UNDELIVERED.TITLE') }}
        </h2>
        <p class="text-xs text-n-slate-11">
          {{ t('CAMPAIGN.WHATSAPP.UNDELIVERED.DESCRIPTION') }}
        </p>
      </div>
      <Button
        :label="t('CAMPAIGN.WHATSAPP.UNDELIVERED.EXPORT')"
        icon="i-lucide-download"
        size="sm"
        variant="outline"
        color="slate"
        :is-loading="exporting"
        :disabled="!meta.total"
        @click="exportCsv"
      />
    </div>

    <TabBar
      class="mb-3"
      :tabs="tabs"
      :initial-active-tab="filterIndex"
      @tab-changed="onTabChanged"
    />

    <div v-if="loading" class="flex justify-center py-6">
      <Spinner />
    </div>
    <p v-else-if="!rows.length" class="py-2 text-sm text-n-slate-10">
      {{ t('CAMPAIGN.WHATSAPP.UNDELIVERED.EMPTY') }}
    </p>
    <div v-else class="overflow-x-auto">
      <table class="w-full text-sm">
        <thead>
          <tr class="text-xs text-left text-n-slate-10">
            <th class="py-1 pr-3 font-normal">
              {{ t('CAMPAIGN.WHATSAPP.UNDELIVERED.TABLE.CONTACT') }}
            </th>
            <th class="py-1 pr-3 font-normal">
              {{ t('CAMPAIGN.WHATSAPP.UNDELIVERED.TABLE.STATUS') }}
            </th>
            <th class="py-1 pr-3 font-normal">
              {{ t('CAMPAIGN.WHATSAPP.UNDELIVERED.TABLE.REASON') }}
            </th>
            <th class="py-1 pr-3 font-normal">
              {{ t('CAMPAIGN.WHATSAPP.UNDELIVERED.TABLE.DATE') }}
            </th>
            <th class="py-1 font-normal text-right">
              {{ t('CAMPAIGN.WHATSAPP.UNDELIVERED.TABLE.OPEN') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in rows"
            :key="row.id"
            class="align-top border-b border-n-weak last:border-0"
          >
            <td class="py-2 pr-3">
              <div class="text-n-slate-12">{{ row.name || '—' }}</div>
              <div class="text-xs tabular-nums text-n-slate-11">
                {{ row.phone_number }}
              </div>
            </td>
            <td class="py-2 pr-3 text-xs whitespace-nowrap text-n-slate-11">
              {{ statusLabel(row.status) }}
            </td>
            <td class="py-2 pr-3 text-n-slate-12">
              {{ row.reason }}
              <code
                v-if="row.status === 'failed' && row.error !== row.reason"
                class="block text-xs break-all text-n-slate-10"
              >
                {{ row.error }}
              </code>
            </td>
            <td class="py-2 pr-3 text-xs whitespace-nowrap text-n-slate-11">
              {{ dateFormat(row.at, 'dd/MM/yyyy HH:mm') }}
            </td>
            <td class="py-2 text-right whitespace-nowrap">
              <router-link
                v-if="row.conversation_id"
                :to="conversationRoute(row.conversation_id)"
                class="text-xs text-n-brand hover:underline"
              >
                {{ t('CAMPAIGN.WHATSAPP.UNDELIVERED.OPEN_CONVERSATION') }}
              </router-link>
              <router-link
                v-else-if="row.contact_id"
                :to="contactRoute(row.contact_id)"
                class="text-xs text-n-brand hover:underline"
              >
                {{ t('CAMPAIGN.WHATSAPP.UNDELIVERED.OPEN_CONTACT') }}
              </router-link>
              <span v-else class="text-xs text-n-slate-10">—</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <PaginationFooter
      v-if="meta.total > meta.per_page"
      class="mt-3"
      :current-page="page"
      :total-items="meta.total"
      :items-per-page="meta.per_page"
      @update:current-page="page = $event"
    />
  </div>
</template>
