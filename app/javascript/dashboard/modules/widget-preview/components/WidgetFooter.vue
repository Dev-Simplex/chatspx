<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ResizableTextArea from 'shared/components/ResizableTextArea.vue';
import Avatar from 'next/avatar/Avatar.vue';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';
import { PREVIEW_AVATAR_ACCENT } from '../previewAvatarAccent';

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
        <!-- Era `<Avatar name="C">`, com o "C" CRAVADO: o preview mostrava essa
             inicial para todo mundo, com foto ou sem, e nunca correspondeu a
             caixa nenhuma. Agora ele mostra a foto do atendimento de verdade —
             que e o unico jeito de o preview responder "como isso vai aparecer
             no meu site". Sem foto, cai na inicial do nome da caixa.
             `aria-hidden` fica: e ilustracao, e um role="img" sem nome util e
             violacao seria.
             `accent` NAO e' enfeite: sem ele o Avatar sorteia a cor das
             iniciais por `name.length % 6` numa paleta de hex cravados, e com
             "Site da Simplex" o sorteio caia em 3,82:1 — o porque esta em
             `previewAvatarAccent.js`. -->
        <span aria-hidden="true">
          <Avatar
            :src="config.logo"
            :name="config.websiteName || ''"
            :size="34"
            :accent="PREVIEW_AVATAR_ACCENT"
            rounded-full
          />
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
