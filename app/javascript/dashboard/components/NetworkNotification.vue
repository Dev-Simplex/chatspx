<script setup>
import { ref, computed, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useEmitter } from 'dashboard/composables/emitter';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import {
  isAConversationRoute,
  isAInboxViewRoute,
  isNotificationRoute,
} from 'dashboard/helper/routeHelpers';
import { useEventListener } from '@vueuse/core';
import {
  useConnectionStatus,
  GRACE_MS,
  SUSTAINED_MS,
} from 'dashboard/composables/useConnectionStatus';

import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const route = useRoute();

const RECONNECTED_BANNER_TIMEOUT = 2000;

// N2 compartilhado (barra do topo + hint no composer). Este componente é o dono
// dos relógios da escalada; a barra e o hint só leem o ref.
const { isSustainedOffline } = useConnectionStatus();

const showNotification = ref(!navigator.onLine);
const isDisconnected = ref(false);
const isReconnecting = ref(false);
const isReconnected = ref(false);
let reconnectTimeout = null;
// Escalada offline: só pintamos o pill (N1) depois de GRACE_MS caído e escalamos
// para a barra do topo (N2, via isSustainedOffline) depois de SUSTAINED_MS.
// Reconexão sub-GRACE_MS nunca acende nada.
let graceTimer = null;
let sustainedTimer = null;

const clearOfflineTimers = () => {
  clearTimeout(graceTimer);
  clearTimeout(sustainedTimer);
  graceTimer = null;
  sustainedTimer = null;
};

const bannerText = computed(() => {
  if (isReconnecting.value) return t('NETWORK.NOTIFICATION.RECONNECTING');
  if (isReconnected.value) return t('NETWORK.NOTIFICATION.RECONNECT_SUCCESS');
  return t('NETWORK.NOTIFICATION.OFFLINE');
});

const iconName = computed(() => (isReconnected.value ? 'wifi' : 'wifi-off'));
const canRefresh = computed(
  () => !isReconnecting.value && !isReconnected.value
);

// O pill (N1) recolhe quando a queda escala para a barra do topo (N2), para não
// duplicar indicadores — mas o transitório "Reconectando…/Reconectado" é sempre
// mostrado no pill.
const showPill = computed(
  () =>
    showNotification.value &&
    (!isSustainedOffline.value || isReconnecting.value || isReconnected.value)
);

const refreshPage = () => {
  window.location.reload();
};

const closeNotification = () => {
  showNotification.value = false;
  isReconnected.value = false;
  isSustainedOffline.value = false;
  clearOfflineTimers();
  clearTimeout(reconnectTimeout);
};

const isInAnyOfTheRoutes = routeName => {
  return (
    isAConversationRoute(routeName, true) ||
    isAInboxViewRoute(routeName, true) ||
    isNotificationRoute(routeName, true)
  );
};

const updateWebsocketStatus = () => {
  const wasAlreadyDown = isDisconnected.value;
  isDisconnected.value = true;
  // Queda já em curso: não reinicia os relógios (senão grace/sustained nunca
  // "vencem" sob disconnects repetidos da lib).
  if (wasAlreadyDown || graceTimer || sustainedTimer) return;
  graceTimer = setTimeout(() => {
    graceTimer = null;
    if (isDisconnected.value) showNotification.value = true; // N1 (pill)
  }, GRACE_MS);
  sustainedTimer = setTimeout(() => {
    sustainedTimer = null;
    if (isDisconnected.value) {
      showNotification.value = true;
      isSustainedOffline.value = true; // N2 (barra do topo + hint no composer)
    }
  }, SUSTAINED_MS);
};

const handleReconnectionCompleted = () => {
  clearOfflineTimers();
  isDisconnected.value = false;
  isReconnecting.value = false;
  isSustainedOffline.value = false;
  isReconnected.value = true;
  showNotification.value = true;
  reconnectTimeout = setTimeout(closeNotification, RECONNECTED_BANNER_TIMEOUT);
};

const handleReconnecting = () => {
  // O socket reabriu (refetch em curso). Para a escalada e recolhe a barra N2;
  // o pill assume o transitório "Reconectando…".
  clearOfflineTimers();
  isSustainedOffline.value = false;
  if (isInAnyOfTheRoutes(route.name)) {
    isReconnecting.value = true;
    isReconnected.value = false;
    showNotification.value = true;
  } else {
    handleReconnectionCompleted();
  }
};

const updateOnlineStatus = event => {
  // Case: Websocket is not disconnected
  // If the app goes offline, show the notification
  // If the app goes online, close the notification

  // Case: Websocket is disconnected
  // If the app goes offline, show the notification
  // If the app goes online but the websocket is disconnected, don't close the notification
  // If the app goes online and the websocket is not disconnected, close the notification

  if (event.type === 'offline') {
    showNotification.value = true;
  } else if (event.type === 'online' && !isDisconnected.value) {
    handleReconnectionCompleted();
  }
};

useEventListener('online', updateOnlineStatus);
useEventListener('offline', updateOnlineStatus);
useEmitter(BUS_EVENTS.WEBSOCKET_DISCONNECT, updateWebsocketStatus);
useEmitter(
  BUS_EVENTS.WEBSOCKET_RECONNECT_COMPLETED,
  handleReconnectionCompleted
);
useEmitter(BUS_EVENTS.WEBSOCKET_RECONNECT, handleReconnecting);

onBeforeUnmount(() => {
  clearTimeout(reconnectTimeout);
  clearOfflineTimers();
});
</script>

<template>
  <transition name="network-notification-fade" tag="div">
    <div
      v-show="showPill"
      data-testid="network-pill"
      class="fixed z-50 top-2 left-2 group"
    >
      <div
        class="relative flex items-center justify-between w-full px-2 py-1 bg-n-amber-4 dark:bg-n-amber-8 rounded-lg shadow-lg"
      >
        <fluent-icon :icon="iconName" class="text-n-amber-12" size="18" />
        <span class="px-2 text-xs font-medium tracking-wide text-n-amber-12">
          {{ bannerText }}
        </span>
        <Button
          v-if="canRefresh"
          ghost
          sm
          amber
          icon="i-lucide-refresh-ccw"
          :title="$t('NETWORK.BUTTON.REFRESH')"
          class="!text-n-amber-12 dark:!text-n-amber-9"
          @click="refreshPage"
        />

        <Button
          ghost
          sm
          amber
          icon="i-lucide-x"
          class="!text-n-amber-12 dark:!text-n-amber-9"
          @click="closeNotification"
        />
      </div>
    </div>
  </transition>
</template>
