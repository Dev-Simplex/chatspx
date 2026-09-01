<script setup>
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert, useTrack } from 'dashboard/composables';
import { INBOX_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';

import NextButton from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const store = useStore();

// A ação é em massa e não tem desfazer em lote — por isso o botão só aparece
// quando existe o que marcar. Sem isso ele viraria um clique morto na maior
// parte do tempo, que é o estado normal desta tela.
const hasUnread = useMapGetter('notifications/getHasUnreadNotifications');
const uiFlags = useMapGetter('notifications/getUIFlags');

async function markAllRead() {
  useTrack(INBOX_EVENTS.MARK_ALL_NOTIFICATIONS_AS_READ);
  try {
    await store.dispatch('notifications/readAll');
    useAlert(t('INBOX.ALERTS.MARK_ALL_READ'));
  } catch {
    useAlert(t('INBOX.ALERTS.MARK_ALL_READ_ERROR'));
  }
}
</script>

<template>
  <div
    class="flex items-center justify-between w-full gap-1 h-[3.25rem] ltr:pl-4 rtl:pr-4 ltr:pr-3 rtl:pl-3"
  >
    <div class="flex items-center gap-2 min-w-0 flex-1">
      <h1 class="text-heading-2 truncate text-n-slate-12 min-w-0">
        {{ $t('INBOX.LIST.TITLE') }}
      </h1>
    </div>
    <!-- Dos três itens do menu de ações em massa que existiam aqui (marcar
         todas, excluir todas, excluir lidas), só volta o de marcar: os de
         excluir contradizem o comportamento WhatsApp-like desta tela, em que a
         notificação some sozinha quando a conversa é aberta. Com uma ação só,
         botão direto lê melhor que menu de um item — e com rótulo, não só
         ícone: é ação rara, e ícone sozinho não se explica. -->
    <NextButton
      v-if="hasUnread"
      sm
      ghost
      slate
      icon="i-lucide-check-check"
      :label="$t('INBOX.MENU_ITEM.MARK_ALL_READ')"
      :is-loading="uiFlags.isUpdating"
      class="flex-shrink-0"
      data-testid="inbox-mark-all-read"
      @click="markAllRead"
    />
  </div>
</template>
