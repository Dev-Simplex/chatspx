<script setup>
import { computed, ref, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useBulkDownload } from 'dashboard/composables/useBulkDownload';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();

const PAGE_SIZE = 9;

// Backend enum: image=>0, audio=>1, video=>2, file=>3, embed=>12, ig_reel=>9
const FILE_TYPE_ENUM = {
  0: 'image',
  1: 'audio',
  2: 'video',
  3: 'file',
  9: 'ig_reel',
  12: 'embed',
};

const normalizeFileType = attachment => {
  if (!attachment) return null;
  const ft = attachment.file_type;
  if (typeof ft === 'string') return ft;
  return FILE_TYPE_ENUM[ft] ?? 'file';
};

const attachmentsRaw = computed(() => {
  const list = getters.getSelectedChatAttachments?.value ?? [];
  return Array.isArray(list) ? list : [];
});

const fetchAttachments = () => {
  if (props.conversationId) {
    store.dispatch('fetchAllAttachments', props.conversationId).catch(() => {});
  }
};

onMounted(fetchAttachments);

const grouped = computed(() => {
  const raw = attachmentsRaw.value;
  const groups = {
    image: [],
    video: [],
    audio: [],
    file: [],
    embed: [],
  };
  raw.forEach(att => {
    const type = normalizeFileType(att);
    if (!type) return;
    if (type === 'image') groups.image.push(att);
    else if (type === 'video' || type === 'ig_reel') groups.video.push(att);
    else if (type === 'audio') groups.audio.push(att);
    else if (type === 'file') groups.file.push(att);
    else if (type === 'embed') groups.embed.push(att);
  });
  return groups;
});

const hasAnyMedia = computed(
  () =>
    grouped.value.image.length > 0 ||
    grouped.value.video.length > 0 ||
    grouped.value.audio.length > 0 ||
    grouped.value.file.length > 0 ||
    grouped.value.embed.length > 0
);

// Visible counts per section (9 at a time)
const visibleCounts = ref({
  image: PAGE_SIZE,
  video: PAGE_SIZE,
  audio: PAGE_SIZE,
  file: PAGE_SIZE,
  embed: PAGE_SIZE,
});

const visibleImages = computed(() =>
  grouped.value.image.slice(0, visibleCounts.value.image)
);
const visibleVideos = computed(() =>
  grouped.value.video.slice(0, visibleCounts.value.video)
);
const visibleAudios = computed(() =>
  grouped.value.audio.slice(0, visibleCounts.value.audio)
);
const visibleFiles = computed(() =>
  grouped.value.file.slice(0, visibleCounts.value.file)
);
const visibleEmbeds = computed(() =>
  grouped.value.embed.slice(0, visibleCounts.value.embed)
);

const hasMoreImages = computed(
  () => grouped.value.image.length > visibleCounts.value.image
);
const hasMoreVideos = computed(
  () => grouped.value.video.length > visibleCounts.value.video
);
const hasMoreAudios = computed(
  () => grouped.value.audio.length > visibleCounts.value.audio
);
const hasMoreFiles = computed(
  () => grouped.value.file.length > visibleCounts.value.file
);
const hasMoreEmbeds = computed(
  () => grouped.value.embed.length > visibleCounts.value.embed
);

const remainingImages = computed(
  () => grouped.value.image.length - visibleCounts.value.image
);
const remainingVideos = computed(
  () => grouped.value.video.length - visibleCounts.value.video
);
const remainingAudios = computed(
  () => grouped.value.audio.length - visibleCounts.value.audio
);
const remainingFiles = computed(
  () => grouped.value.file.length - visibleCounts.value.file
);
const remainingEmbeds = computed(
  () => grouped.value.embed.length - visibleCounts.value.embed
);

const showMore = type => {
  visibleCounts.value[type] += PAGE_SIZE;
};

const showGallery = ref(false);
const galleryAttachment = ref(null);
const galleryList = ref([]);
const prewarmedVideoPreviewKeys = ref(new Set());

// Gallery always receives the full group list (not just visible slice)
const openGallery = (attachment, fullList) => {
  if (!attachment || !Array.isArray(fullList)) return;
  galleryAttachment.value = attachment;
  galleryList.value = fullList;
  showGallery.value = true;
};

const closeGallery = () => {
  showGallery.value = false;
  galleryAttachment.value = null;
  galleryList.value = [];
};

const resolveAttachmentKey = (attachment, index) => {
  return attachment?.id ?? attachment?.message_id ?? index;
};

