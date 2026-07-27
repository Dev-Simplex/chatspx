<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';
import ConversationMedia from './ConversationMedia.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();

// Faixa estilo WhatsApp Web: 4 casinhas, a última vira o "+N" quando sobra mais.
const THUMB_SLOTS = 4;

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

const attachmentsMeta = computed(
  () => getters.getSelectedChatAttachmentsMeta?.value ?? {}
);

const fetchAttachments = () => {
  if (props.conversationId) {
    store.dispatch('fetchAllAttachments', props.conversationId).catch(() => {});
  }
};

onMounted(fetchAttachments);

watch(() => props.conversationId, fetchAttachments);

// O anexo que chega ao vivo (ADD_CONVERSATION_ATTACHMENTS) vem do payload da
// mensagem, que NÃO carrega created_at — e é justamente o mais novo. Por isso
// ele vale "infinito" no ranking; com `?? 0` a foto recém-enviada ia parar no
// fim e sumia das 4 casinhas. O id (auto-incremento) desempata entre eles.
const recencyRank = att => att?.created_at ?? Number.MAX_SAFE_INTEGER;
const attachmentRowId = att => Number(att?.id) || 0;

// A API ordena por created_at desc, mas o store anexa os que chegam ao vivo no
// FIM da lista: sem reordenar, a faixa não mostraria o que acabou de chegar.
const recentAttachments = computed(() =>
  [...attachmentsRaw.value].sort(
    (a, b) =>
      recencyRank(b) - recencyRank(a) || attachmentRowId(b) - attachmentRowId(a)
  )
);

// O store carrega só a primeira página: o total real vem do meta.
const totalCount = computed(() => {
  const { totalCount: metaTotal } = attachmentsMeta.value ?? {};
  return Math.max(metaTotal ?? 0, attachmentsRaw.value.length);
});

const hasMedia = computed(() => attachmentsRaw.value.length > 0);

const thumbs = computed(() => recentAttachments.value.slice(0, THUMB_SLOTS));

// Só as 3 primeiras casinhas ficam visíveis quando a 4ª vira contador.
const overflowCount = computed(() =>
  totalCount.value > THUMB_SLOTS ? totalCount.value - (THUMB_SLOTS - 1) : 0
);

const isOverflowSlot = index =>
  overflowCount.value > 0 && index === THUMB_SLOTS - 1;

const isVideo = att => {
  const type = normalizeFileType(att);
  return type === 'video' || type === 'ig_reel';
};

const getThumbSrc = att => {
  if (att?.thumb_url) return att.thumb_url;
  return normalizeFileType(att) === 'image' ? att?.data_url || '' : '';
};

const getFallbackIcon = att => {
  const type = normalizeFileType(att);
  if (type === 'audio') return 'i-lucide-mic';
  if (type === 'image') return 'i-lucide-image';
  if (type === 'video' || type === 'ig_reel') return 'i-lucide-video';
  return 'i-lucide-file-text';
};

// --- Painel completo ---------------------------------------------------------
const panelDialogRef = ref(null);
const activeTab = ref('media');

const openPanel = () => panelDialogRef.value?.open();
const closePanel = () => panelDialogRef.value?.close();

// --- Lightbox ----------------------------------------------------------------
// A galeria é teleportada para o body e o painel é um <dialog> modal (top
// layer): os dois juntos deixariam a galeria escondida atrás do backdrop. Por
// isso fechamos o painel antes de abrir a galeria e o reabrimos ao sair dela.
const isGalleryOpen = ref(false);
const galleryAttachment = ref(null);
const galleryList = ref([]);

const handleOpenGallery = ({ attachment, list }) => {
  if (!attachment || !Array.isArray(list) || !list.length) return;
  galleryAttachment.value = attachment;
  galleryList.value = list;
  closePanel();
  isGalleryOpen.value = true;
};

const closeGallery = () => {
  isGalleryOpen.value = false;
  galleryAttachment.value = null;
  galleryList.value = [];
  openPanel();
};

const onTabChange = tab => {
  activeTab.value = tab;
};
</script>

