<script setup>
// Fallback para ações sem editor dedicado (ex.: mute/snooze/resolve/open/pending, que não
// têm parâmetros) ou tipos ainda não cobertos. Apenas informa que não há o que configurar.
// inheritAttrs:false — o dispatcher passa :node/@update, que aqui não têm uso.
import { useI18n } from 'vue-i18n';

defineOptions({ inheritAttrs: false });

const { t } = useI18n();
</script>

<template>
  <div
    class="flex flex-col items-center justify-center gap-2 py-8 text-center text-n-slate-10"
    data-testid="config-generic-empty"
  >
    <span class="text-2xl i-lucide-sliders-horizontal" />
    <p class="text-sm">{{ t('AUTOMATION.CANVAS.CONFIG.GENERIC.NO_PARAMS') }}</p>
  </div>
</template>
