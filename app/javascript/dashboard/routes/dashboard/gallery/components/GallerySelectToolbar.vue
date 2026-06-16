<script setup>
import { computed, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { useBulkDownload } from 'dashboard/composables/useBulkDownload';

const props = defineProps({
  count: { type: Number, required: true },
  items: { type: Array, required: true },
  // total de itens que o filtro atual retorna no servidor (p/ "todos do filtro")
  totalCount: { type: Number, default: 0 },
  selectAllFilterActive: { type: Boolean, default: false },
  // filtros atuais já em snake_case p/ o backend (type, inbox_id, contact_id, ...)
  filters: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['clear', 'selectAll', 'selectAllFilter']);

const { t } = useI18n();

// Acima deste limite o navegador vira spam de diálogos de "salvar"; o caminho
// correto para lotes maiores é o ZIP assíncrono (bulk download).
const DIRECT_DOWNLOAD_LIMIT = 10;

const { status, processed, total, errorMeta, isPreparing, isStarting, start } =
  useBulkDownload();

const downloadable = computed(() =>
  props.items.filter(i => i.type === 'attachment' && (i.dataUrl || i.thumbUrl))
);

// O ZIP faz sentido quando há anexos selecionados OU no modo "todos do filtro".
const canZip = computed(
  () => props.selectAllFilterActive || downloadable.value.length > 0
);

// Mostrar o convite "selecionar todos do filtro" (padrão Gmail) quando há mais
// itens no servidor do que os carregados/selecionados na tela.
const showSelectAllFilter = computed(
  () => !props.selectAllFilterActive && props.totalCount > props.count
);

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

const startZip = () => {
  if (props.selectAllFilterActive) {
    start({ filters: props.filters });
  } else {
    start({ attachmentIds: downloadable.value.map(i => i.id) });
  }
};

const handleDownload = async () => {
  // Modo "todos do filtro" sempre vira ZIP (não dá p/ baixar centenas soltas).
  if (props.selectAllFilterActive) {
    startZip();
    return;
  }
  const list = downloadable.value;
  if (!list.length) {
    useAlert(t('GALLERY.ACTIONS.DOWNLOAD_EMPTY'));
    return;
  }
  // Lote pequeno: download direto (comportamento atual). Grande: ZIP.
  if (list.length > DIRECT_DOWNLOAD_LIMIT) {
    startZip();
    return;
  }
  await list.reduce(
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

// Feedback do fluxo ZIP via toast.
watch(status, value => {
  if (value === 'ready') {
    useAlert(t('GALLERY.BULK.READY'));
  } else if (value === 'error' && errorMeta.value) {
    useAlert(t(errorMeta.value.key, errorMeta.value.params));
  }
});
</script>

<template>
  <div
    class="flex items-center justify-between gap-2 px-6 py-2 bg-n-brand/10 dark:bg-n-brand/15 border-b border-n-weak"
  >
    <div class="flex items-center gap-2 text-sm text-n-slate-12">
      <span class="i-lucide-check-square size-4 text-n-brand" />
      <span class="font-medium">
        <template v-if="selectAllFilterActive">
          {{ t('GALLERY.BULK.SELECTED_ALL_FILTER', { total: totalCount }) }}
        </template>
        <template v-else>
          {{ t('GALLERY.ACTIONS.SELECTED', { count }) }}
        </template>
      </span>
      <button
        v-if="!selectAllFilterActive"
        type="button"
        class="ml-2 text-xs text-n-slate-11 hover:text-n-slate-12 underline-offset-2 hover:underline"
        @click="$emit('selectAll')"
      >
        {{ t('GALLERY.ACTIONS.SELECT_ALL') }}
      </button>
      <button
        v-if="showSelectAllFilter"
        type="button"
        class="ml-1 text-xs font-medium text-n-brand hover:underline underline-offset-2"
        @click="emit('selectAllFilter')"
      >
        {{ t('GALLERY.BULK.SELECT_ALL_FILTER', { total: totalCount }) }}
      </button>
    </div>

    <!-- Estado: preparando o ZIP (barra de progresso via polling) -->
    <div
      v-if="isPreparing"
      class="flex items-center gap-2 text-xs font-medium text-n-slate-11"
    >
      <span class="i-lucide-loader-2 size-3.5 animate-spin text-n-brand" />
      {{
        total > 0
          ? t('GALLERY.BULK.PREPARING', { processed, total })
          : t('GALLERY.BULK.PREPARING_INDEFINITE')
      }}
    </div>

    <div v-else class="flex items-center gap-1">
      <button
        v-if="canZip"
        type="button"
        :disabled="isStarting"
        class="inline-flex items-center gap-1.5 h-8 px-3 rounded-lg text-xs font-medium text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-40 disabled:cursor-not-allowed"
        @click="startZip"
      >
        <span class="i-lucide-file-archive size-3.5" />
        {{
          t('GALLERY.BULK.DOWNLOAD_ZIP', {
            count: selectAllFilterActive ? totalCount : downloadable.length,
          })
        }}
      </button>
      <button
        type="button"
        :disabled="isStarting"
        class="inline-flex items-center gap-1.5 h-8 px-3 rounded-lg text-xs font-medium text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-40 disabled:cursor-not-allowed"
        @click="handleDownload"
      >
        <span class="i-lucide-download size-3.5" />
        {{ t('GALLERY.ACTIONS.DOWNLOAD') }}
      </button>
      <button
        v-if="!selectAllFilterActive"
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