<template>
  <div class="border-t border-n-weak/50">
    <button
      type="button"
      class="flex items-center justify-between w-full px-4 py-3 m-0 text-start select-none hover:bg-n-slate-3/30"
      @click="openPanel"
    >
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('CONVERSATION_SIDEBAR.MEDIA_STRIP.TITLE') }}
      </span>
      <span class="flex items-center gap-1.5">
        <span v-if="hasMedia" class="text-sm text-n-slate-11 tabular-nums">
          {{ totalCount }}
        </span>
        <Icon
          icon="ltr:i-lucide-chevron-right rtl:i-lucide-chevron-left"
          class="size-4 text-n-slate-10"
        />
      </span>
    </button>

    <p v-if="!hasMedia" class="px-4 pb-3 text-xs text-n-slate-10">
      {{ t('CONVERSATION_SIDEBAR.MEDIA_STRIP.EMPTY') }}
    </p>

    <div v-else class="grid grid-cols-4 gap-1 px-4 pb-3">
      <button
        v-for="(att, idx) in thumbs"
        :key="att.id ?? att.message_id ?? idx"
        type="button"
        class="relative overflow-hidden transition-opacity rounded-lg cursor-pointer aspect-square bg-n-slate-2 hover:opacity-80 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @click="openPanel"
      >
        <img
          v-if="getThumbSrc(att)"
          :src="getThumbSrc(att)"
          class="object-cover w-full h-full"
          alt=""
        />
        <!-- Sem miniatura (doc/áudio): ícone de tipo. Escondido na casinha do
             contador, senão o ícone atravessa o "+N" e os dois ficam ilegíveis. -->
        <span
          v-else-if="!isOverflowSlot(idx)"
          class="flex items-center justify-center w-full h-full text-n-slate-11"
        >
          <Icon :icon="getFallbackIcon(att)" class="size-6" />
        </span>

        <!-- Vídeo: overlay de play sobre a miniatura -->
        <span
          v-if="isVideo(att) && !isOverflowSlot(idx)"
          class="absolute inset-0 flex items-center justify-center bg-black/20"
        >
          <Icon
            icon="i-teenyicons-play-small-solid"
            class="text-white size-6"
          />
        </span>

        <!-- Última casinha vira o contador quando há mais mídias -->
        <span
          v-if="isOverflowSlot(idx)"
          class="absolute inset-0 flex items-center justify-center text-base font-semibold leading-none text-white tabular-nums bg-black/60"
        >
          {{
            t('CONVERSATION_SIDEBAR.MEDIA_STRIP.MORE_COUNT', {
              count: overflowCount,
            })
          }}
        </span>
      </button>
    </div>

    <Dialog
      ref="panelDialogRef"
      width="2xl"
      full-height
      :show-cancel-button="false"
      :show-confirm-button="false"
    >
      <div class="flex flex-col flex-1 min-h-0 gap-4">
        <div class="flex items-center justify-between gap-2 shrink-0">
          <h3 class="text-base font-medium leading-6 text-n-slate-12">
            {{ t('CONVERSATION_SIDEBAR.MEDIA_STRIP.PANEL_TITLE') }}
          </h3>
          <button
            type="button"
            class="flex items-center justify-center transition-colors rounded-md size-8 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
            :title="t('ATTACHMENT_PREVIEW.CLOSE')"
            :aria-label="t('ATTACHMENT_PREVIEW.CLOSE')"
            @click="closePanel"
          >
            <Icon icon="i-lucide-x" class="size-4" />
          </button>
        </div>
        <ConversationMedia
          :conversation-id="conversationId"
          :initial-tab="activeTab"
          @open-gallery="handleOpenGallery"
          @tab-change="onTabChange"
        />
      </div>
    </Dialog>

    <GalleryView
      v-if="isGalleryOpen && galleryAttachment && galleryList.length > 0"
      v-model:show="isGalleryOpen"
      :attachment="galleryAttachment"
      :all-attachments="galleryList"
      @close="closeGallery"
    />
  </div>
</template>
