<script setup>
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useConnectionStatus } from 'dashboard/composables/useConnectionStatus';

// N2 do aviso escalonado: barra full-width no topo (padrão WhatsApp Web / Slack /
// Gmail) que só aparece quando a queda é SUSTENTADA (> SUSTAINED_MS). Não bloqueia
// o trabalho e recolhe sozinha ao reconectar. O timing/estado vive no composable
// compartilhado — o NetworkNotification é quem arma os relógios; aqui só lemos.
const { isSustainedOffline } = useConnectionStatus();
</script>

<template>
  <transition name="connection-status-bar">
    <div
      v-if="isSustainedOffline"
      role="status"
      aria-live="polite"
      data-testid="connection-status-bar"
      class="flex w-full shrink-0 items-center justify-center gap-2 border-b border-n-amber-6 bg-n-amber-4 px-4 py-1.5 text-sm font-medium text-n-amber-12 dark:border-n-amber-8/60 dark:bg-n-amber-8"
    >
      <Icon
        icon="i-lucide-wifi-off"
        class="size-4 shrink-0 animate-pulse motion-reduce:animate-none"
      />
      <span>{{ $t('NETWORK.NOTIFICATION.SUSTAINED_OFFLINE') }}</span>
    </div>
  </transition>
</template>

<style scoped>
.connection-status-bar-enter-active,
.connection-status-bar-leave-active {
  transition:
    opacity 0.2s ease,
    transform 0.2s ease;
}
.connection-status-bar-enter-from,
.connection-status-bar-leave-to {
  opacity: 0;
  transform: translateY(-100%);
}

@media (prefers-reduced-motion: reduce) {
  .connection-status-bar-enter-active,
  .connection-status-bar-leave-active {
    transition: none;
  }
}
</style>
