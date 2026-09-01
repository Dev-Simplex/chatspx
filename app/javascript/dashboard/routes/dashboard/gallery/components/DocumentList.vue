<script setup>
import { onBeforeUnmount, onMounted, ref, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import SenderAvatar from './SenderAvatar.vue';
import {
  useGroupedByDate,
  formatTime,
} from '../composables/useGroupedByDate.js';

const props = defineProps({
  items: { type: Array, required: true },
  selectedIds: { type: Set, required: true },
  // Checkbox oculto até o modo seleção ficar ativo (≥1 selecionado) — coerência
  // com a grade de imagens. O clique na linha continua alternando a seleção.
  selectionActive: { type: Boolean, default: false },
  isLoadingMore: { type: Boolean, default: false },
  hasMore: { type: Boolean, default: false },
});

const emit = defineEmits(['toggleSelect', 'openConversation', 'loadMore']);

const { t } = useI18n();
const groups = useGroupedByDate(toRef(props, 'items'), t);
const sentinel = ref(null);
let observer = null;

onMounted(() => {
  if (!sentinel.value) return;
  observer = new IntersectionObserver(
    entries => {
      entries.forEach(entry => {
        if (entry.isIntersecting && props.hasMore && !props.isLoadingMore) {
          emit('loadMore');
        }
      });
    },
    { rootMargin: '400px' }
  );
  observer.observe(sentinel.value);
});

onBeforeUnmount(() => {
  if (observer) observer.disconnect();
});

const formatBytes = bytes => {
  if (!bytes) return '—';
  const units = ['B', 'KB', 'MB', 'GB'];
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value.toFixed(value > 99 ? 0 : 1)} ${units[unit]}`;
};

const extensionMeta = item => {
  if (item.fileType === 'audio') {
    return { label: 'AUDIO', icon: 'i-lucide-mic', color: 'bg-n-violet-9' };
  }
  const ext = (item.extension || '').toLowerCase().replace('.', '');
  const map = {
    pdf: { label: 'PDF', icon: 'i-lucide-file-text', color: 'bg-red-500' },
    doc: { label: 'DOC', icon: 'i-lucide-file-text', color: 'bg-n-blue-9' },
    docx: { label: 'DOC', icon: 'i-lucide-file-text', color: 'bg-n-blue-9' },
    xls: {
      label: 'XLS',
      icon: 'i-lucide-file-spreadsheet',
      color: 'bg-n-teal-9',
    },
    xlsx: {
      label: 'XLS',
      icon: 'i-lucide-file-spreadsheet',
      color: 'bg-n-teal-9',
    },
    csv: {
      label: 'CSV',
      icon: 'i-lucide-file-spreadsheet',
      color: 'bg-n-teal-9',
    },
    ppt: { label: 'PPT', icon: 'i-lucide-file-text', color: 'bg-n-amber-9' },
    pptx: { label: 'PPT', icon: 'i-lucide-file-text', color: 'bg-n-amber-9' },
    zip: { label: 'ZIP', icon: 'i-lucide-file-archive', color: 'bg-n-amber-9' },
    rar: { label: 'RAR', icon: 'i-lucide-file-archive', color: 'bg-n-amber-9' },
    '7z': { label: '7Z', icon: 'i-lucide-file-archive', color: 'bg-n-amber-9' },
    txt: { label: 'TXT', icon: 'i-lucide-file-text', color: 'bg-slate-500' },
  };
  return (
    map[ext] || {
      label: ext.toUpperCase().slice(0, 4) || 'FILE',
      icon: 'i-lucide-file',
      color: 'bg-n-slate-9',
    }
  );
};

const cleanFilename = name => {
  if (!name || name === 'no-filename.oga') return t('GALLERY.AUDIO_MESSAGE');
  return name;
};
</script>

<template>
  <div class="max-w-4xl mx-auto">
    <section v-for="group in groups" :key="group.key" class="mb-8 last:mb-0">
      <h3
        class="mb-3 text-[13px] uppercase tracking-wider font-semibold text-n-slate-11"
      >
        {{ group.label }}
      </h3>

      <ul class="flex flex-col gap-1">
        <li
          v-for="item in group.items"
          :key="item.id"
          class="group flex items-center gap-3 py-3 px-4 rounded-2xl cursor-pointer transition-all border border-transparent [content-visibility:auto] [contain-intrinsic-size:0_72px]"
          :class="
            selectedIds.has(item.id)
              ? 'bg-n-brand/10 !border-n-brand/40'
              : 'hover:bg-n-alpha-1 dark:hover:bg-n-slate-9/30 hover:border-n-weak/60'
          "
          @click="$emit('toggleSelect', item.id)"
        >
          <!-- Checkbox — item selecionado ou modo seleção ativo → sempre visível;
               caso contrário oculto e REVELADO no hover/foco da linha (group-hover).
               pointer-events-none enquanto oculto p/ não capturar o clique fora do
               hover (a linha inteira já alterna a seleção no clique). -->
          <button
            type="button"
            :aria-label="t('GALLERY.ACTIONS.SELECT')"
            :aria-pressed="selectedIds.has(item.id)"
            class="size-5 rounded-md flex items-center justify-center flex-shrink-0 transition-all border-2"
            :class="[
              selectedIds.has(item.id)
                ? 'bg-n-brand border-n-brand'
                : 'border-n-slate-7 dark:border-n-slate-9 group-hover:border-n-slate-9 dark:group-hover:border-n-slate-7',
              selectionActive || selectedIds.has(item.id)
                ? 'opacity-100'
                : 'opacity-0 pointer-events-none group-hover:opacity-100 group-hover:pointer-events-auto focus-visible:opacity-100 focus-visible:pointer-events-auto',
            ]"
            @click.stop="$emit('toggleSelect', item.id)"
          >
            <span
              v-if="selectedIds.has(item.id)"
              class="i-lucide-check size-3.5 text-white"
            />
          </button>

          <!-- Type badge -->
          <div
            class="size-12 rounded-2xl flex flex-col items-center justify-center text-white flex-shrink-0 shadow-sm"
            :class="extensionMeta(item).color"
          >
            <span :class="extensionMeta(item).icon" class="size-4 opacity-80" />
            <span class="text-[9px] font-bold tracking-wider mt-0.5">
              {{ extensionMeta(item).label }}
            </span>
          </div>

          <!-- File info -->
          <div class="flex-1 min-w-0">
            <div class="flex items-baseline gap-2">
              <span class="text-sm font-semibold text-n-slate-12 truncate">
                {{ cleanFilename(item.filename) }}
              </span>
              <span class="text-xs text-n-slate-10 tabular-nums flex-shrink-0">
                {{ formatBytes(item.fileSize) }}
              </span>
            </div>
            <div class="flex items-center gap-2 mt-1">
              <SenderAvatar :sender="item.sender" :size="18" />
              <span class="text-xs text-n-slate-11 truncate">
                {{ item.sender?.name || t('GALLERY.UNKNOWN_SENDER') }}
              </span>
              <span
                class="text-xs text-n-slate-10 tabular-nums"
                aria-hidden="true"
              >
                &middot;
              </span>
              <span class="text-xs text-n-slate-10 tabular-nums">
                {{ formatTime(item.createdAt) }}
              </span>
            </div>
          </div>

          <!-- Actions -->
          <div class="flex items-center gap-1 flex-shrink-0">
            <a
              v-if="item.dataUrl"
              :href="item.dataUrl"
              :download="item.filename"
              target="_blank"
              rel="noopener noreferrer"
              class="size-9 rounded-xl hover:bg-n-alpha-2 flex items-center justify-center text-n-slate-11 hover:text-n-slate-12 opacity-0 group-hover:opacity-100 transition-opacity"
              :title="t('GALLERY.ACTIONS.DOWNLOAD')"
              @click.stop
            >
              <span class="i-lucide-download size-4" />
            </a>
            <button
              type="button"
              class="size-9 rounded-xl hover:bg-n-alpha-2 flex items-center justify-center text-n-slate-11 hover:text-n-slate-12 opacity-0 group-hover:opacity-100 transition-opacity"
              :title="t('GALLERY.ACTIONS.OPEN_CONVERSATION')"
              @click.stop="$emit('openConversation', item)"
            >
              <span class="i-lucide-message-circle size-4" />
            </button>
          </div>
        </li>
      </ul>
    </section>

    <div ref="sentinel" class="h-px w-full" />
    <div v-if="isLoadingMore" class="flex justify-center py-6">
      <span class="i-lucide-loader-2 size-5 animate-spin text-n-slate-10" />
    </div>
  </div>
</template>
