<script setup>
import { ref, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

const DISMISS_KEY = 'pwa_install_dismissed_at';
const DISMISS_TTL_DAYS = 14;

const deferredPrompt = ref(null);
const visible = ref(false);

const recentlyDismissed = () => {
  const ts = Number(localStorage.getItem(DISMISS_KEY) || 0);
  if (!ts) return false;
  const diffDays = (Date.now() - ts) / (1000 * 60 * 60 * 24);
  return diffDays < DISMISS_TTL_DAYS;
};

const onBeforeInstallPrompt = e => {
  e.preventDefault();
  if (recentlyDismissed()) return;
  deferredPrompt.value = e;
  visible.value = true;
};

const install = async () => {
  if (!deferredPrompt.value) return;
  await deferredPrompt.value.prompt();
  await deferredPrompt.value.userChoice.catch(() => {});
  deferredPrompt.value = null;
  visible.value = false;
};

const dismiss = () => {
  localStorage.setItem(DISMISS_KEY, String(Date.now()));
  visible.value = false;
};

const onAppInstalled = () => {
  visible.value = false;
  deferredPrompt.value = null;
};

onMounted(() => {
  window.addEventListener('beforeinstallprompt', onBeforeInstallPrompt);
  window.addEventListener('appinstalled', onAppInstalled);
});
onBeforeUnmount(() => {
  window.removeEventListener('beforeinstallprompt', onBeforeInstallPrompt);
  window.removeEventListener('appinstalled', onAppInstalled);
});
</script>

<template>
  <div
    v-if="visible"
    class="fixed bottom-4 left-4 z-50 max-w-sm bg-n-solid-2 border border-n-weak rounded-xl shadow-lg p-4 flex items-start gap-3"
  >
    <div class="flex-1">
      <div class="text-sm font-medium text-n-slate-12">
        {{ t('PWA_INSTALL.TITLE') }}
      </div>
      <div class="text-xs text-n-slate-11 mt-1">
        {{ t('PWA_INSTALL.DESCRIPTION') }}
      </div>
      <div class="flex gap-2 mt-3">
        <button
          type="button"
          class="px-3 py-1.5 text-xs rounded-md bg-n-brand text-white hover:opacity-90"
          @click="install"
        >
          {{ t('PWA_INSTALL.INSTALL') }}
        </button>
        <button
          type="button"
          class="px-3 py-1.5 text-xs rounded-md text-n-slate-11 hover:bg-n-alpha-2"
          @click="dismiss"
        >
          {{ t('PWA_INSTALL.LATER') }}
        </button>
      </div>
    </div>
    <button
      type="button"
      class="text-n-slate-11 hover:text-n-slate-12 -mt-1 -mr-1 p-1"
      @click="dismiss"
    >
      <span class="i-lucide-x size-3.5" />
    </button>
  </div>
</template>
