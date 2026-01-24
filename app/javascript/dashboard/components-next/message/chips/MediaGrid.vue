<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { useMessageContext } from '../provider.js';
import { ATTACHMENT_TYPES } from '../constants';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';

const props = defineProps({
  attachments: {
    type: Array,
    default: () => [],
  },
  maxVisible: {
    type: Number,
    default: 4,
  },
});

const { t } = useI18n();
const { filteredCurrentChatAttachments } = useMessageContext();

const showGallery = ref(false);
const activeAttachment = ref(null);
const errorMap = ref({});

const visibleAttachments = computed(() =>
  props.attachments.slice(0, props.maxVisible)
);
const extraCount = computed(() =>
  Math.max(0, props.attachments.length - visibleAttachments.value.length)
);

const layout = computed(() => {
  const count = visibleAttachments.value.length;
  if (count <= 1) return 'single';
  if (count === 2) return 'two';
  if (count === 3) return 'three';
  return 'four';
});

const isSingle = computed(() => layout.value === 'single');
const singleAspectRatio = computed(() => {
  if (!isSingle.value) return null;
  const { width, height } = visibleAttachments.value[0] || {};
  if (width && height) return `${width} / ${height}`;
  return null;
});

const hasSingleAspectRatio = computed(() => !!singleAspectRatio.value);

const containerClass = computed(() => [
  'inline-block',
  'rounded-[18px]',
  'overflow-hidden',
  'p-[2px]',
]);

const gridClass = computed(() => {
  const classes = [
    'grid',
    'gap-[2px]',
    'max-w-full',
    'select-none',
    'w-[220px]',
    'sm:w-[280px]',
    'md:w-[340px]',
    'max-w-[75vw]',
  ];

  if (layout.value === 'single') {
    classes.push('grid-cols-1');
  } else if (layout.value === 'two') {
    classes.push('grid-cols-2', 'grid-rows-1', 'aspect-[2/1]');
  } else {
    classes.push('grid-cols-2', 'grid-rows-2', 'aspect-square');
  }

  return classes;
});

const tileClass = index => {
  const base = ['relative', 'w-full', 'h-full', 'cursor-pointer', 'overflow-hidden', 'skip-context-menu'];
  if (layout.value === 'single') return base.concat('rounded-[16px]');
  if (layout.value === 'three' && index === 0) {
    return base.concat('row-span-2', 'rounded-l-[16px]');
  }
  if (layout.value === 'two') {
    return base.concat(index === 0 ? 'rounded-l-[16px]' : 'rounded-r-[16px]');
  }
  if (layout.value === 'four') {
    const map = {
      0: 'rounded-tl-[16px]',
      1: 'rounded-tr-[16px]',
      2: 'rounded-bl-[16px]',
      3: 'rounded-br-[16px]',
    };
    return base.concat(map[index] || '');
  }
  if (layout.value === 'three') {
    return base.concat(index === 1 ? 'rounded-tr-[16px]' : 'rounded-br-[16px]');
  }
  return base;
};

const tileHasError = index => !!errorMap.value[index];

const onTileError = index => {
  errorMap.value = { ...errorMap.value, [index]: true };
};

const isVideoAttachment = attachment =>
  [ATTACHMENT_TYPES.VIDEO, ATTACHMENT_TYPES.IG_REEL].includes(
    attachment?.fileType
  );

const isImageAttachment = attachment =>
  attachment?.fileType === ATTACHMENT_TYPES.IMAGE;

const shouldUseFullSize = computed(() => isSingle.value);

const getMediaSrc = attachment => {
  if (!attachment) return '';
  if (shouldUseFullSize.value) return attachment.dataUrl || attachment.thumbUrl;
  return attachment.thumbUrl || attachment.dataUrl;
};

const mediaClass = index => {
  if (layout.value === 'single') {
    return hasSingleAspectRatio.value
      ? 'w-full h-full max-h-[60vh] object-contain bg-black/5 dark:bg-white/5 skip-context-menu'
      : 'w-full h-auto max-h-[60vh] object-contain bg-black/5 dark:bg-white/5 skip-context-menu';
  }
  return 'w-full h-full object-cover skip-context-menu';
};

const openGallery = attachment => {
  if (!attachment) return;
  activeAttachment.value = attachment;
  showGallery.value = true;
};

const activeAttachmentSnake = computed(() => {
  if (!activeAttachment.value) return null;
  return useSnakeCase(activeAttachment.value);
});

const shouldShowMoreOverlay = index =>
  extraCount.value > 0 && index === visibleAttachments.value.length - 1;
</script>

<template>
  <div :class="containerClass">
    <div
      :class="gridClass"
      :style="
        singleAspectRatio ? { aspectRatio: singleAspectRatio } : undefined
      "
    >
      <button
        v-for="(attachment, index) in visibleAttachments"
        :key="attachment.id || index"
        type="button"
        :class="tileClass(index)"
        @click="openGallery(attachment)"
      >
        <div
          v-if="tileHasError(index)"
          class="flex flex-col items-center justify-center gap-1 text-xs text-center bg-n-alpha-1 text-n-slate-11 w-full h-full"
        >
          <Icon icon="i-lucide-circle-off" class="text-n-slate-11" />
          <span>{{ t('COMPONENTS.MEDIA.LOADING_FAILED') }}</span>
        </div>
        <template v-else>
          <img
            v-if="isImageAttachment(attachment) && getMediaSrc(attachment)"
            :src="getMediaSrc(attachment)"
            :class="mediaClass(index)"
            @error="onTileError(index)"
          />
          <img
            v-else-if="isVideoAttachment(attachment) && attachment.thumbUrl"
            :src="attachment.thumbUrl"
            :class="mediaClass(index)"
            @error="onTileError(index)"
          />
          <video
            v-else-if="isVideoAttachment(attachment)"
            :src="attachment.dataUrl"
            :class="mediaClass(index)"
            muted
            playsInline
            preload="metadata"
            @error="onTileError(index)"
          />
          <div
            v-else
            class="w-full h-full bg-n-alpha-1 text-n-slate-11 flex items-center justify-center"
          >
            <Icon icon="i-lucide-image" class="text-n-slate-11" />
          </div>
        </template>
        <div
          v-if="isVideoAttachment(attachment)"
          class="absolute inset-0 bg-black/25 flex items-center justify-center"
        >
          <div
            class="size-8 rounded-full bg-black/40 flex items-center justify-center"
          >
            <Icon
              icon="i-teenyicons-play-small-solid"
              class="text-white"
            />
          </div>
        </div>
        <div
          v-if="shouldShowMoreOverlay(index)"
          class="absolute inset-0 z-10 bg-black/60 text-white text-xl font-semibold flex items-center justify-center"
        >
          +{{ extraCount }}
        </div>
      </button>
    </div>
  </div>
  <GalleryView
    v-if="showGallery && activeAttachmentSnake"
    v-model:show="showGallery"
    :attachment="activeAttachmentSnake"
    :all-attachments="filteredCurrentChatAttachments"
    @close="() => (showGallery = false)"
  />
</template>
