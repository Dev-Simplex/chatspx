<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatBytes } from 'shared/helpers/FileHelper';

import { useMessageContext } from '../provider.js';
import BaseAttachmentBubble from './BaseAttachment.vue';
import BaseBubble from './Base.vue';
import FileIcon from 'next/icon/FileIcon.vue';
import ProgressRing from 'dashboard/components-next/upload/ProgressRing.vue';

const { attachments } = useMessageContext();

const { t, locale } = useI18n();

const url = computed(() => {
  return attachments.value[0].dataUrl ?? attachments.value[0].data_url;
});

// Optimistic "uploading" bubble: a document has no local preview, so show the
// real file name (carried on the optimistic attachment) + a progress ring while
// the DirectUpload runs. The server copy replaces it on completion.
const isUploading = computed(
  () => attachments.value[0]?.uploadStatus === 'uploading'
);
const uploadProgress = computed(() =>
  typeof attachments.value[0]?.uploadProgress === 'number'
    ? attachments.value[0].uploadProgress
    : null
);

const fileName = computed(() => {
  const localName =
    attachments.value[0]?.fileName ?? attachments.value[0]?.file_name;
  if (localName) return localName;
  if (url.value) {
    const filename = url.value.substring(url.value.lastIndexOf('/') + 1);
    return filename || t('CONVERSATION.UNKNOWN_FILE_TYPE');
  }
  return t('CONVERSATION.UNKNOWN_FILE_TYPE');
});

const fileLabel = computed(() => decodeURI(fileName.value));

const fileSize = computed(() => {
  // MessageList camelizes API keys; also accept attachments passed through raw.
  const size =
    attachments.value[0]?.fileSize ?? attachments.value[0]?.file_size;
  if (size == null) return '';

  const [value, unit] = formatBytes(size, 1).split(' ');
  const localizedSize = Number(value).toLocaleString(
    locale.value.replace('_', '-')
  );
  return `${localizedSize} ${unit}`;
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
  <!-- Upload em andamento: cartão com nome do arquivo + anel de progresso. -->
  <BaseBubble v-if="isUploading" class="p-3" data-bubble-name="file-uploading">
    <div class="flex items-center gap-3 min-w-56">
      <ProgressRing :value="uploadProgress" :size="32" :stroke="3" />
      <div class="flex flex-col overflow-hidden">
        <span class="text-sm font-medium truncate">
          {{ fileName }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{ $t('ATTACHMENT_PREVIEW.UPLOADING') }}
        </span>
      </div>
    </div>
  </BaseBubble>
  <BaseBubble
    v-else-if="isPdf"
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
        <div class="flex min-w-0 items-center gap-2 text-xs text-n-slate-11">
          <span class="truncate">{{ fileLabel }}</span>
          <span
            v-if="fileSize"
            data-testid="file-size"
            class="shrink-0 whitespace-nowrap"
          >
            {{ fileSize }}
          </span>
        </div>
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
    :content="fileLabel"
    :action="{
      href: url,
      label: $t('CONVERSATION.DOWNLOAD'),
    }"
  >
    <template #default>
      <div class="flex min-w-0 items-center gap-2 text-sm text-n-slate-11">
        <span class="truncate">{{ fileLabel }}</span>
        <span
          v-if="fileSize"
          data-testid="file-size"
          class="shrink-0 whitespace-nowrap"
        >
          {{ fileSize }}
        </span>
      </div>
    </template>
    <template #icon>
      <FileIcon :file-type="fileType" class="size-4" />
    </template>
  </BaseAttachmentBubble>
</template>
