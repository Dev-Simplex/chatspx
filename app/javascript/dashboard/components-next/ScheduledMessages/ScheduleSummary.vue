<script setup>
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  contactInfo: {
    type: Object,
    default: null,
  },
  scheduledAtLabel: {
    type: String,
    default: '',
  },
  messageLength: {
    type: Number,
    default: 0,
  },
});

const { t } = useI18n();
</script>

<template>
  <div class="rounded-lg border border-n-weak bg-n-solid-3 px-4 py-3">
    <p
      class="mb-2 text-xs font-semibold uppercase tracking-wide text-n-slate-10"
    >
      {{ t('KANBAN.SCHEDULED_MESSAGES.SUMMARY') }}
    </p>
    <div class="space-y-1.5 text-sm text-n-slate-11">
      <p v-if="contactInfo?.name" class="flex items-center gap-2">
        <Icon icon="i-lucide-user" class="size-4 text-n-slate-10" />
        {{ contactInfo.name }}
      </p>
      <p class="flex items-center gap-2">
        <Icon icon="i-lucide-calendar-clock" class="size-4 text-n-slate-10" />
        {{ scheduledAtLabel || t('KANBAN.SCHEDULED_MESSAGES.DATE_REQUIRED') }}
      </p>
      <p class="flex items-center gap-2">
        <Icon icon="i-lucide-message-square" class="size-4 text-n-slate-10" />
        {{
          t('KANBAN.SCHEDULED_MESSAGES.CHARACTERS_COUNT', {
            count: messageLength,
          })
        }}
      </p>
    </div>
  </div>
</template>
