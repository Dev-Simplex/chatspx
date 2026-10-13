<script setup>
import { ref, computed, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useIntersectionObserver } from '@vueuse/core';
import BaseBubble from './Base.vue';
import Icon from 'next/icon/Icon.vue';
import ProgressRing from 'dashboard/components-next/upload/ProgressRing.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { useMessageContext } from '../provider.js';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';
import { ATTACHMENT_TYPES } from '../constants';
import { formatBytes } from 'shared/helpers/FileHelper';

const emit = defineEmits(['error']);
const { t } = useI18n();
const hasError = ref(false);
const showGallery = ref(false);
const shouldLoadVideo = ref(false);
const videoContainer = useTemplateRef('videoContainer');
const { filteredCurrentChatAttachments, attachments } = useMessageContext();

const handleError = () => {
  hasError.value = true;
  emit('error');
};

const attachment = computed(() => {
  return attachments.value[0];
});

const videoSource = computed(() => {
  return shouldLoadVideo.value ? attachment.value.dataUrl : '';
});

const videoPoster = computed(() => {
  return attachment.value.thumbUrl || undefined;
});

const isReel = computed(() => {
  return attachment.value.fileType === ATTACHMENT_TYPES.IG_REEL;
});

const tamanho = computed(() =>
  attachment.value?.fileSize ? formatBytes(attachment.value.fileSize, 1) : ''
);

const isUploading = computed(
  () => attachment.value?.uploadStatus === 'uploading'
);
const uploadProgress = computed(() =>
  typeof attachment.value?.uploadProgress === 'number'
    ? attachment.value.uploadProgress
    : null
);

const loadVideo = () => {
  if (shouldLoadVideo.value) return;
  shouldLoadVideo.value = true;
};

useIntersectionObserver(
  videoContainer,
  ([entry]) => {
    if (!entry?.isIntersecting) return;
    loadVideo();
  },
  {
    rootMargin: '300px 0px 300px 0px',
  }
);
</script>

<template>
  <BaseBubble
    class="overflow-hidden p-3"
    data-bubble-name="video"
    @click="!isUploading && (showGallery = true)"
  >
    <div ref="videoContainer" class="relative group rounded-lg overflow-hidden">
      <div
        v-if="isUploading"
        class="absolute inset-0 z-10 flex items-center justify-center bg-n-black/40 backdrop-blur-[1px]"
      >
        <ProgressRing :value="uploadProgress" :size="48" :stroke="4" />
      </div>
      <div
        v-if="attachment.comoDocumento"
        class="absolute top-2 left-2 z-[1] flex items-center gap-1 px-2 py-1 rounded-md bg-n-black/70 text-white text-xs font-medium pointer-events-none"
      >
        <Icon icon="i-lucide-file-text" class="size-3.5 flex-shrink-0" />
        {{ t('CONVERSATION.SENT_AS_DOCUMENT_BADGE') }}
        <span v-if="tamanho" class="opacity-75">{{ tamanho }}</span>
      </div>
      <div
        v-if="isReel"
        class="absolute p-2 flex items-start justify-end right-0 pointer-events-none"
      >
        <Icon icon="i-lucide-instagram" class="text-white shadow-lg" />
      </div>
      <video
        controls
        class="rounded-lg skip-context-menu"
        preload="metadata"
        :poster="videoPoster"
        :src="videoSource"
        :class="{
          'max-w-48': isReel,
          'max-w-full': !isReel,
        }"
        @pointerenter="loadVideo"
        @pointerdown="loadVideo"
        @touchstart.passive="loadVideo"
        @focus="loadVideo"
        @click.stop
        @error="handleError"
      />
    </div>
    <div
      v-if="attachment.comoDocumento"
      class="flex items-start gap-2 mt-2 px-2.5 py-2 rounded-lg bg-n-alpha-2 max-w-80"
    >
      <Icon
        icon="i-lucide-file-text"
        class="size-4 mt-0.5 flex-shrink-0 text-n-slate-12"
      />
      <div class="flex flex-col gap-0.5 min-w-0">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('CONVERSATION.SENT_AS_DOCUMENT') }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{ t('CONVERSATION.SENT_AS_DOCUMENT_HINT') }}
        </span>
      </div>
    </div>
  </BaseBubble>
  <GalleryView
    v-if="showGallery"
    v-model:show="showGallery"
    :attachment="useSnakeCase(attachment)"
    :all-attachments="filteredCurrentChatAttachments"
    @error="onError"
    @close="() => (showGallery = false)"
  />
</template>
