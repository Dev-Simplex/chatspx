<script setup>
import { computed } from 'vue';
import Icon from 'next/icon/Icon.vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from './provider.js';
import { hasOneDayPassed } from 'shared/helpers/timeHelper';
import { metaErrorReason } from 'dashboard/helper/metaErrorHelper';
import { ORIENTATION, MESSAGE_STATUS } from './constants';

const props = defineProps({
  error: { type: String, required: true },
  // Driven by the parent while a retry POST is in flight: disables the button
  // and swaps the icon for a spinner so the agent can't fire a duplicate retry.
  isRetrying: { type: Boolean, default: false },
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

// Só resolve quando o código da Meta é reconhecido; caso contrário o tooltip
// segue mostrando apenas o texto cru, como antes.
const metaReason = computed(() => metaErrorReason(props.error));
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
        class="absolute bg-n-solid-1 dark:bg-[#233138] px-4 py-3 border rounded-lg border-[var(--wa-list-border)] dark:border-[var(--wa-list-border-dark)] text-n-slate-12 bottom-6 w-64 text-xs shadow-[0_2px_8px_rgba(11,20,26,0.12)] opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all text-start"
        :class="{
          'ltr:left-0 rtl:right-0': orientation === ORIENTATION.LEFT,
          'ltr:right-0 rtl:left-0': orientation === ORIENTATION.RIGHT,
        }"
      >
        <template v-if="metaReason">
          <p class="font-medium">
            {{ t('CHAT_LIST.SEND_ERROR.META_SOURCE') }}
          </p>
          <p class="mt-1 text-n-slate-11">
            {{ t(`CHAT_LIST.SEND_ERROR.${metaReason.reasonKey}`) }}
          </p>
          <p class="mt-1.5 text-n-slate-10">
            {{ t('CHAT_LIST.SEND_ERROR.CODE', { code: metaReason.code }) }}
          </p>
        </template>
        <span v-else class="break-all">{{ error }}</span>
      </div>
    </div>
    <button
      v-if="canRetry"
      type="button"
      :disabled="status !== MESSAGE_STATUS.FAILED || isRetrying"
      class="bg-n-alpha-2 rounded-md size-5 grid place-content-center cursor-pointer hover:bg-n-alpha-3 transition-colors relative z-10 disabled:opacity-50 disabled:cursor-not-allowed"
      @click.stop="emit('retry')"
    >
      <Icon
        icon="i-lucide-refresh-ccw"
        class="text-n-ruby-11 size-[14px] message-retry-icon"
        :class="{ 'message-retry-icon--spinning': isRetrying }"
      />
    </button>
  </div>
</template>

<style scoped lang="scss">
.message-retry-icon {
  transition: transform var(--motion-fast, 160ms) var(--ease-out-expo, ease-out);
}

// While a retry is in flight the icon spins; once resolved it settles back.
.message-retry-icon--spinning {
  animation: message-retry-spin var(--motion-drama, 520ms) linear infinite;
}

@keyframes message-retry-spin {
  to {
    transform: rotate(360deg);
  }
}

@media (prefers-reduced-motion: reduce) {
  .message-retry-icon--spinning {
    animation-duration: 1.2s;
  }
}
</style>
