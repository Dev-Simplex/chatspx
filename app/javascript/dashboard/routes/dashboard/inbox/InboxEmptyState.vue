<script setup>
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
// Mesma tela vazia do dashboard (logo da marca, nome da instalação, rodapé de
// criptografia). Reusar em vez de copiar mantém as duas idênticas sozinhas.
import EmptyStateMessage from 'dashboard/components/widgets/conversation/EmptyState/EmptyStateMessage.vue';

defineProps({
  emptyStateMessage: {
    type: String,
    default: '',
  },
});

const { t } = useI18n();
const uiFlags = useMapGetter('notifications/getUIFlags');
</script>

<template>
  <div class="hidden w-full h-full bg-n-surface-1 lg:block">
    <div
      v-if="uiFlags.isFetching"
      class="flex items-center justify-center h-full"
    >
      <Spinner class="text-n-brand" />
    </div>
    <EmptyStateMessage
      v-else
      :message="emptyStateMessage || t('INBOX.LIST.NOTE')"
    />
  </div>
</template>
