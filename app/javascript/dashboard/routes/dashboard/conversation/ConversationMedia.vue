<script setup>
import { computed, ref, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
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

watch(
  () => props.conversationId,
  () => {
    visibleCounts.value = { image: PAGE_SIZE, video: PAGE_SIZE, audio: PAGE_SIZE, file: PAGE_SIZE, embed: PAGE_SIZE };
    fetchAttachments();
  }
);

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

const visibleImages = computed(() => grouped.value.image.slice(0, visibleCounts.value.image));
const visibleVideos = computed(() => grouped.value.video.slice(0, visibleCounts.value.video));
const visibleAudios = computed(() => grouped.value.audio.slice(0, visibleCounts.value.audio));
const visibleFiles = computed(() => grouped.value.file.slice(0, visibleCounts.value.file));
const visibleEmbeds = computed(() => grouped.value.embed.slice(0, visibleCounts.value.embed));

const hasMoreImages = computed(() => grouped.value.image.length > visibleCounts.value.image);
const hasMoreVideos = computed(() => grouped.value.video.length > visibleCounts.value.video);
const hasMoreAudios = computed(() => grouped.value.audio.length > visibleCounts.value.audio);
const hasMoreFiles = computed(() => grouped.value.file.length > visibleCounts.value.file);
const hasMoreEmbeds = computed(() => grouped.value.embed.length > visibleCounts.value.embed);

const remainingImages = computed(() => grouped.value.image.length - visibleCounts.value.image);
const remainingVideos = computed(() => grouped.value.video.length - visibleCounts.value.video);
const remainingAudios = computed(() => grouped.value.audio.length - visibleCounts.value.audio);
const remainingFiles = computed(() => grouped.value.file.length - visibleCounts.value.file);
const remainingEmbeds = computed(() => grouped.value.embed.length - visibleCounts.value.embed);

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
</script>

<template>
  <div class="conversation-media px-2 py-3 text-sm">
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
        <div class="grid grid-cols-3 gap-1.5">
          <button
            v-for="(att, idx) in visibleImages"
            :key="att.id ?? att.message_id ?? idx"
            type="button"
            class="aspect-square rounded-md overflow-hidden bg-n-slate-2 border border-n-weak focus:outline-none focus:ring-2 focus:ring-n-blue"
            @click="openGallery(att, grouped.image)"
          >
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
          {{ t('CONVERSATION_SIDEBAR.SHOW_MORE', { count: Math.min(remainingImages, PAGE_SIZE) }) }}
        </button>
      </div>

      <!-- Vídeos -->
      <div v-if="grouped.video.length > 0" class="mb-4">
        <h6 class="text-n-slate-11 font-medium mb-2 flex items-center gap-1.5">
          <Icon icon="i-lucide-video" class="size-4" />
          {{ t('CONVERSATION_SIDEBAR.MEDIA_SECTIONS.VIDEOS') }}
          ({{ grouped.video.length }})
        </h6>
        <div class="grid grid-cols-3 gap-1.5">
          <button
            v-for="(att, idx) in visibleVideos"
            :key="att.id ?? att.message_id ?? idx"
            type="button"
            class="aspect-square rounded-md overflow-hidden bg-n-slate-2 border border-n-weak focus:outline-none focus:ring-2 focus:ring-n-blue"
            @pointerenter="prewarmVideoPreview(att, idx)"
            @pointerdown="prewarmVideoPreview(att, idx)"
            @touchstart.passive="prewarmVideoPreview(att, idx)"
            @focus="prewarmVideoPreview(att, idx)"
            @click="openGallery(att, grouped.video)"
          >
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
          {{ t('CONVERSATION_SIDEBAR.SHOW_MORE', { count: Math.min(remainingVideos, PAGE_SIZE) }) }}
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
            class="flex items-center gap-2 rounded-md border border-n-weak bg-n-slate-2 px-3 py-2 text-left hover:bg-n-slate-3 focus:outline-none focus:ring-2 focus:ring-n-blue"
            @click="openGallery(att, grouped.audio)"
          >
            <Icon
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
          {{ t('CONVERSATION_SIDEBAR.SHOW_MORE', { count: Math.min(remainingAudios, PAGE_SIZE) }) }}
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
              class="flex items-center gap-2 rounded-md border border-n-weak bg-n-slate-2 px-3 py-2 text-n-slate-12 hover:bg-n-slate-3 truncate"
            >
              <Icon
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
          {{ t('CONVERSATION_SIDEBAR.SHOW_MORE', { count: Math.min(remainingFiles, PAGE_SIZE) }) }}
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
          {{ t('CONVERSATION_SIDEBAR.SHOW_MORE', { count: Math.min(remainingEmbeds, PAGE_SIZE) }) }}
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

<style scoped>
.conversation-media {
  max-height: 50vh;
  overflow-y: auto;
}
</style>
