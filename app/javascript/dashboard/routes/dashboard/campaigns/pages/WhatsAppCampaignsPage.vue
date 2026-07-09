<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useToggle } from '@vueuse/core';
import { useStoreGetters, useMapGetter } from 'dashboard/composables/store';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CampaignLayout from 'dashboard/components-next/Campaigns/CampaignLayout.vue';
import CampaignList from 'dashboard/components-next/Campaigns/Pages/CampaignPage/CampaignList.vue';
import WhatsAppCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/WhatsAppCampaignDialog.vue';
import ConfirmDeleteCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/ConfirmDeleteCampaignDialog.vue';
import WhatsAppCampaignEmptyState from 'dashboard/components-next/Campaigns/EmptyState/WhatsAppCampaignEmptyState.vue';

// O disparo em massa segue pelo orquestrador SPX (pacing, atribuicao por corretor,
// rotacao de template) — o blaster nativo continua DESATIVADO (Campaign#execute_campaign
// e no-op para WhatsApp). Criar campanha aqui registra/agenda sem disparar nada.

const { t } = useI18n();
const getters = useStoreGetters();
const route = useRoute();
const router = useRouter();

const [showWhatsAppCampaignDialog, toggleWhatsAppCampaignDialog] = useToggle();

const selectedCampaign = ref(null);

const uiFlags = useMapGetter('campaigns/getUIFlags');
const isFetchingCampaigns = computed(() => uiFlags.value.isFetching);

const confirmDeleteCampaignDialogRef = ref(null);

const WhatsAppCampaigns = computed(
  () => getters['campaigns/getWhatsAppCampaigns'].value
);

const hasNoWhatsAppCampaigns = computed(
  () => WhatsAppCampaigns.value?.length === 0 && !isFetchingCampaigns.value
);

const handleDelete = campaign => {
  selectedCampaign.value = campaign;
  confirmDeleteCampaignDialogRef.value.dialogRef.open();
};

const goToDetail = campaign => {
  router.push({
    name: 'campaigns_whatsapp_detail',
    params: {
      accountId: route.params.accountId,
      campaignId: campaign.id,
    },
  });
};
</script>

<template>
  <CampaignLayout
    :header-title="t('CAMPAIGN.WHATSAPP.HEADER_TITLE')"
    :button-label="t('CAMPAIGN.WHATSAPP.NEW_CAMPAIGN')"
    @click="toggleWhatsAppCampaignDialog()"
    @close="toggleWhatsAppCampaignDialog(false)"
  >
    <template #action>
      <WhatsAppCampaignDialog
        v-if="showWhatsAppCampaignDialog"
        @close="toggleWhatsAppCampaignDialog(false)"
      />
    </template>
    <div
      v-if="isFetchingCampaigns"
      class="flex items-center justify-center py-10 text-n-slate-11"
    >
      <Spinner />
    </div>
    <CampaignList
      v-else-if="!hasNoWhatsAppCampaigns"
      :campaigns="WhatsAppCampaigns"
      show-view
      @delete="handleDelete"
      @view="goToDetail"
    />
    <WhatsAppCampaignEmptyState
      v-else
      :title="t('CAMPAIGN.WHATSAPP.EMPTY_STATE.TITLE')"
      :subtitle="t('CAMPAIGN.WHATSAPP.EMPTY_STATE.SUBTITLE')"
      class="pt-14"
    />
    <ConfirmDeleteCampaignDialog
      ref="confirmDeleteCampaignDialogRef"
      :selected-campaign="selectedCampaign"
    />
  </CampaignLayout>
</template>
