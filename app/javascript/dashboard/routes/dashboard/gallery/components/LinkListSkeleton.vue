<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  count: { type: Number, default: 6 },
});

const { t } = useI18n();
</script>

<template>
  <div
    role="status"
    aria-busy="true"
    :aria-label="t('GALLERY.LOADING')"
    class="max-w-4xl mx-auto"
  >
    <ul class="flex flex-col gap-2">
      <li
        v-for="n in count"
        :key="n"
        class="flex items-start gap-3 py-4 px-4 rounded-2xl border border-transparent animate-pulse motion-reduce:animate-none"
      >
        <div class="size-5 rounded-md bg-n-slate-3 mt-1" />
        <div class="size-12 rounded-2xl bg-n-slate-3 flex-shrink-0" />
        <div class="flex-1 min-w-0 flex flex-col gap-2">
          <div class="h-3.5 w-1/3 rounded bg-n-slate-3" />
          <div class="h-3 w-full rounded bg-n-slate-3" />
          <div class="h-3 w-2/3 rounded bg-n-slate-3" />
        </div>
      </li>
    </ul>
    <span class="sr-only">{{ t('GALLERY.LOADING') }}</span>
  </div>
</template>
