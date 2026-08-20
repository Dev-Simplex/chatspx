<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ResizableTextArea from 'shared/components/ResizableTextArea.vue';
import Avatar from 'next/avatar/Avatar.vue';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';

const props = defineProps({
  config: {
    type: Object,
    default: () => ({}),
  },
});

const { t } = useI18n();

const isInputFocused = ref(false);

const getStatusText = computed(() => {
  return props.config.isOnline
    ? t('INBOX_MGMT.WIDGET_BUILDER.BODY.TEAM_AVAILABILITY.ONLINE')
    : t('INBOX_MGMT.WIDGET_BUILDER.BODY.TEAM_AVAILABILITY.OFFLINE');
});
</script>

<template>
  <div class="relative flex flex-col w-full px-4">
    <div
      v-if="config.isDefaultScreen"
      class="p-4 rounded-md shadow-sm bg-wp-surface-2"
    >
      <div class="flex items-center justify-between">
        <div>
          <div class="text-sm font-medium leading-4 text-wp-text">
            {{ getStatusText }}
          </div>
          <div class="mt-1 text-xs text-wp-text-muted">
            {{ config.replyTime }}
          </div>
        </div>
        <!-- ilustrativo: quem lê a tela por leitor de tela não ganha nada com
             "avatar C", e um role="img" sem nome é violação séria -->
        <span aria-hidden="true">
          <Avatar name="C" :size="34" rounded-full />
        </span>
      </div>
      <button
        v-if="config.isDefaultScreen"
        class="inline-flex items-center justify-between px-2 py-1 mt-1 -ml-2 font-medium leading-6 bg-transparent rounded-md text-w-brand-readable"
      >
        <span class="pr-2 text-xs">
          {{
            $t(
              'INBOX_MGMT.WIDGET_BUILDER.FOOTER.START_CONVERSATION_BUTTON_TEXT'
            )
          }}
        </span>
        <FluentIcon icon="arrow-right" size="14" />
      </button>
    </div>
    <div
      v-else
      class="flex items-center h-10 rounded-md bg-wp-surface-2"
      :class="{ 'ring-2 ring-w-focus': isInputFocused }"
    >
      <ResizableTextArea
        id="chat-input"
        :rows="1"
        :placeholder="
          $t('INBOX_MGMT.WIDGET_BUILDER.FOOTER.CHAT_INPUT_PLACEHOLDER')
        "
        class="flex-grow !bg-transparent border-0 outline-none !outline-0 border-none h-8 text-sm pb-0 !pt-1.5 resize-none px-3 !mb-0 focus:outline-none rounded-md text-wp-text"
        @focus="isInputFocused = true"
        @blur="isInputFocused = false"
      />
      <div class="flex items-center gap-2 px-2">
        <FluentIcon icon="emoji" />
        <FluentIcon class="icon-send" icon="send" />
      </div>
    </div>
  </div>
</template>
