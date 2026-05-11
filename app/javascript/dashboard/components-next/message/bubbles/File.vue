<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import { useMessageContext } from '../provider.js';
import BaseAttachmentBubble from './BaseAttachment.vue';
import BaseBubble from './Base.vue';
import FileIcon from 'next/icon/FileIcon.vue';

const { attachments } = useMessageContext();

const { t } = useI18n();

const url = computed(() => {
  return attachments.value[0].dataUrl;
});

const fileName = computed(() => {
  if (url.value) {
    const filename = url.value.substring(url.value.lastIndexOf('/') + 1);
    return filename || t('CONVERSATION.UNKNOWN_FILE_TYPE');
  }
  return t('CONVERSATION.UNKNOWN_FILE_TYPE');
});

const fileType = computed(() => {
  return fileName.value.split('.').pop();
});

const isPdf = computed(
  () =>
    fileType.value?.toLowerCase() === 'pdf' ||
    /\.pdf(\?|$)/i.test(url.value || '')
);
</script>

<template>
  <BaseBubble
    v-if="isPdf"
    class="overflow-hidden p-2"
    data-bubble-name="pdf-preview"
  >
    <div class="flex flex-col gap-2 min-w-72">
      <div class="rounded-md overflow-hidden border border-n-weak bg-n-alpha-2">
        <embed
          :src="`${url}#toolbar=0&navpanes=0&view=FitH`"
          type="application/pdf"
          class="w-full h-72 block"
        />
      </div>
      <div class="flex items-center justify-between gap-2">
        <span class="text-xs text-n-slate-11 truncate">
          {{ decodeURI(fileName) }}
        </span>
        <a
          :href="url"
          rel="noreferrer noopener nofollow"
          target="_blank"
          class="text-xs px-2 py-1 rounded-md bg-n-solid-3 border border-n-container hover:bg-n-alpha-3 whitespace-nowrap"
        >
          {{ $t('CONVERSATION.PDF_PREVIEW.OPEN_FULL') }}
        </a>
      </div>
    </div>
  </BaseBubble>
  <BaseAttachmentBubble
    v-else
    icon="i-teenyicons-user-circle-solid"
    icon-bg-color="bg-n-alpha-3 dark:bg-n-alpha-white"
    sender-translation-key="CONVERSATION.SHARED_ATTACHMENT.FILE"
    :content="decodeURI(fileName)"
    :action="{
      href: url,
      label: $t('CONVERSATION.DOWNLOAD'),
    }"
  >
    <template #icon>
      <FileIcon :file-type="fileType" class="size-4" />
    </template>
  </BaseAttachmentBubble>
</template>
