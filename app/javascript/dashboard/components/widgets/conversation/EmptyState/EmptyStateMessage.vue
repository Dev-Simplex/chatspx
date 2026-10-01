<script setup>
import { computed, ref } from 'vue';
import { useTimeoutFn } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

defineProps({
  message: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    default: '',
  },
  showCta: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const globalConfig = useMapGetter('globalConfig/get');

const installationName = computed(() => {
  return globalConfig.value?.installationName || 'Chatwoot';
});

const logoUrl = computed(() => {
  return (
    globalConfig.value?.logoThumbnail ||
    globalConfig.value?.logo ||
    '/brand-assets/logo_thumbnail.svg'
  );
});

const logoVisible = ref(true);
const assetsPath = '/brand-assets/outubro-rosa';
const entranceFinished = ref(false);
const { start: startCycle } = useTimeoutFn(
  () => {
    entranceFinished.value = true;
  },
  3000,
  { immediate: false }
);
</script>

<template>
  <div
    class="relative flex flex-col items-center justify-center h-full w-full px-8 py-16 text-center"
  >
    <div v-if="showCta" class="flex flex-col items-center max-w-md gap-6">
      <picture>
        <source
          media="(prefers-reduced-motion: reduce)"
          :srcset="`${assetsPath}/tela-vazia.png`"
        />
        <img
          :src="`${assetsPath}/${entranceFinished ? 'ciclo' : 'entrada'}.webp`"
          alt=""
          width="240"
          height="240"
          class="size-60 object-contain"
          @load="!entranceFinished && startCycle()"
        />
      </picture>
      <p class="text-base text-n-slate-11 leading-relaxed">
        {{ t('CONVERSATION.EMPTY_STATE.PREVENTION_MESSAGE') }}
      </p>
    </div>
    <div v-else class="flex flex-col items-center max-w-md">
      <div v-if="logoVisible" class="mb-8">
        <img
          :src="logoUrl"
          alt=""
          class="size-20 drop-shadow-sm"
          @error="logoVisible = false"
        />
      </div>

      <h3 class="text-2xl font-semibold text-n-slate-12">
        {{ installationName }}
      </h3>

      <p
        class="mt-3 text-sm text-center text-n-slate-10 max-w-sm leading-relaxed"
      >
        {{ message }}
      </p>

      <p
        v-if="description"
        class="mt-1 text-sm text-center text-n-slate-10 max-w-sm"
      >
        {{ description }}
      </p>
    </div>

    <div
      v-if="!showCta"
      class="absolute bottom-6 left-0 right-0 flex items-center justify-center gap-1.5"
    >
      <span class="i-lucide-lock size-3 text-n-slate-9" />
      <span class="text-xs text-n-slate-9">
        {{ t('CONVERSATION.EMPTY_STATE.ENCRYPTION_NOTICE') }}
      </span>
    </div>
  </div>
</template>
