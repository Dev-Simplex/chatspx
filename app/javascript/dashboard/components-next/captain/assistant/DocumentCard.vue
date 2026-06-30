<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { usePolicy } from 'dashboard/composables/usePolicy';
import {
  isPdfDocument,
  formatDocumentLink,
} from 'shared/helpers/documentHelper';

import AiBadge from 'dashboard/components-next/agents-ui/AiBadge.vue';
import AiDropdown from 'dashboard/components-next/agents-ui/AiDropdown.vue';

const props = defineProps({
  id: { type: Number, required: true },
  name: { type: String, default: '' },
  assistant: { type: Object, default: () => ({}) },
  externalLink: { type: String, required: true },
  createdAt: { type: Number, required: true },
  status: { type: String, default: '' },
});

const emit = defineEmits(['action']);
const { checkPermissions } = usePolicy();
const { t } = useI18n();

const menuItems = computed(() => {
  const allOptions = [
    {
      label: t('CAPTAIN.DOCUMENTS.OPTIONS.VIEW_DOCUMENT'),
      value: 'view',
      icon: 'i-lucide-eye',
    },
    {
      label: t('CAPTAIN.DOCUMENTS.OPTIONS.VIEW_RELATED_RESPONSES'),
      value: 'viewRelatedQuestions',
      icon: 'i-lucide-git-branch',
    },
  ];
  if (checkPermissions(['administrator'])) {
    allOptions.push({
      label: t('CAPTAIN.DOCUMENTS.OPTIONS.DELETE_DOCUMENT'),
      value: 'delete',
      icon: 'i-lucide-trash-2',
      danger: true,
    });
  }
  return allOptions;
});

const createdAt = computed(() => dynamicTime(props.createdAt));
const displayLink = computed(() => formatDocumentLink(props.externalLink));
const isPdf = computed(() => isPdfDocument(props.externalLink));
const iconTint = computed(() => (isPdf.value ? '#1faa59' : '#30b0c7'));
const iconClass = computed(() =>
  isPdf.value ? 'i-lucide-file-text' : 'i-lucide-globe'
);

const statusInfo = computed(() => {
  if (props.status === 'available')
    return { variant: 'on', label: t('CAPTAIN.DOCUMENTS.STATUS.TRAINED') };
  if (props.status === 'in_progress')
    return { variant: 'warn', label: t('CAPTAIN.DOCUMENTS.STATUS.PROCESSING') };
  if (props.status === 'failed')
    return { variant: 'err', label: t('CAPTAIN.DOCUMENTS.STATUS.FAILED') };
  return null;
});

const MID = '·';
const onView = () =>
  emit('action', { action: 'view', value: 'view', id: props.id });
const handleAction = value =>
  emit('action', { action: value, value, id: props.id });
</script>

<template>
  <div
    class="flex relative gap-3 items-center p-3.5 rounded-2xl border shadow-sm transition-all border-n-weak bg-n-solid-1 hover:border-n-slate-6"
  >
    <button
      type="button"
      class="grid flex-none place-items-center text-white rounded-[10px] size-10"
      :style="{ background: iconTint }"
      @click="onView"
    >
      <span :class="iconClass" class="size-5" />
    </button>
    <button type="button" class="flex-1 min-w-0 text-left" @click="onView">
      <span class="flex gap-2 items-center">
        <span class="text-[15px] font-semibold truncate text-n-slate-12">{{
          name
        }}</span>
        <AiBadge
          v-if="statusInfo"
          :variant="statusInfo.variant"
          :label="statusInfo.label"
        />
      </span>
      <span
        class="flex gap-1.5 items-center mt-0.5 text-[12.5px] truncate text-n-slate-11"
      >
        <i class="shrink-0 i-woot-captain" />
        <span class="truncate">{{ assistant?.name || '' }}</span>
        <span aria-hidden="true">{{ MID }}</span>
        <span class="truncate">{{ displayLink }}</span>
        <span aria-hidden="true">{{ MID }}</span>
        <span class="shrink-0">{{ createdAt }}</span>
      </span>
    </button>
    <AiDropdown :items="menuItems" @select="handleAction">
      <template #trigger>
        <span class="i-lucide-ellipsis-vertical size-4" />
      </template>
    </AiDropdown>
  </div>
</template>
