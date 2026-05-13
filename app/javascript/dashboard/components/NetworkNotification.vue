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

const { t } = useI18n();
const route = useRoute();

// Reconexões mais rápidas que isso nunca chegam a aparecer ao usuário.
// 3s cobre a grande maioria dos blips de WebSocket sem perda real.
const SHOW_AFTER_DISCONNECT_MS = 3000;
// Browsers throttle conexões em abas ocultas. Ao voltar, suprimimos
// qualquer aviso por essa janela pra evitar o flash de "Desconectado"
// que é só ruído da reconexão normal.
const VISIBILITY_GRACE_MS = 5000;
// Quanto tempo o status "Conectado" fica visível depois do reconnect.
const RECONNECTED_BANNER_TIMEOUT = 2000;

const showNotification = ref(!navigator.onLine);
const isDisconnected = ref(false);
const isReconnecting = ref(false);
const isReconnected = ref(false);
// Se o usuário chegou a ver o aviso — suprime a confirmação "Conectado"
// quando a desconexão foi tão rápida que nunca foi exibida.
const wasNotificationVisible = ref(!navigator.onLine);
// True dentro da janela de grace após voltar de background.
const recentlyResumed = ref(false);

let showTimer = null;
let visibilityTimer = null;
let reconnectTimeout = null;

const isWindowVisible = () =>
  typeof document === 'undefined' || document.visibilityState === 'visible';

const bannerText = computed(() => {
  if (isReconnecting.value) return t('NETWORK.NOTIFICATION.RECONNECTING');
  if (isReconnected.value) return t('NETWORK.NOTIFICATION.RECONNECT_SUCCESS');
  return t('NETWORK.NOTIFICATION.OFFLINE');
});

const dotClasses = computed(() => {
  if (isReconnected.value) return 'bg-emerald-500';
  if (isReconnecting.value) return 'bg-slate-400 animate-pulse';
  return 'bg-amber-500';
});

const canRefresh = computed(
  () => !isReconnecting.value && !isReconnected.value
);

const refreshPage = () => {
  window.location.reload();
};

const showBanner = () => {
  showNotification.value = true;
  wasNotificationVisible.value = true;
};

const closeNotification = () => {
  showNotification.value = false;
  isReconnected.value = false;
  wasNotificationVisible.value = false;
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
  isDisconnected.value = true;
  // Voltamos de background há pouco — quase certo que é reconexão
  // automática pós-throttle, não desconexão real. Suprime.
  if (recentlyResumed.value) return;
  clearTimeout(showTimer);
  showTimer = setTimeout(() => {
    if (isDisconnected.value) showBanner();
  }, SHOW_AFTER_DISCONNECT_MS);
};

const handleReconnectionCompleted = () => {
  isDisconnected.value = false;
  isReconnecting.value = false;
  clearTimeout(showTimer);
  // Desconexão foi invisível ao usuário — não vamos chamar atenção
  // pra algo que ele nem soube que aconteceu.
  if (!wasNotificationVisible.value) {
    showNotification.value = false;
    return;
  }
  isReconnected.value = true;
  showNotification.value = true;
  reconnectTimeout = setTimeout(closeNotification, RECONNECTED_BANNER_TIMEOUT);
};

const handleReconnecting = () => {
  if (isInAnyOfTheRoutes(route.name)) {
    isReconnecting.value = true;
    isReconnected.value = false;
    // Só promove o estado visual se o usuário já estava vendo o aviso.
    if (wasNotificationVisible.value) {
      showNotification.value = true;
    }
  } else {
    handleReconnectionCompleted();
  }
};

const updateOnlineStatus = event => {
  if (event.type === 'offline') {
    // Internet caiu de verdade — sem grace period, alerta direto.
    clearTimeout(showTimer);
    showBanner();
  } else if (event.type === 'online' && !isDisconnected.value) {
    handleReconnectionCompleted();
  }
};

const handleVisibilityChange = () => {
  if (!isWindowVisible()) return;
  recentlyResumed.value = true;
  clearTimeout(visibilityTimer);
  visibilityTimer = setTimeout(() => {
    recentlyResumed.value = false;
  }, VISIBILITY_GRACE_MS);
};

useEventListener('online', updateOnlineStatus);
useEventListener('offline', updateOnlineStatus);
useEventListener(document, 'visibilitychange', handleVisibilityChange);
useEmitter(BUS_EVENTS.WEBSOCKET_DISCONNECT, updateWebsocketStatus);
useEmitter(
  BUS_EVENTS.WEBSOCKET_RECONNECT_COMPLETED,
  handleReconnectionCompleted
);
useEmitter(BUS_EVENTS.WEBSOCKET_RECONNECT, handleReconnecting);

onBeforeUnmount(() => {
  clearTimeout(reconnectTimeout);
  clearTimeout(showTimer);
  clearTimeout(visibilityTimer);
});
</script>

<template>
  <transition name="network-notification-fade">
    <div
      v-show="showNotification"
      class="fixed z-50 bottom-3 left-3 flex items-center gap-2 px-3 py-1.5 bg-n-solid-1 dark:bg-n-solid-3 border border-n-weak rounded-full shadow-lg"
      role="status"
      :aria-label="bannerText"
    >
      <span class="w-2 h-2 rounded-full flex-shrink-0" :class="dotClasses" />
      <span class="text-xs font-medium text-n-slate-12">{{ bannerText }}</span>
      <button
        v-if="canRefresh"
        type="button"
        class="ml-1 text-xs font-medium text-n-brand hover:underline focus:outline-none"
        @click="refreshPage"
      >
        {{ $t('NETWORK.BUTTON.REFRESH') }}
      </button>
    </div>
  </transition>
</template>

<style scoped>
.network-notification-fade-enter-active,
.network-notification-fade-leave-active {
  transition:
    opacity 0.2s ease,
    transform 0.2s ease;
}
.network-notification-fade-enter-from,
.network-notification-fade-leave-to {
  opacity: 0;
  transform: translateY(8px);
}
</style>
