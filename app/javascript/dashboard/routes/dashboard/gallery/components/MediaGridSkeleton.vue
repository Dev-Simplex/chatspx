<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  count: { type: Number, default: 18 },
});

const { t } = useI18n();
</script>

<template>
  <div
    role="status"
    aria-busy="true"
    :aria-label="t('GALLERY.LOADING')"
    class="grid gap-3 grid-cols-[repeat(auto-fill,minmax(180px,1fr))]"
  >
    <div
      v-for="n in count"
      :key="n"
      class="aspect-square rounded-2xl bg-n-slate-3 animate-pulse motion-reduce:animate-none"
    />
    <span class="sr-only">{{ t('GALLERY.LOADING') }}</span>
  </div>
</template>
