<script setup>
import { ref, computed, onMounted, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

import { useStoreGetters } from 'dashboard/composables/store';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useImageZoom } from 'dashboard/composables/useImageZoom';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import { downloadFile } from '@chatwoot/utils';

import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

const props = defineProps({
  attachment: {
    type: Object,
    required: true,
  },
  allAttachments: {
    type: Array,
    required: true,
  },
  hasMore: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['close', 'loadMore']);
const show = defineModel('show', { type: Boolean, default: false });

const { t } = useI18n();
const getters = useStoreGetters();

const ALLOWED_FILE_TYPES = {
  IMAGE: 'image',
  VIDEO: 'video',
  IG_REEL: 'ig_reel',
};

const isDownloading = ref(false);
const activeAttachment = ref({});
const activeFileType = ref('');

const getAttachmentIndex = attachment => {
  if (!attachment) return 0;

  if (attachment.id != null) {
    const byId = props.allAttachments.findIndex(
      item => item.id === attachment.id
    );
    if (byId !== -1) return byId;
  }

  const byMessage = props.allAttachments.findIndex(
    item => item.message_id === attachment.message_id
  );
  return byMessage !== -1 ? byMessage : 0;
};

const activeImageIndex = ref(getAttachmentIndex(props.attachment));

const imageRef = useTemplateRef('imageRef');

const {
  imageWrapperStyle,
  imageStyle,
  onRotate,
  activeImageRotation,
  onZoom,
  onDoubleClickZoomImage,
  onWheelImageZoom,
  onMouseMove,
  onMouseLeave,
  resetZoomAndRotation,
} = useImageZoom(imageRef);

const currentUser = computed(() => getters.getCurrentUser.value);
const hasMoreThanOneAttachment = computed(
  () => props.allAttachments.length > 1
);

const readableTime = computed(() => {
  const { created_at: createdAt } = activeAttachment.value;
  if (!createdAt) return '';
  return messageTimestamp(createdAt, 'LLL d yyyy, h:mm a') || '';
});

const isImage = computed(
  () => activeFileType.value === ALLOWED_FILE_TYPES.IMAGE
);
const isVideo = computed(() =>
  [ALLOWED_FILE_TYPES.VIDEO, ALLOWED_FILE_TYPES.IG_REEL].includes(
    activeFileType.value
  )
);
const actionButtonClass =
  '!text-white/80 hover:!text-white !bg-transparent hover:!bg-white/10';
const navButtonClass =
  'size-10 rounded-full bg-white/10 hover:bg-white/20 text-white/90 flex items-center justify-center disabled:opacity-30 disabled:cursor-not-allowed';
const thumbnailButtonBase =
  'relative size-12 rounded-md overflow-hidden flex items-center justify-center shrink-0';
const thumbnailActiveClass = 'ring-2 ring-[#25D366]';
const thumbnailInactiveClass = 'ring-1 ring-white/10 hover:ring-white/30';

const senderDetails = computed(() => {
  const {
    name,
    available_name: availableName,
    avatar_url,
    thumbnail,
    id,
  } = activeAttachment.value?.sender || props.attachment?.sender || {};

  return {
    name:
      currentUser.value?.id === id
        ? t('GALLERY_VIEW.SENT_BY_YOU')
        : name || availableName || '',
    avatar: thumbnail || avatar_url || '',
  };
});

const fileNameFromDataUrl = computed(() => {
  if (activeAttachment.value?.filename) return activeAttachment.value.filename;

  const { data_url: dataUrl } = activeAttachment.value;
  if (!dataUrl) return '';

  const fileName = dataUrl.split('/').pop()?.split('?')[0];
  return fileName ? decodeURIComponent(fileName) : '';
});

const onClose = () => emit('close');

const setImageAndVideoSrc = attachment => {
  const { file_type: type } = attachment;
  if (!Object.values(ALLOWED_FILE_TYPES).includes(type)) return;

  activeAttachment.value = attachment;
  activeFileType.value = type;
};

const goToAttachment = (attachment, index = null) => {
  if (!attachment) return;

  const resolvedIndex =
    typeof index === 'number' && index >= 0
      ? index
      : getAttachmentIndex(attachment);
  activeImageIndex.value = resolvedIndex;
  setImageAndVideoSrc(attachment);
  resetZoomAndRotation();
};

const onClickChangeAttachment = (attachment, index) => {
  goToAttachment(attachment, index);
};

const canGoPrev = computed(() => activeImageIndex.value > 0);
const canGoNext = computed(
  () => activeImageIndex.value < props.allAttachments.length - 1
);

const goPrev = () => {
  if (!canGoPrev.value) return;
  onClickChangeAttachment(
    props.allAttachments[activeImageIndex.value - 1],
    activeImageIndex.value - 1
  );
};

const goNext = () => {
  if (!canGoNext.value) return;
  onClickChangeAttachment(
    props.allAttachments[activeImageIndex.value + 1],
    activeImageIndex.value + 1
  );
};

const getThumbnailSrc = attachment => {
  if (attachment?.thumb_url) return attachment.thumb_url;
  if (attachment?.file_type === ALLOWED_FILE_TYPES.IMAGE)
    return attachment.data_url;
  return '';
};

const isVideoAttachment = attachment =>
  [ALLOWED_FILE_TYPES.VIDEO, ALLOWED_FILE_TYPES.IG_REEL].includes(
    attachment?.file_type
  );

const touchStartX = ref(0);
const touchEndX = ref(0);
const onTouchStart = event => {
  touchStartX.value = event.touches[0].clientX;
};

const onTouchEnd = event => {
  touchEndX.value = event.changedTouches[0].clientX;
  const delta = touchStartX.value - touchEndX.value;
  if (Math.abs(delta) < 40) return;
  if (delta > 0) {
    goNext();
  } else {
    goPrev();
  }
};

const LOAD_MORE_THRESHOLD = 5;
const checkLoadMore = () => {
  if (!props.hasMore) return;
  const remaining = props.allAttachments.length - 1 - activeImageIndex.value;
  if (remaining <= LOAD_MORE_THRESHOLD) {
    emit('loadMore');
  }
};

watch(activeImageIndex, () => {
  checkLoadMore();
});

const onClickDownload = async () => {
  const { file_type: type, data_url: url, extension } = activeAttachment.value;
  if (!Object.values(ALLOWED_FILE_TYPES).includes(type)) return;

  try {
    isDownloading.value = true;
    await downloadFile({ url, type, extension });
  } catch (error) {
    useAlert(t('GALLERY_VIEW.ERROR_DOWNLOADING'));
  } finally {
    isDownloading.value = false;
  }
};

const keyboardEvents = {
  Escape: { action: onClose },
  ArrowLeft: {
    action: goPrev,
  },
  ArrowRight: {
    action: goNext,
  },
};

useKeyboardEvents(keyboardEvents);

onMounted(() => {
  goToAttachment(props.attachment);
});
</script>

<template>
  <TeleportWithDirection to="body">
    <woot-modal
      v-model:show="show"
      full-width
      :show-close-button="false"
      :on-close="onClose"
    >
      <div
        class="bg-[#0b141a] text-white flex flex-col h-[inherit] w-[inherit] overflow-hidden select-none"
        @click="onClose"
      >
        <header
          class="z-10 flex items-center justify-between w-full h-16 px-4 py-2 bg-[#202c33] border-b border-white/10"
          @click.stop
        >
          <div
            v-if="senderDetails"
            class="flex items-center min-w-[15rem] shrink-0"
          >
            <div
              v-if="senderDetails.avatar"
              class="flex-shrink-0 size-10 rounded-full overflow-hidden bg-white/10"
            >
              <img
                :src="senderDetails.avatar"
                alt=""
                class="w-full h-full object-cover"
              />
            </div>
            <div class="flex flex-col ml-2 rtl:ml-0 rtl:mr-2 overflow-hidden">
              <h3 class="text-base leading-5 m-0 font-medium">
                <span
                  class="overflow-hidden text-white whitespace-nowrap text-ellipsis"
                >
                  {{ senderDetails.name }}
                </span>
              </h3>
              <span
                class="text-xs text-white/60 whitespace-nowrap text-ellipsis"
              >
                {{ readableTime }}
              </span>
            </div>
          </div>

          <div
            class="flex-1 mx-2 px-2 truncate text-sm font-medium text-center text-white/70"
          >
            <span v-dompurify-html="fileNameFromDataUrl" class="truncate" />
          </div>

          <div class="flex items-center gap-2 ml-2 shrink-0">
            <NextButton
              v-if="isImage"
              icon="i-lucide-zoom-in"
              slate
              ghost
              :class="actionButtonClass"
              @click="onZoom(0.1)"
            />
            <NextButton
              v-if="isImage"
              icon="i-lucide-zoom-out"
              slate
              ghost
              :class="actionButtonClass"
              @click="onZoom(-0.1)"
            />
            <NextButton
              v-if="isImage"
              icon="i-lucide-rotate-ccw"
              slate
              ghost
              :class="actionButtonClass"
              @click="onRotate('counter-clockwise')"
            />
            <NextButton
              v-if="isImage"
              icon="i-lucide-rotate-cw"
              slate
              ghost
              :class="actionButtonClass"
              @click="onRotate('clockwise')"
            />
            <NextButton
              icon="i-lucide-download"
              slate
              ghost
              :class="actionButtonClass"
              :is-loading="isDownloading"
              :disabled="isDownloading"
              @click="onClickDownload"
            />
            <NextButton
              icon="i-lucide-x"
              slate
              ghost
              :class="actionButtonClass"
              @click="onClose"
            />
          </div>
        </header>

        <main
          class="flex items-stretch flex-1 h-full overflow-hidden"
          @touchstart="hasMoreThanOneAttachment && onTouchStart($event)"
          @touchend="hasMoreThanOneAttachment && onTouchEnd($event)"
        >
          <div class="flex items-center justify-center w-16 shrink-0">
            <button
              v-if="hasMoreThanOneAttachment"
              type="button"
              :class="navButtonClass"
              :disabled="!canGoPrev"
              @click.stop="goPrev"
            >
              <Icon
                icon="ltr:i-lucide-chevron-left rtl:i-lucide-chevron-right"
                class="size-5"
              />
            </button>
          </div>

          <div class="flex-1 flex items-center justify-center overflow-hidden">
            <div
              v-if="isImage"
              :style="imageWrapperStyle"
              class="flex items-center justify-center origin-center"
              :class="{
                // Adjust dimensions when rotated 90/270 degrees to maintain visibility
                // and prevent image from overflowing container in different aspect ratios
                'w-[calc(100dvh-8rem)] h-[calc(100dvw-7rem)]':
                  activeImageRotation % 180 !== 0,
                'size-full': activeImageRotation % 180 === 0,
              }"
            >
              <img
                ref="imageRef"
                :key="
                  activeAttachment.id ||
                  `${activeAttachment.message_id}-${activeImageIndex}`
                "
                :src="activeAttachment.data_url"
                :style="imageStyle"
                class="max-h-full max-w-full object-contain duration-100 ease-in-out transform select-none"
                @click.stop
                @dblclick.stop="onDoubleClickZoomImage"
                @wheel.prevent.stop="onWheelImageZoom"
                @mousemove="onMouseMove"
                @mouseleave="onMouseLeave"
              />
            </div>

            <video
              v-if="isVideo"
              :key="
                activeAttachment.id ||
                `${activeAttachment.message_id}-${activeImageIndex}`
              "
              :src="activeAttachment.data_url"
              controls
              preload="metadata"
              playsInline
              class="max-h-full max-w-full object-contain"
              @click.stop
            />
          </div>

          <div class="flex items-center justify-center w-16 shrink-0">
            <button
              v-if="hasMoreThanOneAttachment"
              type="button"
              :class="navButtonClass"
              :disabled="!canGoNext"
              @click.stop="goNext"
            >
              <Icon
                icon="ltr:i-lucide-chevron-right rtl:i-lucide-chevron-left"
                class="size-5"
              />
            </button>
          </div>
        </main>

        <footer
          v-if="hasMoreThanOneAttachment"
          class="z-10 border-t border-white/10 bg-[#202c33]"
          @click.stop
        >
          <div class="flex items-center gap-3 px-4 py-3">
            <div class="text-xs text-white/60 shrink-0">
              {{ `${activeImageIndex + 1} / ${allAttachments.length}` }}
            </div>
            <div class="flex-1 overflow-x-auto">
              <div class="flex items-center gap-2">
                <button
                  v-for="(attachment, index) in allAttachments"
                  :key="attachment.id || `${attachment.message_id}-${index}`"
                  type="button"
                  :class="[
                    thumbnailButtonBase,
                    index === activeImageIndex
                      ? thumbnailActiveClass
                      : thumbnailInactiveClass,
                  ]"
                  @click.stop="onClickChangeAttachment(attachment, index)"
                >
                  <img
                    v-if="getThumbnailSrc(attachment)"
                    :src="getThumbnailSrc(attachment)"
                    class="w-full h-full object-cover"
                  />
                  <div
                    v-else
                    class="w-full h-full bg-white/5 flex items-center justify-center"
                  >
                    <Icon icon="i-lucide-image" class="text-white/70" />
                  </div>
                  <div
                    v-if="isVideoAttachment(attachment)"
                    class="absolute inset-0 bg-black/30 flex items-center justify-center"
                  >
                    <div
                      class="size-6 rounded-full bg-black/40 flex items-center justify-center"
                    >
                      <Icon
                        icon="i-teenyicons-play-small-solid"
                        class="text-white"
                      />
                    </div>
                  </div>
                </button>
              </div>
            </div>
          </div>
        </footer>
      </div>
    </woot-modal>
  </TeleportWithDirection>
</template>
