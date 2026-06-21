<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseBubble from './Base.vue';
import AudioChip from 'next/message/chips/Audio.vue';
import ProgressRing from 'dashboard/components-next/upload/ProgressRing.vue';
import { useMessageContext } from '../provider.js';

const { attachments } = useMessageContext();
const { t } = useI18n();

const attachment = computed(() => {
  return attachments.value[0];
});

const isUploading = computed(
  () => attachment.value?.uploadStatus === 'uploading'
);
const uploadProgress = computed(() =>
  typeof attachment.value?.uploadProgress === 'number'
    ? attachment.value.uploadProgress
    : null
);
</script>

<template>
  <!-- Upload em andamento: anel de progresso + rótulo no lugar do player. -->
  <BaseBubble
    v-if="isUploading"
    class="bg-transparent"
    data-bubble-name="audio-uploading"
  >
    <div class="flex items-center gap-3 p-2 min-w-48">
      <ProgressRing :value="uploadProgress" :size="32" :stroke="3" />
      <span class="text-sm text-n-slate-11">
        {{ t('ATTACHMENT_PREVIEW.UPLOADING') }}
      </span>
    </div>
  </BaseBubble>
  <BaseBubble v-else class="bg-transparent" data-bubble-name="audio">
    <AudioChip
      :attachment="attachment"
      class="p-2 text-n-slate-12 skip-context-menu"
    />
  </BaseBubble>
</template>
