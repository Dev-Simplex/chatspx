<script setup>
// CASCA (bloco 2.05). Eram 199 linhas com estado proprio, um listener de
// `keypress` no DOCUMENTO e dois botoes mutuamente exclusivos. O estado foi
// para `useComposer`, o campo para o primitivo `WComposer`, os controles para
// `ComposerActions` — e aqui sobra o que casca deve ter: delegacao.
import WComposer from 'widget/ui/WComposer.vue';
import ComposerActions from 'widget/components/ComposerActions.vue';
import { useComposer } from '../composables/useComposer';

const props = defineProps({
  onSendMessage: { type: Function, default: () => {} },
  onSendAttachment: { type: Function, default: () => {} },
});

const composer = useComposer({ onSendMessage: props.onSendMessage });
</script>

<template>
  <WComposer
    v-model="composer.userInput.value"
    :label="$t('CHAT_PLACEHOLDER')"
    :placeholder="$t('CHAT_PLACEHOLDER')"
    @submit="composer.enviar"
    @compositionstart="composer.aoComporInicio"
    @compositionend="composer.aoComporFim"
    @typing-on="composer.aoDigitarInicio"
    @typing-off="composer.aoDigitarFim"
  >
    <template #actions>
      <ComposerActions
        :composer="composer"
        :on-send-attachment="onSendAttachment"
      />
    </template>
  </WComposer>
</template>
