<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { snoozedReopenTime } from 'dashboard/helper/snoozeHelpers';
import wootConstants from 'dashboard/constants/globals';

const props = defineProps({
  chat: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const STATUS = wootConstants.STATUS_TYPE;

const status = computed(() => props.chat?.status || STATUS.OPEN);
const assignee = computed(() => props.chat?.meta?.assignee || null);

const badge = computed(() => {
  if (status.value === STATUS.PENDING) {
    return {
      label: t('CONVERSATION.HEADER.STATUS_BADGE.PENDING'),
      icon: 'i-lucide-clock',
      pillClass: 'wa-status-pill--pending',
    };
  }

  if (status.value === STATUS.SNOOZED) {
    const snoozedUntil = props.chat?.snoozed_until;
    return {
      label: snoozedUntil
        ? t('CONVERSATION.HEADER.STATUS_BADGE.SNOOZED_UNTIL', {
            time: snoozedReopenTime(snoozedUntil),
          })
        : t('CONVERSATION.HEADER.STATUS_BADGE.SNOOZED_NEXT_REPLY'),
      icon: 'i-lucide-bell-off',
      pillClass: 'wa-status-pill--snoozed',
    };
  }

  if (status.value === STATUS.RESOLVED) {
    return {
      label: t('CONVERSATION.HEADER.STATUS_BADGE.RESOLVED'),
      icon: 'i-lucide-check-circle-2',
      pillClass: 'wa-status-pill--resolved',
    };
  }

  // OPEN — split por assignee
  if (assignee.value) {
    return {
      label: t('CONVERSATION.HEADER.STATUS_BADGE.OPEN_ASSIGNED'),
      icon: 'i-lucide-user-check',
      pillClass: 'wa-status-pill--open-assigned',
    };
  }

  return {
    label: t('CONVERSATION.HEADER.STATUS_BADGE.OPEN_UNASSIGNED'),
    icon: 'i-lucide-user-x',
    pillClass: 'wa-status-pill--open-unassigned',
  };
});
</script>

<template>
  <div
    class="inline-flex items-center gap-1.5 wa-status-pill conversation--meta-pill wa-status-pill--readonly"
    :class="badge.pillClass"
    :title="badge.label"
  >
    <span :class="badge.icon" class="size-3" />
    <span class="truncate max-w-[160px]">{{ badge.label }}</span>
  </div>
</template>
