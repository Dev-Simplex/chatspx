<script setup>
import BaseHeatmapContainer from './BaseHeatmapContainer.vue';

defineProps({
  scopeInboxId: {
    type: [Number, null],
    default: null,
  },
});
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
</script>

<template>
  <BaseHeatmapContainer
    :scope-inbox-id="scopeInboxId"
    metric="conversations_count"
    :title="t('OVERVIEW_REPORTS.CONVERSATION_HEATMAP.HEADER')"
    download-title="conversation_heatmap"
    store-getter="getAccountConversationHeatmapData"
    store-action="fetchAccountConversationHeatmap"
    download-action="downloadAccountConversationHeatmap"
    ui-flag-key="isFetchingAccountConversationsHeatmap"
  />
</template>