const prewarmVideoPreview = (attachment, index) => {
  if (!attachment?.data_url) return;

  const key = resolveAttachmentKey(attachment, index);
  if (prewarmedVideoPreviewKeys.value.has(key)) return;

  prewarmedVideoPreviewKeys.value = new Set([
    ...prewarmedVideoPreviewKeys.value,
    key,
  ]);
};

const getVideoPreviewSrc = (attachment, index) => {
  const key = resolveAttachmentKey(attachment, index);
  return prewarmedVideoPreviewKeys.value.has(key) ? attachment.data_url : '';
};

const getThumbSrc = att => att?.thumb_url || att?.data_url || '';

const getFileName = att => {
  const url = att?.data_url;
  if (!url) return t('CONVERSATION_SIDEBAR.MEDIA_SECTIONS.DOCUMENT');
  try {
    const path = url.split('?')[0];
    const segment = path.split('/').pop();
    return (
      decodeURIComponent(segment || '') ||
      t('CONVERSATION_SIDEBAR.MEDIA_SECTIONS.DOCUMENT')
    );
  } catch {
    return t('CONVERSATION_SIDEBAR.MEDIA_SECTIONS.DOCUMENT');
  }
};

const getLinkUrl = att => att?.data_url || att?.external_url || '#';

// --- Download em massa (zip assíncrono) + modo seleção -----------------------
const { status, processed, total, errorMeta, isPreparing, isStarting, start } =
  useBulkDownload();

const selectionMode = ref(false);
const selectedIds = ref(new Set());

// "Baixar todas" cobre os tipos com arquivo (imagens, vídeos, áudios, docs) —
// links/embeds não entram no zip.
const downloadableCount = computed(
  () =>
    grouped.value.image.length +
    grouped.value.video.length +
    grouped.value.audio.length +
    grouped.value.file.length
);

const selectedCount = computed(() => selectedIds.value.size);
const isItemSelected = att => att?.id != null && selectedIds.value.has(att.id);

const toggleItem = att => {
  if (att?.id == null) return;
  const next = new Set(selectedIds.value);
  if (next.has(att.id)) next.delete(att.id);
  else next.add(att.id);
  selectedIds.value = next;
};

const enterSelection = () => {
  selectionMode.value = true;
};

function exitSelection() {
  selectionMode.value = false;
  selectedIds.value = new Set();
}

// Em modo seleção o clique alterna o item; fora dele, abre o lightbox.
const onItemClick = (att, fullList) => {
  if (selectionMode.value) {
    toggleItem(att);
    return;
  }
  openGallery(att, fullList);
};

// Documentos são <a> — em modo seleção interceptamos o clique para alternar.
const onFileClick = (event, att) => {
  if (selectionMode.value) {
    event.preventDefault();
    toggleItem(att);
  }
};

const downloadAll = () => start({ conversationId: props.conversationId });

const downloadSelected = () => {
  if (!selectedIds.value.size) return;
  start({
    attachmentIds: [...selectedIds.value],
    conversationId: props.conversationId,
  });
};

watch(status, value => {
  if (value === 'ready') {
    useAlert(t('GALLERY.BULK.READY'));
  } else if (value === 'error' && errorMeta.value) {
    useAlert(t(errorMeta.value.key, errorMeta.value.params));
  }
});

// Troca de conversa: reseta paginação/seleção e recarrega.
watch(
  () => props.conversationId,
  () => {
    visibleCounts.value = {
      image: PAGE_SIZE,
      video: PAGE_SIZE,
      audio: PAGE_SIZE,
      file: PAGE_SIZE,
      embed: PAGE_SIZE,
    };
    exitSelection();
    fetchAttachments();
  }
);
</script>

