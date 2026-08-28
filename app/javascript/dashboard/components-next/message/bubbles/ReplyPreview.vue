<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import FileIcon from 'next/icon/FileIcon.vue';
import Icon from 'next/icon/Icon.vue';

import { ATTACHMENT_TYPES } from '../constants';
import {
  buildGroupAuthor,
  groupAuthorLabels,
  groupAuthorStyle,
} from '../groupAuthorPresenter.js';

const props = defineProps({
  inReplyTo: {
    type: Object,
    default: null,
  },
});

const { t } = useI18n();

/**
 * Autor da mensagem CITADA. Num grupo é justamente o que falta para o agente saber a
 * qual thread a resposta pertence — a barra colorida à esquerda entrega isso sem leitura.
 * Fora de grupo (ou em mensagem legada, sem `group_sender`) devolve null e o preview
 * fica exatamente como é hoje.
 */
const quotedGroupAuthor = computed(() => {
  const attrs = props.inReplyTo?.contentAttributes || {};
  const sender = attrs.groupSender ?? attrs.group_sender ?? null;

  return buildGroupAuthor(sender, groupAuthorLabels(t));
});

const hasContent = computed(() => !!props.inReplyTo?.content);
const firstAttachment = computed(() => {
  const attachments = props.inReplyTo?.attachments;
  if (!attachments?.length) return null;
  return attachments[0];
});

const attachmentFileType = computed(() => {
  const att = firstAttachment.value;
  if (!att) return null;
  return att.fileType ?? att.file_type ?? null;
});

const showAttachmentPreview = computed(() => !!firstAttachment.value);

const showTextPreview = computed(
  () => !!hasContent.value && !firstAttachment.value
);

const isImage = computed(
  () =>
    attachmentFileType.value === ATTACHMENT_TYPES.IMAGE ||
    attachmentFileType.value === ATTACHMENT_TYPES.IG_REEL
);

const isVideo = computed(
  () =>
    attachmentFileType.value === ATTACHMENT_TYPES.VIDEO ||
    attachmentFileType.value === ATTACHMENT_TYPES.IG_REEL
);

const isAudio = computed(
  () => attachmentFileType.value === ATTACHMENT_TYPES.AUDIO
);

const isFile = computed(
  () =>
    attachmentFileType.value === ATTACHMENT_TYPES.FILE ||
    attachmentFileType.value === ATTACHMENT_TYPES.FALLBACK
);

const imagePreviewUrl = computed(() => {
  const att = firstAttachment.value;
  if (!att) return '';
  return att.thumbUrl ?? att.thumb_url ?? att.dataUrl ?? att.data_url ?? '';
});

const videoPreviewUrl = computed(() => {
  const att = firstAttachment.value;
  if (!att) return '';
  return att.thumbUrl ?? att.thumb_url ?? '';
});

const attachmentLabel = computed(() => {
  const type = attachmentFileType.value;
  if (!type) return t('CONVERSATION.REPLY_MESSAGE_NOT_FOUND');
  const key = `CHAT_LIST.ATTACHMENTS.${type}.CONTENT`;
  const translated = t(key);
  return translated !== key
    ? translated
    : t('CHAT_LIST.ATTACHMENTS.file.CONTENT');
});

const fileName = computed(() => {
  const att = firstAttachment.value;
  if (!att) return '';
  const url = att.dataUrl ?? att.data_url ?? '';
  if (!url) {
    const ext = att.extension ?? '';
    return ext ? `Documento.${ext}` : t('CONVERSATION.UNKNOWN_FILE_TYPE');
  }
  try {
    const segment = url.substring(url.lastIndexOf('/') + 1);
    const decoded = decodeURIComponent(segment);
    if (decoded && decoded.length < 80) return decoded;
    const ext = att.extension ?? segment.split('.').pop() ?? '';
    return ext ? `Documento.${ext}` : t('CONVERSATION.UNKNOWN_FILE_TYPE');
  } catch {
    return att.extension
      ? `Documento.${att.extension}`
      : t('CONVERSATION.UNKNOWN_FILE_TYPE');
  }
});

