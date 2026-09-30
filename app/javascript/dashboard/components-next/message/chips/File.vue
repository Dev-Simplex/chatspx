<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { getFileInfo } from '@chatwoot/utils';
import { formatBytes } from 'shared/helpers/FileHelper';

import FileIcon from 'next/icon/FileIcon.vue';
import Icon from 'next/icon/Icon.vue';

const { attachment } = defineProps({
  attachment: {
    type: Object,
    required: true,
  },
});

const { t, locale } = useI18n();

const url = computed(() => attachment.dataUrl ?? attachment.data_url);

const fileSize = computed(() => {
  const size = attachment.fileSize ?? attachment.file_size;
  if (size == null) return '';

  const [value, unit] = formatBytes(size, 1).split(' ');
  const localizedSize = Number(value).toLocaleString(
    locale.value.replace('_', '-')
  );
  return `${localizedSize} ${unit}`;
});

const fileDetails = computed(() => {
  return getFileInfo(url.value || '');
});

const displayFileName = computed(() => {
  const { base, type } = fileDetails.value;
  const truncatedName = (str, maxLength, hasExt) =>
    str.length > maxLength
      ? `${str.substring(0, maxLength).trimEnd()}${hasExt ? '..' : '...'}`
      : str;

  return type
    ? `${truncatedName(base, 12, true)}.${type}`
    : truncatedName(base, 14, false);
});

const textColorClass = computed(() => {
  const colorMap = {
    '7z': 'dark:text-[#EDEEF0] text-[#2F265F]',
    csv: 'text-n-amber-12',
    doc: 'dark:text-[#D6E1FF] text-[#1F2D5C]', // indigo-12
    docx: 'dark:text-[#D6E1FF] text-[#1F2D5C]', // indigo-12
    json: 'text-n-slate-12',
    odt: 'dark:text-[#D6E1FF] text-[#1F2D5C]', // indigo-12
    pdf: 'text-n-slate-12',
    ppt: 'dark:text-[#FFE0C2] text-[#582D1D]',
    pptx: 'dark:text-[#FFE0C2] text-[#582D1D]',
    rar: 'dark:text-[#EDEEF0] text-[#2F265F]',
    rtf: 'dark:text-[#D6E1FF] text-[#1F2D5C]', // indigo-12
    tar: 'dark:text-[#EDEEF0] text-[#2F265F]',
    txt: 'text-n-slate-12',
    xls: 'text-n-teal-12',
    xlsx: 'text-n-teal-12',
    zip: 'dark:text-[#EDEEF0] text-[#2F265F]',
  };

  return colorMap[fileDetails.value.type] || 'text-n-slate-12';
});
</script>

<template>
  <div
    class="h-9 bg-n-alpha-white gap-2 overflow-hidden items-center flex px-2 rounded-lg border border-n-container"
  >
    <FileIcon class="flex-shrink-0" :file-type="fileDetails.type" />
    <span
      class="flex-1 min-w-0 text-sm max-w-36"
      :title="fileDetails.name"
      :class="textColorClass"
    >
      {{ displayFileName }}
    </span>
    <span
      v-if="fileSize"
      data-testid="file-size"
      class="shrink-0 whitespace-nowrap text-sm text-n-slate-11"
    >
      {{ `· ${fileSize}` }}
    </span>
    <a
      v-tooltip="t('CONVERSATION.DOWNLOAD')"
      class="flex-shrink-0 size-9 grid place-content-center cursor-pointer text-n-slate-11 hover:text-n-slate-12 transition-colors"
      :href="url"
      rel="noreferrer noopener nofollow"
      target="_blank"
    >
      <Icon icon="i-lucide-download" />
    </a>
  </div>
</template>
