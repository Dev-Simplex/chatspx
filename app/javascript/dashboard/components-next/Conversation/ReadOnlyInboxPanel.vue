<script setup>
// CHAT-155: no lugar do editor numa caixa somente leitura -- o aviso fica onde o atendente
// iria escrever, e a unica saida para o cliente e responder pela caixa de destino.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import RedirectReplyDialog from 'dashboard/components-next/Conversation/RedirectReplyDialog.vue';

defineProps({
  inbox: { type: Object, required: true },
});

const emit = defineEmits(['switchToNote']);

const { t } = useI18n();
const redirectDialogRef = ref(null);
</script>

<template>
  <div class="flex flex-col items-center gap-3 px-4 py-5">
    <div class="flex items-center gap-2 text-n-amber-11">
      <Icon icon="i-lucide-eye" class="size-5" />
      <span class="text-sm font-semibold">
        {{ t('CONVERSATION.READ_ONLY_INBOX.BANNER') }}
      </span>
    </div>
    <div class="flex items-center gap-2 mt-1">
      <NextButton
        v-if="inbox.read_only_redirect_inbox_id"
        icon="i-lucide-reply"
        blue
        sm
        :label="
          t('CONVERSATION.READ_ONLY_INBOX.REPLY_THROUGH', {
            inbox: inbox.read_only_redirect_inbox_name,
          })
        "
        class="rounded-full px-4"
        @click="redirectDialogRef.open()"
      />
      <NextButton
        icon="i-lucide-lock"
        slate
        faded
        sm
        :label="t('CONVERSATION.READ_ONLY_INBOX.PRIVATE_NOTE')"
        class="rounded-full px-4"
        @click="emit('switchToNote')"
      />
    </div>
    <RedirectReplyDialog
      v-if="inbox.read_only_redirect_inbox_id"
      ref="redirectDialogRef"
      :inbox="inbox"
    />
  </div>
</template>
