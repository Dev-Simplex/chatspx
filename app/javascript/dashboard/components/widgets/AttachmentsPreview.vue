<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatBytes } from 'shared/helpers/FileHelper';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
import ProgressRing from 'dashboard/components-next/upload/ProgressRing.vue';

const props = defineProps({
  attachments: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['removeAttachment', 'retryUpload']);

const { t } = useI18n();

const nonRecordedAudioAttachments = computed(() => {
  return props.attachments.filter(attachment => !attachment?.isRecordedAudio);
});

const recordedAudioAttachments = computed(() =>
  props.attachments.filter(attachment => attachment.isRecordedAudio)
);

const onRemoveAttachment = itemIndex => {
  emit(
    'removeAttachment',
    nonRecordedAudioAttachments.value
      .filter((_, index) => index !== itemIndex)
      .concat(recordedAudioAttachments.value)
  );
};

const formatFileSize = file => {
  const size = file.byte_size || file.size;
  return formatBytes(size, 0);
};

const isTypeImage = file => {
  const type = file.content_type || file.type;
  return type.includes('image');
};

const isTypeVideo = file => {
  const type = file.content_type || file.type;
  return type.includes('video');
};

const isTypeAudio = file => {
  const type = file.content_type || file.type;
  return type.includes('audio');
};

const fileName = file => {
  return file.filename || file.name;
};

// DirectUpload lifecycle of the attachment (set while it transfers on attach).
const uploadStatusOf = attachment => attachment?.uploadStatus;
const uploadProgressOf = attachment =>
  typeof attachment?.uploadProgress === 'number'
    ? attachment.uploadProgress
    : null;

const onRetry = attachment => {
  // eslint-disable-next-line vue/custom-event-name-casing
  emit('retryUpload', attachment);
};
</script>

<template>
  <div class="flex flex-wrap gap-y-1 gap-x-2 overflow-auto max-h-[12.5rem]">
    <div
      v-for="(attachment, index) in nonRecordedAudioAttachments"
      :key="attachment.id"
      class="flex items-center p-1 bg-n-slate-3 gap-1 rounded-md w-[15rem]"
    >
      <div class="max-w-[4rem] flex-shrink-0 w-6 flex items-center">
        <!-- Upload in flight: show the per-attachment progress ring instead of
             the thumb so the agent gets feedback while it transfers. -->
        <ProgressRing
          v-if="uploadStatusOf(attachment) === 'uploading'"
          :value="uploadProgressOf(attachment)"
          :size="22"
          :stroke="3"
        />
        <button
          v-else-if="uploadStatusOf(attachment) === 'failed'"
          type="button"
          class="grid place-content-center w-6 h-6 text-n-ruby-9"
          :title="t('ATTACHMENT_PREVIEW.RETRY')"
          @click="onRetry(attachment)"
        >
          <Icon icon="i-lucide-rotate-cw" class="size-4" />
        </button>
        <img
          v-else-if="isTypeImage(attachment.resource)"
          class="object-cover w-6 h-6 rounded-sm"
          :src="attachment.thumb"
        />
        <video
          v-else-if="isTypeVideo(attachment.resource) && attachment.thumb"
          class="object-cover w-6 h-6 rounded-sm bg-black"
          :src="attachment.thumb"
          muted
          playsinline
          preload="metadata"
        />
        <Icon
          v-else-if="isTypeVideo(attachment.resource)"
          icon="i-lucide-clapperboard"
          class="size-5 text-n-slate-11"
        />
        <Icon
          v-else-if="isTypeAudio(attachment.resource)"
          icon="i-lucide-music"
          class="size-5 text-n-slate-11"
        />
        <Icon v-else icon="i-lucide-file" class="size-5 text-n-slate-11" />
      </div>
      <div class="max-w-3/5 min-w-[50%] overflow-hidden text-ellipsis">
        <span
          class="h-4 overflow-hidden text-sm font-medium text-ellipsis whitespace-nowrap"
        >
          {{ fileName(attachment.resource) }}
        </span>
      </div>
      <div class="w-[30%] justify-center">
        <span class="overflow-hidden text-xs text-ellipsis whitespace-nowrap">
          {{ formatFileSize(attachment.resource) }}
        </span>
      </div>
      <div class="flex items-center justify-center">
        <Button
          ghost
          slate
          xs
          icon="i-lucide-x"
          @click="onRemoveAttachment(index)"
        />
      </div>
    </div>
  </div>
</template>
