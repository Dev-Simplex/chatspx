<script setup>
import { useI18n } from 'vue-i18n';
import LordIconIcon from 'next/icon/LordIconIcon.vue';
import { LORDICON } from 'dashboard/constants/lordicons';

defineProps({
  tab: { type: String, required: true },
});
defineEmits(['change']);

const { t } = useI18n();

const tabs = [
  {
    key: 'media',
    icon: LORDICON.galleryMedia,
    fallback: 'i-lucide-image',
    label: 'GALLERY.TABS.MEDIA',
    useLordicon: true,
  },
  {
    key: 'documents',
    fallback: 'i-lucide-file-text',
    label: 'GALLERY.TABS.DOCUMENTS',
    useLordicon: false,
  },
  {
    key: 'links',
    fallback: 'i-lucide-link-2',
    label: 'GALLERY.TABS.LINKS',
    useLordicon: false,
  },
];
</script>

<template>
  <div
    role="tablist"
    class="inline-flex items-center gap-1 p-1 rounded-xl bg-n-solid-2 dark:bg-n-solid-3 border border-n-weak/50"
  >
    <button
      v-for="t_ in tabs"
      :key="t_.key"
      type="button"
      role="tab"
      data-hover-host
      :data-sidebar-active="String(tab === t_.key)"
      :aria-selected="tab === t_.key"
      class="inline-flex items-center gap-2 h-9 px-4 rounded-lg text-sm font-medium transition-all"
      :class="
        tab === t_.key
          ? 'bg-n-solid-1 dark:bg-n-solid-1 text-n-slate-12 shadow-sm ring-1 ring-n-weak/40'
          : 'text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1'
      "
      @click="$emit('change', t_.key)"
    >
      <LordIconIcon
        v-if="t_.useLordicon && t_.icon"
        :src="t_.icon.idle"
        :src-active="t_.icon.active"
        :family="t_.icon.family"
        :fallback-lucide="t_.fallback"
        :size="18"
        class="text-current"
      />
      <span v-else :class="t_.fallback" class="size-4" />
      {{ t(t_.label) }}
    </button>
  </div>
</template>