<template>
  <div class="max-h-[50vh] overflow-y-auto px-4 pb-3 text-sm">
    <!-- Barra de ações de download em massa — CTA primário de largura total.
         Só aparece quando há ao menos 1 arquivo baixável (§T8): conversa só com
         links não mostra "Baixar todas (0)". -->
    <div
      v-if="downloadableCount > 0"
      class="flex flex-col gap-2 mb-3 sticky top-0 z-20 bg-n-solid-1 dark:bg-n-solid-2 pt-1 pb-2"
    >
      <!-- Preparando o zip -->
      <div
        v-if="isPreparing"
        class="flex items-center justify-center gap-2 w-full h-9 rounded-lg bg-n-brand/10 text-n-brand text-sm font-medium"
      >
        <Icon icon="i-lucide-loader-2" class="size-4 animate-spin" />
        {{
          total > 0
            ? t('CONVERSATION_SIDEBAR.BULK.PREPARING', { processed, total })
            : t('CONVERSATION_SIDEBAR.BULK.PREPARING_INDEFINITE')
        }}
      </div>

      <!-- Ações padrão -->
      <template v-else-if="!selectionMode">
        <button
          type="button"
          :disabled="isStarting"
          class="flex items-center justify-center gap-2 w-full h-9 rounded-lg text-sm font-semibold text-white bg-n-brand hover:bg-n-brand/90 shadow-sm transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          @click="downloadAll"
        >
          <Icon icon="i-lucide-download" class="size-4" />
          {{
            t('CONVERSATION_SIDEBAR.BULK.DOWNLOAD_ALL', {
              count: downloadableCount,
            })
          }}
        </button>
        <button
          v-if="downloadableCount > 0"
          type="button"
          class="flex items-center justify-center gap-1.5 w-full h-8 rounded-lg text-xs font-medium text-n-slate-11 border border-n-weak hover:bg-n-alpha-2 hover:text-n-slate-12 transition-colors"
          @click="enterSelection"
        >
          <Icon icon="i-lucide-check-square" class="size-3.5" />
          {{ t('CONVERSATION_SIDEBAR.BULK.SELECT') }}
        </button>
      </template>

      <!-- Modo seleção -->
      <template v-else>
        <div class="flex items-center justify-between">
          <span class="text-xs font-medium text-n-slate-12">
            {{
              t('CONVERSATION_SIDEBAR.BULK.SELECTED_COUNT', {
                count: selectedCount,
              })
            }}
          </span>
          <button
            type="button"
            class="text-xs text-n-slate-11 hover:text-n-slate-12"
            @click="exitSelection"
          >
            {{ t('CONVERSATION_SIDEBAR.BULK.CANCEL') }}
          </button>
        </div>
        <button
          type="button"
          :disabled="!selectedCount || isStarting"
          class="flex items-center justify-center gap-2 w-full h-9 rounded-lg text-sm font-semibold text-white bg-n-brand hover:bg-n-brand/90 shadow-sm disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
          @click="downloadSelected"
        >
          <Icon icon="i-lucide-download" class="size-4" />
          {{ t('CONVERSATION_SIDEBAR.BULK.DOWNLOAD_SELECTED') }}
        </button>
      </template>
    </div>

    <template v-if="!hasAnyMedia">
      <p class="text-n-slate-11 text-center py-2">
        {{ t('CONVERSATION_SIDEBAR.MEDIA_EMPTY') }}
      </p>
    </template>
    <template v-else>
      <!-- Imagens -->
      <div v-if="grouped.image.length > 0" class="mb-4">
        <h6 class="text-n-slate-11 font-medium mb-2 flex items-center gap-1.5">
          <Icon icon="i-lucide-image" class="size-4" />
          {{ t('CONVERSATION_SIDEBAR.MEDIA_SECTIONS.IMAGES') }}
          ({{ grouped.image.length }})
        </h6>
        <div class="grid grid-cols-3 gap-1">
          <button
            v-for="(att, idx) in visibleImages"
            :key="att.id ?? att.message_id ?? idx"
            type="button"
            class="relative aspect-square rounded-lg overflow-hidden bg-n-slate-2 cursor-pointer hover:opacity-80 transition-opacity focus:outline-none focus:ring-2 focus:ring-n-blue"
            :class="{ 'ring-2 ring-n-brand': isItemSelected(att) }"
            @click="onItemClick(att, grouped.image)"
          >
            <span
              v-if="selectionMode"
              class="absolute top-1 ltr:left-1 rtl:right-1 z-10 size-5 rounded-md border-2 flex items-center justify-center"
              :class="
                isItemSelected(att)
                  ? 'bg-n-brand border-n-brand text-white'
                  : 'bg-black/30 border-white/70'
              "
            >
              <Icon
                v-if="isItemSelected(att)"
                icon="i-lucide-check"
                class="size-3.5"
              />
            </span>
            <img
              v-if="getThumbSrc(att)"
              :src="getThumbSrc(att)"
              class="w-full h-full object-cover"
              alt=""
            />
            <div
              v-else
              class="w-full h-full flex items-center justify-center text-n-slate-10"
            >
              <Icon icon="i-lucide-image" class="size-6" />
            </div>
          </button>
        </div>
        <button
          v-if="hasMoreImages"
          type="button"
          class="mt-2 w-full text-xs text-n-blue-text hover:underline text-center py-1"
          @click="showMore('image')"
        >
          {{
            t('CONVERSATION_SIDEBAR.SHOW_MORE', {
              count: Math.min(remainingImages, PAGE_SIZE),
            })
          }}
        </button>
      </div>

      <!-- Vídeos -->
      <div v-if="grouped.video.length > 0" class="mb-4">
        <h6 class="text-n-slate-11 font-medium mb-2 flex items-center gap-1.5">
          <Icon icon="i-lucide-video" class="size-4" />
          {{ t('CONVERSATION_SIDEBAR.MEDIA_SECTIONS.VIDEOS') }}
          ({{ grouped.video.length }})
        </h6>
        <div class="grid grid-cols-3 gap-1">
          <button
            v-for="(att, idx) in visibleVideos"
            :key="att.id ?? att.message_id ?? idx"
            type="button"
            class="relative aspect-square rounded-lg overflow-hidden bg-n-slate-2 cursor-pointer hover:opacity-80 transition-opacity focus:outline-none focus:ring-2 focus:ring-n-blue"
            :class="{ 'ring-2 ring-n-brand': isItemSelected(att) }"
            @pointerenter="prewarmVideoPreview(att, idx)"
            @pointerdown="prewarmVideoPreview(att, idx)"
            @touchstart.passive="prewarmVideoPreview(att, idx)"
            @focus="prewarmVideoPreview(att, idx)"
            @click="onItemClick(att, grouped.video)"
          >
            <span
              v-if="selectionMode"
              class="absolute top-1 ltr:left-1 rtl:right-1 z-10 size-5 rounded-md border-2 flex items-center justify-center"
              :class="
                isItemSelected(att)
                  ? 'bg-n-brand border-n-brand text-white'
                  : 'bg-black/30 border-white/70'
              "
            >
              <Icon
                v-if="isItemSelected(att)"
                icon="i-lucide-check"
                class="size-3.5"
              />
            </span>
            <img
              v-if="att.thumb_url"
              :src="att.thumb_url"
              class="w-full h-full object-cover"
              alt=""
            />
            <video
              v-else-if="att.data_url"
              :src="getVideoPreviewSrc(att, idx)"
              class="w-full h-full object-cover"
              muted
              playsinline
              preload="none"
            />
            <div
              v-else
              class="w-full h-full flex items-center justify-center text-n-slate-10 relative"
            >
              <Icon icon="i-lucide-video" class="size-6" />
              <div
                class="absolute inset-0 flex items-center justify-center bg-black/20"
              >
                <Icon
                  icon="i-teenyicons-play-small-solid"
                  class="size-6 text-white"
                />
              </div>
            </div>
          </button>
        </div>
        <button
          v-if="hasMoreVideos"
          type="button"
          class="mt-2 w-full text-xs text-n-blue-text hover:underline text-center py-1"
          @click="showMore('video')"
        >
          {{
            t('CONVERSATION_SIDEBAR.SHOW_MORE', {
              count: Math.min(remainingVideos, PAGE_SIZE),
            })
          }}
        </button>
      </div>

      <!-- Áudios -->
      <div v-if="grouped.audio.length > 0" class="mb-4">
        <h6 class="text-n-slate-11 font-medium mb-2 flex items-center gap-1.5">
          <Icon icon="i-lucide-mic" class="size-4" />
          {{ t('CONVERSATION_SIDEBAR.MEDIA_SECTIONS.AUDIOS') }}
          ({{ grouped.audio.length }})
        </h6>
        <div class="flex flex-col gap-1.5">
          <button
            v-for="(att, idx) in visibleAudios"
            :key="att.id ?? att.message_id ?? idx"
            type="button"
            class="flex items-center gap-2 rounded-md border bg-n-slate-2 px-3 py-2 text-left hover:bg-n-slate-3 focus:outline-none focus:ring-2 focus:ring-n-blue"
            :class="
              isItemSelected(att)
                ? 'border-n-brand ring-1 ring-n-brand'
                : 'border-n-weak'
            "
            @click="onItemClick(att, grouped.audio)"
          >
            <Icon
              v-if="selectionMode"
              :icon="
                isItemSelected(att)
                  ? 'i-lucide-check-square'
                  : 'i-lucide-square'
              "
              class="size-4 shrink-0"
              :class="isItemSelected(att) ? 'text-n-brand' : 'text-n-slate-10'"
            />
            <Icon
              v-else
              icon="i-lucide-volume-2"
              class="size-4 text-n-slate-11 shrink-0"
            />
            <span class="truncate text-n-slate-12">
              {{ t('CONVERSATION_SIDEBAR.MEDIA_SECTIONS.AUDIO') }} {{ idx + 1 }}
            </span>
          </button>
        </div>
        <button
          v-if="hasMoreAudios"
          type="button"
          class="mt-2 w-full text-xs text-n-blue-text hover:underline text-center py-1"
          @click="showMore('audio')"
        >
          {{
            t('CONVERSATION_SIDEBAR.SHOW_MORE', {
              count: Math.min(remainingAudios, PAGE_SIZE),
            })
          }}
        </button>
      </div>

      <!-- Documentos -->
      <div v-if="grouped.file.length > 0" class="mb-4">
        <h6 class="text-n-slate-11 font-medium mb-2 flex items-center gap-1.5">
          <Icon icon="i-lucide-file-text" class="size-4" />
          {{ t('CONVERSATION_SIDEBAR.MEDIA_SECTIONS.DOCUMENTS') }}
          ({{ grouped.file.length }})
        </h6>
        <ul class="flex flex-col gap-1.5">
          <li
            v-for="(att, idx) in visibleFiles"
            :key="att.id ?? att.message_id ?? idx"
          >
            <a
              :href="att.data_url"
              target="_blank"
              rel="noopener noreferrer"
              class="flex items-center gap-2 rounded-md border bg-n-slate-2 px-3 py-2 text-n-slate-12 hover:bg-n-slate-3 truncate"
              :class="
                isItemSelected(att)
                  ? 'border-n-brand ring-1 ring-n-brand'
                  : 'border-n-weak'
              "
              @click="onFileClick($event, att)"
            >
              <Icon
                v-if="selectionMode"
                :icon="
                  isItemSelected(att)
                    ? 'i-lucide-check-square'
                    : 'i-lucide-square'
                "
                class="size-4 shrink-0"
                :class="
                  isItemSelected(att) ? 'text-n-brand' : 'text-n-slate-10'
                "
              />
              <Icon
                v-else
                icon="i-lucide-file-down"
                class="size-4 text-n-slate-11 shrink-0"
              />
              <span class="truncate flex-1">{{ getFileName(att) }}</span>
            </a>
          </li>
        </ul>
        <button
          v-if="hasMoreFiles"
          type="button"
          class="mt-2 w-full text-xs text-n-blue-text hover:underline text-center py-1"
          @click="showMore('file')"
        >
          {{
            t('CONVERSATION_SIDEBAR.SHOW_MORE', {
              count: Math.min(remainingFiles, PAGE_SIZE),
            })
          }}
        </button>
      </div>

      <!-- Links -->
      <div v-if="grouped.embed.length > 0">
        <h6 class="text-n-slate-11 font-medium mb-2 flex items-center gap-1.5">
          <Icon icon="i-lucide-link" class="size-4" />
          {{ t('CONVERSATION_SIDEBAR.MEDIA_SECTIONS.LINKS') }}
          ({{ grouped.embed.length }})
        </h6>
        <ul class="flex flex-col gap-1.5">
          <li
            v-for="(att, idx) in visibleEmbeds"
            :key="att.id ?? att.message_id ?? idx"
          >
            <a
              :href="getLinkUrl(att)"
              target="_blank"
              rel="noopener noreferrer"
              class="flex items-center gap-2 rounded-md border border-n-weak bg-n-slate-2 px-3 py-2 text-n-blue hover:bg-n-slate-3 truncate"
            >
              <Icon icon="i-lucide-external-link" class="size-4 shrink-0" />
              <span class="truncate flex-1">{{ getLinkUrl(att) }}</span>
            </a>
          </li>
        </ul>
        <button
          v-if="hasMoreEmbeds"
          type="button"
          class="mt-2 w-full text-xs text-n-blue-text hover:underline text-center py-1"
          @click="showMore('embed')"
        >
          {{
            t('CONVERSATION_SIDEBAR.SHOW_MORE', {
              count: Math.min(remainingEmbeds, PAGE_SIZE),
            })
          }}
        </button>
      </div>
    </template>

    <GalleryView
      v-if="showGallery && galleryAttachment && galleryList.length > 0"
      v-model:show="showGallery"
      :attachment="galleryAttachment"
      :all-attachments="galleryList"
      @close="closeGallery"
    />
  </div>
</template>
