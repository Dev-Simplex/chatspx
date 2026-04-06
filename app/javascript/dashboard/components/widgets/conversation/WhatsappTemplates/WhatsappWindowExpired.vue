<script setup>
import { computed, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFunctionGetter } from 'dashboard/composables/store';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import {
  COMPONENT_TYPES,
  findComponentByType,
} from 'dashboard/helper/templateHelper';

const props = defineProps({
  inboxId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['sendTemplate', 'switchToNote']);

const { t } = useI18n();

const whatsAppTemplates = useFunctionGetter(
  'inboxes/getFilteredWhatsAppTemplates',
  toRef(props, 'inboxId')
);

const hasTemplates = computed(() => whatsAppTemplates.value?.length > 0);

const recentTemplates = computed(() => {
  if (!whatsAppTemplates.value) return [];
  return whatsAppTemplates.value.slice(0, 5);
});

const getTemplateBody = template => {
  return findComponentByType(template, COMPONENT_TYPES.BODY)?.text || '';
};

const truncateBody = text => {
  if (!text) return '';
  return text.length > 80 ? `${text.substring(0, 80)}...` : text;
};

const onSelectTemplate = template => {
  emit('sendTemplate', template);
};

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

    <!-- Quick Templates -->
    <div v-if="hasTemplates" class="w-full max-w-lg">
      <p class="mb-2 text-xs font-medium text-n-slate-10">
        {{ t('CONVERSATION.WHATSAPP_WINDOW_EXPIRED.QUICK_TEMPLATES') }}
      </p>
      <div class="flex flex-col gap-1">
        <button
          v-for="template in recentTemplates"
          :key="template.id"
          class="flex items-center gap-2 px-3 py-2 text-left rounded-lg transition-colors bg-n-alpha-black2 hover:bg-n-alpha-2 dark:hover:bg-n-solid-2 group"
          @click="onSelectTemplate(template)"
        >
          <Icon
            icon="i-ph-whatsapp-logo"
            class="size-4 text-n-slate-10 group-hover:text-green-600 shrink-0"
          />
          <div class="flex-1 min-w-0">
            <span class="text-sm font-medium text-n-slate-12 truncate block">
              {{ template.name }}
            </span>
            <span class="text-xs text-n-slate-10 truncate block">
              {{ truncateBody(getTemplateBody(template)) }}
            </span>
          </div>
          <Icon
            icon="i-lucide-send"
            class="size-3.5 text-n-slate-9 opacity-0 group-hover:opacity-100 transition-opacity shrink-0"
          />
        </button>
      </div>
    </div>

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
