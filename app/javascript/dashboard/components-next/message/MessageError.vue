<script setup>
import { computed } from 'vue';
import Icon from 'next/icon/Icon.vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from './provider.js';
import { hasOneDayPassed } from 'shared/helpers/timeHelper';
import { ORIENTATION, MESSAGE_STATUS } from './constants';

defineProps({
  error: { type: String, required: true },
});

const emit = defineEmits(['retry']);

const { orientation, status, createdAt, content, attachments } =
  useMessageContext();

const { t } = useI18n();

const canRetry = computed(() => {
  const hasContent = content.value !== null;
  const hasAttachments = attachments.value && attachments.value.length > 0;
  return !hasOneDayPassed(createdAt.value) && (hasContent || hasAttachments);
});
</script>

<template>
  <div class="text-xs text-n-ruby-11 flex items-center gap-1.5 relative z-10">
    <span>{{ t('CHAT_LIST.FAILED_TO_SEND') }}</span>
    <div class="relative group">
      <div
        class="bg-n-alpha-2 rounded-md size-5 grid place-content-center cursor-pointer"
      >
        <Icon
          icon="i-lucide-alert-triangle"
          class="text-n-ruby-11 size-[14px]"
        />
      </div>
      <div
        class="absolute bg-n-solid-1 dark:bg-[#233138] px-4 py-3 border rounded-lg border-[var(--wa-list-border)] dark:border-[var(--wa-list-border-dark)] text-n-slate-12 bottom-6 w-52 text-xs shadow-[0_2px_8px_rgba(11,20,26,0.12)] opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all break-all"
        :class="{
          'ltr:left-0 rtl:right-0': orientation === ORIENTATION.LEFT,
          'ltr:right-0 rtl:left-0': orientation === ORIENTATION.RIGHT,
        }"
      >
        {{ error }}
      </div>
    </div>
    <button
      v-if="canRetry"
      type="button"
      :disabled="status !== MESSAGE_STATUS.FAILED"
      class="bg-n-alpha-2 rounded-md size-5 grid place-content-center cursor-pointer hover:bg-n-alpha-3 transition-colors relative z-10 disabled:opacity-50 disabled:cursor-not-allowed"
      @click.stop="emit('retry')"
    >
      <Icon icon="i-lucide-refresh-ccw" class="text-n-ruby-11 size-[14px]" />
    </button>
  </div>
</template>
