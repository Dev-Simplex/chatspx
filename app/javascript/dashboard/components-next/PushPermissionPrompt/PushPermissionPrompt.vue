<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import {
  hasPushPermissions,
  verifyServiceWorkerExistence,
  requestPushPermissions,
} from 'dashboard/helper/pushHelper';

const { t } = useI18n();
const route = useRoute();

// Internal chat has its own bottom-right composer/send button and its own
// in-chat notification controls — this banner would overlap the send button.
const isInternalChat = computed(() => route.name === 'internal_chat_index');

const DISMISS_KEY = 'push_permission_dismissed_at';
const DISMISS_TTL_DAYS = 30;
const TRIGGER_DELAY_MS = 60 * 1000;

const visible = ref(false);
let timer = null;

const recentlyDismissed = () => {
  const ts = Number(localStorage.getItem(DISMISS_KEY) || 0);
  if (!ts) return false;
  return (Date.now() - ts) / (1000 * 60 * 60 * 24) < DISMISS_TTL_DAYS;
};

const canPrompt = () => {
  if (isInternalChat.value) return false;
  if (!('Notification' in window)) return false;
  if (Notification.permission !== 'default') return false;
  if (hasPushPermissions()) return false;
  if (recentlyDismissed()) return false;
  return true;
};

const enable = () => {
  visible.value = false;
  verifyServiceWorkerExistence(() => {
    requestPushPermissions({ onSuccess: () => {} });
  });
};

const dismiss = () => {
  localStorage.setItem(DISMISS_KEY, String(Date.now()));
  visible.value = false;
};

onMounted(() => {
  timer = setTimeout(() => {
    if (canPrompt()) visible.value = true;
  }, TRIGGER_DELAY_MS);
});

onBeforeUnmount(() => {
  if (timer) clearTimeout(timer);
});
</script>

<template>
  <div
    v-if="visible && !isInternalChat"
    class="fixed bottom-4 right-4 z-50 max-w-sm bg-n-solid-2 border border-n-weak rounded-xl shadow-lg p-4 flex items-start gap-3"
  >
    <div class="flex-1">
      <div class="text-sm font-medium text-n-slate-12">
        {{ t('PUSH_PROMPT.TITLE') }}
      </div>
      <div class="text-xs text-n-slate-11 mt-1">
        {{ t('PUSH_PROMPT.DESCRIPTION') }}
      </div>
      <div class="flex gap-2 mt-3">
        <button
          type="button"
          class="px-3 py-1.5 text-xs rounded-md bg-n-brand text-white hover:opacity-90"
          @click="enable"
        >
          {{ t('PUSH_PROMPT.ENABLE') }}
        </button>
        <button
          type="button"
          class="px-3 py-1.5 text-xs rounded-md text-n-slate-11 hover:bg-n-alpha-2"
          @click="dismiss"
        >
          {{ t('PUSH_PROMPT.LATER') }}
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