const fileExtension = computed(() => {
  const name = fileName.value;
  const ext = firstAttachment.value?.extension;
  if (ext) return ext;
  const parts = name.split('.');
  return parts.length > 1 ? parts.pop().toLowerCase() : 'file';
});
</script>

<template>
  <!-- Sem autor de grupo o wrapper vira `display: contents` e some do layout: a
       conversa 1:1 renderiza exatamente a mesma árvore visual de antes. -->
  <div
    :class="
      quotedGroupAuthor
        ? 'min-w-0 border-l-2 pl-2 border-[var(--group-author-color)] dark:border-[var(--group-author-color-dark)]'
        : 'contents'
    "
    :style="quotedGroupAuthor ? groupAuthorStyle(quotedGroupAuthor) : null"
  >
    <span
      v-if="quotedGroupAuthor"
      class="block mb-0.5 max-w-full truncate text-[13px] leading-tight text-[var(--group-author-color)] dark:text-[var(--group-author-color-dark)]"
      :class="
        quotedGroupAuthor.isUnknown ? 'italic font-medium' : 'font-semibold'
      "
    >
      {{ quotedGroupAuthor.label }}
    </span>
    <div class="flex items-center gap-2 min-w-0">
      <!-- Reply with text: show truncated content -->
      <template v-if="showTextPreview">
        <span class="break-all line-clamp-2 text-current">
          {{ inReplyTo.content }}
        </span>
      </template>

      <!-- Attachment-only: show preview by type -->
      <template v-else-if="showAttachmentPreview && firstAttachment">
        <!-- Image: thumbnail -->
        <template v-if="isImage && imagePreviewUrl">
          <img
            :src="imagePreviewUrl"
            :alt="t('CHAT_LIST.ATTACHMENTS.image.CONTENT')"
            class="size-10 shrink-0 rounded object-cover skip-context-menu"
          />
          <span class="min-w-0 truncate text-current">
            {{ attachmentLabel }}
          </span>
        </template>

        <!-- Video: thumbnail if available, else icon + label -->
        <template v-else-if="isVideo">
          <img
            v-if="videoPreviewUrl"
            :src="videoPreviewUrl"
            :alt="attachmentLabel"
            class="size-10 shrink-0 rounded object-cover skip-context-menu"
          />
          <div
            v-else
            class="size-10 shrink-0 rounded bg-n-alpha-3 flex items-center justify-center"
          >
            <Icon icon="i-lucide-video" class="size-5 text-n-slate-11" />
          </div>
          <span class="min-w-0 truncate text-current">{{
            attachmentLabel
          }}</span>
        </template>

        <!-- Audio: icon + label -->
        <template v-else-if="isAudio">
          <div
            class="size-10 shrink-0 rounded bg-n-alpha-3 flex items-center justify-center"
          >
            <Icon icon="i-lucide-mic" class="size-5 text-n-slate-11" />
          </div>
          <span class="min-w-0 truncate text-current">{{
            attachmentLabel
          }}</span>
        </template>

        <!-- File / PDF: icon + file name -->
        <template v-else-if="isFile">
          <div
            class="size-10 shrink-0 rounded bg-n-alpha-3 flex items-center justify-center"
          >
            <FileIcon
              :file-type="fileExtension"
              class="size-5 text-n-slate-11"
            />
          </div>
          <span class="min-w-0 truncate text-current" :title="fileName">{{
            fileName
          }}</span>
        </template>

        <!-- Other types (location, contact, embed, etc.): icon + label -->
        <template v-else>
          <div
            class="size-10 shrink-0 rounded bg-n-alpha-3 flex items-center justify-center"
          >
            <Icon icon="i-lucide-paperclip" class="size-5 text-n-slate-11" />
          </div>
          <span class="min-w-0 truncate text-current">{{
            attachmentLabel
          }}</span>
        </template>
      </template>

      <!-- Fallback: message not found -->
      <template v-else>
        <span class="text-current">
          {{ $t('CONVERSATION.REPLY_MESSAGE_NOT_FOUND') }}
        </span>
      </template>
    </div>
  </div>
</template>
