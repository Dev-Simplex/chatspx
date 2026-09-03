<script setup>
/**
 * Os controles do composer: anexar, emoji e enviar.
 *
 * Componente proprio para que `ChatInputWrap.vue` fique abaixo das 60 linhas
 * que o aceite 7 do bloco 2.05 exige. Ele nao tem estado: recebe o composer
 * pronto e so decide marcacao.
 *
 * Os tres ficam SEMPRE visiveis (aceite 1). Antes, anexar aparecia so com o
 * campo vazio e enviar so com texto — eram mutuamente exclusivos, e o composer
 * vazio nao tinha botao de enviar nenhum.
 */
import { defineAsyncComponent } from 'vue';
import WIconButton from 'widget/ui/WIconButton.vue';
import ChatAttachmentButton from 'widget/components/ChatAttachment.vue';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';
import { useAttachments } from '../composables/useAttachments';

defineProps({
  composer: { type: Object, required: true },
  onSendAttachment: { type: Function, default: () => {} },
});

const EmojiPicker = defineAsyncComponent(
  () => import('shared/components/emoji/EmojiPicker.vue')
);

const { canHandleAttachments, shouldShowEmojiPicker, hasEmojiPickerEnabled } =
  useAttachments();
</script>

<template>
  <ChatAttachmentButton
    v-if="canHandleAttachments"
    data-testid="composer-attach"
    :on-attach="onSendAttachment"
  />
  <WIconButton
    v-if="shouldShowEmojiPicker && hasEmojiPickerEnabled"
    data-testid="composer-emoji"
    :label="$t('EMOJI.ARIA_LABEL')"
    @click="composer.alternarEmoji"
  >
    <FluentIcon icon="emoji" />
  </WIconButton>
  <EmojiPicker
    v-if="shouldShowEmojiPicker && composer.emojiAberto.value"
    v-on-clickaway="composer.alternarEmoji"
    class="!bottom-full end-0 mb-2 max-w-[calc(100vw-3rem)]"
    @select="composer.inserirEmoji"
  />
  <!-- Neutro e desabilitado com o campo vazio (aceite 2) — nunca ausente. -->
  <WIconButton
    data-testid="composer-send"
    :label="$t('A11Y.SEND_MESSAGE')"
    :disabled="!composer.podeEnviar.value"
    :class="composer.podeEnviar.value ? 'bg-w-brand text-w-on-brand' : ''"
    @click="composer.enviar"
  >
    <FluentIcon icon="send" />
  </WIconButton>
</template>
