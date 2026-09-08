<script setup>
import ContentTemplateParser from 'dashboard/components-next/content-templates/ContentTemplateParser.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { useI18n } from 'vue-i18n';

defineProps({
  template: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['sendMessage', 'back']);

const { t } = useI18n();

const handleSendMessage = payload => {
  emit('sendMessage', payload);
};

const handleBack = () => {
  emit('back');
};
</script>

<template>
  <div
    class="absolute bottom-full mb-1.5 ltr:left-0 rtl:right-0 flex flex-col gap-4 px-4 pt-6 pb-0 items-start w-[28.75rem] max-w-[calc(100vw-2rem)] h-auto max-h-[min(30rem,calc(100dvh-7rem))] overflow-y-auto overscroll-contain bg-n-solid-2 border border-n-strong shadow-sm rounded-lg"
  >
    <div class="w-full">
      <ContentTemplateParser
        :template="template"
        @send-message="handleSendMessage"
        @back="handleBack"
      >
        <template #actions="{ sendMessage, goBack, disabled }">
          <div
            class="flex sticky bottom-0 z-10 gap-3 justify-between items-center px-4 pt-3 pb-5 -mx-4 bg-n-solid-2"
          >
            <Button
              :label="t('CONTENT_TEMPLATES.FORM.BACK_BUTTON')"
              color="slate"
              variant="faded"
              class="w-full font-medium"
              @click="goBack"
            />
            <Button
              :label="t('CONTENT_TEMPLATES.FORM.SEND_MESSAGE_BUTTON')"
              class="w-full font-medium"
              :disabled="disabled"
              @click="sendMessage"
            />
          </div>
        </template>
      </ContentTemplateParser>
    </div>
  </div>
</template>
