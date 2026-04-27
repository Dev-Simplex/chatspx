<script setup>
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert, useTrack } from 'dashboard/composables';
import { CAMPAIGN_TYPES } from 'shared/constants/campaign.js';
import { CAMPAIGNS_EVENTS } from 'dashboard/helper/AnalyticsHelper/events.js';

import WhatsAppCampaignForm from 'dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/WhatsAppCampaignForm.vue';

const emit = defineEmits(['close']);

const store = useStore();
const { t } = useI18n();

const addCampaign = async campaignDetails => {
  try {
    await store.dispatch('campaigns/create', campaignDetails);

    useTrack(CAMPAIGNS_EVENTS.CREATE_CAMPAIGN, {
      type: CAMPAIGN_TYPES.ONE_OFF,
    });

    useAlert(t('CAMPAIGN.WHATSAPP.CREATE.FORM.API.SUCCESS_MESSAGE'));
  } catch (error) {
    const errorMessage =
      error?.response?.message ||
      t('CAMPAIGN.WHATSAPP.CREATE.FORM.API.ERROR_MESSAGE');
    useAlert(errorMessage);
  }
};

const handleSubmit = campaignDetails => {
  addCampaign(campaignDetails);
};

const handleClose = () => emit('close');
</script>

<template>
  <div
    class="w-[25rem] z-50 min-w-0 absolute top-10 ltr:right-0 rtl:left-0 bg-n-solid-1 dark:bg-[#233138] rounded-lg border border-[var(--wa-list-border)] dark:border-[var(--wa-list-border-dark)] shadow-[0_2px_8px_rgba(11,20,26,0.12)] max-h-[80vh] overflow-y-auto"
  >
    <div class="p-6 flex flex-col gap-6">
      <h3 class="text-base font-medium text-n-slate-12 flex-shrink-0">
        {{ t(`CAMPAIGN.WHATSAPP.CREATE.TITLE`) }}
      </h3>
      <WhatsAppCampaignForm @submit="handleSubmit" @cancel="handleClose" />
    </div>
  </div>
</template>
