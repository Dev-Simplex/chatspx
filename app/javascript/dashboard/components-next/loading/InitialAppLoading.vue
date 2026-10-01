<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  message: {
    type: String,
    default: '',
  },
});

const { t } = useI18n();
</script>

<template>
  <div
    class="flex flex-col items-center justify-center h-screen w-full bg-n-background gap-4"
  >
    <picture class="mb-2">
      <source
        media="(prefers-reduced-motion: reduce)"
        srcset="/brand-assets/outubro-rosa/carregamento.png"
      />
      <img
        src="/brand-assets/outubro-rosa/carregamento.webp"
        alt=""
        width="48"
        height="48"
        class="size-12"
      />
    </picture>
    <div class="w-48 h-1 bg-n-slate-3 rounded-full overflow-hidden">
      <div
        class="h-full bg-n-brand rounded-full motion-safe:animate-loader-pulse"
      />
    </div>
    <span class="text-sm text-n-slate-10">
      {{ message || t('GENERAL.LOADING_WORKSPACE') }}
    </span>
  </div>
</template>
