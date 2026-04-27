<script setup>
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  count: { type: Number, required: true },
  items: { type: Array, required: true },
});
defineEmits(['clear', 'selectAll']);

const { t } = useI18n();

const downloadOne = (url, filename) =>
  new Promise(resolve => {
    const a = document.createElement('a');
    a.href = url;
    if (filename) a.download = filename;
    a.target = '_blank';
    a.rel = 'noopener';
    document.body.appendChild(a);
    a.click();
    setTimeout(() => {
      a.remove();
      resolve();
    }, 250);
  });

const handleDownload = async () => {
  const downloadable = props.items.filter(
    i => i.type === 'attachment' && (i.dataUrl || i.thumbUrl)
  );
  if (!downloadable.length) {
    useAlert(t('GALLERY.ACTIONS.DOWNLOAD_EMPTY'));
    return;
  }
  if (downloadable.length > 5) {
    useAlert(t('GALLERY.ACTIONS.DOWNLOAD_LIMIT'));
    return;
  }
  await downloadable.reduce(
    (chain, item) =>
      chain.then(() =>
        downloadOne(item.dataUrl || item.thumbUrl, item.filename)
      ),
    Promise.resolve()
  );
};

const handleShare = async () => {
  if (!navigator.share) {
    useAlert(t('GALLERY.ACTIONS.SHARE_UNSUPPORTED'));
    return;
  }
  const urls = props.items
    .map(i => i.dataUrl || (i.urls && i.urls[0]) || null)
    .filter(Boolean)
    .slice(0, 5);
  if (!urls.length) return;
  try {
    await navigator.share({
      title: t('GALLERY.TITLE'),
      text: urls.join('\n'),
    });
  } catch (e) {
    // user cancelled
  }
};
</script>

<template>
  <div
    class="flex items-center justify-between gap-2 px-6 py-2 bg-n-brand/10 dark:bg-n-brand/15 border-b border-n-weak"
  >
    <div class="flex items-center gap-2 text-sm text-n-slate-12">
      <span class="i-lucide-check-square size-4 text-n-brand" />
      <span class="font-medium">
        {{ t('GALLERY.ACTIONS.SELECTED', { count }) }}
      </span>
      <button
        type="button"
        class="ml-2 text-xs text-n-slate-11 hover:text-n-slate-12 underline-offset-2 hover:underline"
        @click="$emit('selectAll')"
      >
        {{ t('GALLERY.ACTIONS.SELECT_ALL') }}
      </button>
    </div>
    <div class="flex items-center gap-1">
      <button
        type="button"
        class="inline-flex items-center gap-1.5 h-8 px-3 rounded-lg text-xs font-medium text-n-slate-12 hover:bg-n-alpha-2"
        @click="handleDownload"
      >
        <span class="i-lucide-download size-3.5" />
        {{ t('GALLERY.ACTIONS.DOWNLOAD') }}
      </button>
      <button
        type="button"
        class="inline-flex items-center gap-1.5 h-8 px-3 rounded-lg text-xs font-medium text-n-slate-12 hover:bg-n-alpha-2"
        @click="handleShare"
      >
        <span class="i-lucide-share-2 size-3.5" />
        {{ t('GALLERY.ACTIONS.SHARE') }}
      </button>
      <button
        type="button"
        class="inline-flex items-center gap-1 h-8 px-3 rounded-lg text-xs text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2"
        @click="$emit('clear')"
      >
        <span class="i-lucide-x size-3.5" />
        {{ t('GALLERY.ACTIONS.DESELECT') }}
      </button>
    </div>
  </div>
</template>
