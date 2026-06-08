<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  headerFormat: { type: String, default: 'NONE' },
  headerText: { type: String, default: '' },
  body: { type: String, default: '' },
  footer: { type: String, default: '' },
  buttons: { type: Array, default: () => [] },
});

const { t } = useI18n();

const mediaMeta = computed(() => {
  const map = {
    IMAGE: { icon: 'i-lucide-image', label: t('WHATSAPP_TEMPLATES_MGMT.PREVIEW.IMAGE') },
    VIDEO: { icon: 'i-lucide-video', label: t('WHATSAPP_TEMPLATES_MGMT.PREVIEW.VIDEO') },
    DOCUMENT: { icon: 'i-lucide-file-text', label: t('WHATSAPP_TEMPLATES_MGMT.PREVIEW.DOCUMENT') },
  };
  return map[props.headerFormat] || null;
});

const buttonIcon = type => {
  const map = {
    URL: 'i-lucide-external-link',
    PHONE_NUMBER: 'i-lucide-phone',
    COPY_CODE: 'i-lucide-copy',
    QUICK_REPLY: 'i-lucide-reply',
  };
  return map[type] || 'i-lucide-reply';
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <span class="text-sm font-medium text-n-slate-12">
      {{ t('WHATSAPP_TEMPLATES_MGMT.PREVIEW.TITLE') }}
    </span>
    <div class="p-3 rounded-xl bg-n-solid-2 border border-n-weak">
      <div class="max-w-xs ml-auto p-2.5 rounded-lg rounded-tr-none bg-n-brand/10 shadow-sm flex flex-col gap-1.5">
        <!-- Header -->
        <div
          v-if="headerFormat === 'TEXT' && headerText"
          class="text-sm font-semibold text-n-slate-12 whitespace-pre-line break-words"
        >
          {{ headerText }}
        </div>
        <div
          v-else-if="mediaMeta"
          class="flex items-center gap-2 h-20 justify-center rounded-md bg-n-alpha-2 text-n-slate-11"
        >
          <Icon :icon="mediaMeta.icon" class="size-5" />
          <span class="text-xs">{{ mediaMeta.label }}</span>
        </div>

        <!-- Body -->
        <div class="text-sm text-n-slate-12 whitespace-pre-line break-words">
          {{ body || t('WHATSAPP_TEMPLATES_MGMT.PREVIEW.BODY_PLACEHOLDER') }}
        </div>

        <!-- Footer -->
        <div v-if="footer" class="text-xs text-n-slate-10 whitespace-pre-line break-words">
          {{ footer }}
        </div>
      </div>

      <!-- Buttons -->
      <div v-if="buttons.length" class="max-w-xs ml-auto mt-1 flex flex-col gap-1">
        <div
          v-for="(btn, idx) in buttons"
          :key="idx"
          class="flex items-center justify-center gap-1.5 py-1.5 rounded-lg bg-n-solid-1 border border-n-weak text-sm text-n-blue-11"
        >
          <Icon :icon="buttonIcon(btn.type)" class="size-3.5" />
          <span class="truncate">{{ btn.text || '—' }}</span>
        </div>
      </div>
    </div>
  </div>
</template>
