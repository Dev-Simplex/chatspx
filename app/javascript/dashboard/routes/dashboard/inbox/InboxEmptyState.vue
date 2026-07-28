<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  emptyStateMessage: {
    type: String,
    default: '',
  },
});

const { t } = useI18n();
const uiFlags = useMapGetter('notifications/getUIFlags');
const globalConfig = useMapGetter('globalConfig/get');

const installationName = computed(() => {
  return globalConfig.value?.installationName || 'Chatwoot';
});

// Marca da instalação em vez de um ícone genérico. Mesma cadeia de fallback do
// empty state da conversa: thumbnail (quadrada) > logo > arquivo padrão.
const logoUrl = computed(() => {
  return (
    globalConfig.value?.logoThumbnail ||
    globalConfig.value?.logo ||
    '/brand-assets/logo_thumbnail.svg'
  );
});

// Se a marca configurada apontar para um arquivo inexistente, some com a
// imagem em vez de deixar o ícone quebrado do navegador.
const logoVisible = ref(true);
</script>

<template>
  <div
    class="relative items-center justify-center hidden w-full h-full text-center bg-n-surface-1 lg:flex"
  >
    <div v-if="uiFlags.isFetching" class="flex justify-center my-4">
      <Spinner class="text-n-brand" />
    </div>
    <div v-else class="flex flex-col items-center max-w-md">
      <img
        v-if="logoVisible"
        :src="logoUrl"
        alt=""
        class="size-24 drop-shadow-sm"
        @error="logoVisible = false"
      />
      <h3 class="mt-6 text-2xl font-semibold text-n-slate-12">
        {{ installationName }}
      </h3>
      <p class="mt-2 text-sm text-n-slate-10">
        {{ emptyStateMessage || t('INBOX.LIST.NOTE') }}
      </p>
    </div>

    <div
      class="absolute bottom-8 left-0 right-0 flex items-center justify-center gap-1.5"
    >
      <Icon icon="i-lucide-lock" class="size-3 text-n-slate-9" />
      <span class="text-xs text-n-slate-9">
        {{ t('CONVERSATION.EMPTY_STATE.ENCRYPTION_NOTICE') }}
      </span>
    </div>
  </div>
</template>
