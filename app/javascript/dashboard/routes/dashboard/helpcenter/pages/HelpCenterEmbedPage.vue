<script setup>
import { computed, ref, watch, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  HELP_CENTER_PORTAL_URL,
  buildHelpCenterEmbedUrl,
  getHelpCenterConversationToken,
  persistHelpCenterConversationToken,
} from 'dashboard/helper/helpCenterEmbed';
import { HELP_CENTER_CONVERSATION_TOKEN } from 'shared/constants/helpCenter';

const { t } = useI18n();

// Tema do iframe acompanha o light/dark do app (classe `dark` no <body>,
// aplicada pelo themeHelper). MutationObserver mantém em sincronia se o
// usuário trocar o tema enquanto está na tela.
const isDark = ref(false);
const isLoading = ref(true);
const portalFrame = ref(null);
const conversationToken = getHelpCenterConversationToken();
const portalOrigin = new URL(HELP_CENTER_PORTAL_URL).origin;

const syncTheme = () => {
  isDark.value = document.body.classList.contains('dark');
};

const embedUrl = computed(() =>
  buildHelpCenterEmbedUrl({
    dark: isDark.value,
    conversationToken,
  })
);

// Trocar o tema recarrega o iframe (rara), então mostra o loader de novo.
watch(embedUrl, () => {
  isLoading.value = true;
});

let observer = null;
const handleConversationToken = event => {
  if (event.origin !== portalOrigin) return;
  if (event.source !== portalFrame.value?.contentWindow) return;
  if (event.data?.event !== HELP_CENTER_CONVERSATION_TOKEN) return;
  if (typeof event.data.token !== 'string' || !event.data.token) return;

  persistHelpCenterConversationToken(event.data.token);
};

onMounted(() => {
  syncTheme();
  observer = new MutationObserver(syncTheme);
  observer.observe(document.body, {
    attributes: true,
    attributeFilter: ['class'],
  });
  window.addEventListener('message', handleConversationToken);
});
onBeforeUnmount(() => {
  observer?.disconnect();
  window.removeEventListener('message', handleConversationToken);
});

const onLoaded = () => {
  isLoading.value = false;
};
</script>

<template>
  <div
    class="relative flex flex-col w-full h-full overflow-hidden bg-n-background dark:bg-n-solid-1"
  >
    <div
      v-if="isLoading"
      class="flex absolute inset-0 justify-center items-center pointer-events-none"
    >
      <span
        class="animate-spin i-lucide-loader-circle size-6 text-n-slate-10"
        aria-hidden="true"
      />
    </div>
    <iframe
      :key="embedUrl"
      ref="portalFrame"
      :src="embedUrl"
      :title="t('SIDEBAR.HELP_CENTER.TITLE')"
      class="w-full h-full border-0"
      referrerpolicy="no-referrer-when-downgrade"
      @load="onLoaded"
    />
  </div>
</template>
