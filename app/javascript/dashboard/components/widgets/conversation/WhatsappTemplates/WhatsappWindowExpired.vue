<script setup>
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const emit = defineEmits(['sendTemplate', 'switchToNote']);

const { t } = useI18n();

const onOpenAllTemplates = () => {
  emit('sendTemplate', null);
};

const onSwitchToNote = () => {
  emit('switchToNote');
};
</script>

<template>
  <div class="flex flex-col items-center gap-3 px-4 py-5">
    <!-- Header -->
    <div class="flex items-center gap-2 text-n-amber-11">
      <Icon icon="i-lucide-clock-alert" class="size-5" />
      <span class="text-sm font-semibold">
        {{ t('CONVERSATION.WHATSAPP_WINDOW_EXPIRED.TITLE') }}
      </span>
    </div>

    <p class="text-xs text-center text-n-slate-11 max-w-md">
      {{ t('CONVERSATION.WHATSAPP_WINDOW_EXPIRED.DESCRIPTION') }}
    </p>

    <!-- Action Buttons -->
    <div class="flex items-center gap-2 mt-1">
      <NextButton
        icon="i-ph-whatsapp-logo"
        blue
        sm
        :label="t('CONVERSATION.WHATSAPP_WINDOW_EXPIRED.SEND_TEMPLATE')"
        class="rounded-full px-4"
        @click="onOpenAllTemplates"
      />
      <NextButton
        icon="i-lucide-lock"
        slate
        faded
        sm
        :label="t('CONVERSATION.WHATSAPP_WINDOW_EXPIRED.PRIVATE_NOTE')"
        class="rounded-full px-4"
        @click="onSwitchToNote"
      />
    </div>
  </div>
</template>
