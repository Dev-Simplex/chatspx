<script setup>
// CHAT-155: a caixa desta conversa e somente leitura; a resposta sai pela caixa de destino.
// Fora da janela de 24h do WhatsApp oficial o backend devolve `requires_template` e o
// modal troca para o seletor de template da caixa de destino (o mesmo do composer).
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import WhatsappTemplatesModal from 'dashboard/components/widgets/conversation/WhatsappTemplates/Modal.vue';

const props = defineProps({
  inbox: { type: Object, required: true },
});

const { t } = useI18n();
const router = useRouter();
const currentChat = useMapGetter('getSelectedChat');
const accountId = useMapGetter('getCurrentAccountId');

const dialogRef = ref(null);
const content = ref('');
const isSending = ref(false);
const showTemplates = ref(false);

const send = async ({ message, templateParams }) => {
  isSending.value = true;
  try {
    const { data } = await ConversationAPI.redirectReply({
      conversationId: currentChat.value.id,
      content: message,
      templateParams,
    });
    dialogRef.value?.close();
    showTemplates.value = false;
    content.value = '';
    router.push(
      `/app/accounts/${accountId.value}/conversations/${data.conversation_id}`
    );
  } catch (error) {
    if (error?.response?.data?.requires_template) {
      dialogRef.value?.close();
      showTemplates.value = true;
      return;
    }
    useAlert(
      error?.response?.data?.error || t('CONVERSATION.READ_ONLY_INBOX.ERROR')
    );
  } finally {
    isSending.value = false;
  }
};

defineExpose({ open: () => dialogRef.value?.open() });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      t('CONVERSATION.READ_ONLY_INBOX.REPLY_THROUGH', {
        inbox: props.inbox.read_only_redirect_inbox_name,
      })
    "
    :description="t('CONVERSATION.READ_ONLY_INBOX.DIALOG_DESCRIPTION')"
    :confirm-button-label="t('CONVERSATION.READ_ONLY_INBOX.SEND')"
    :disable-confirm-button="!content.trim()"
    :is-loading="isSending"
    @confirm="send({ message: content })"
  >
    <TextArea
      v-model="content"
      :max-length="4096"
      :placeholder="t('CONVERSATION.READ_ONLY_INBOX.PLACEHOLDER')"
      auto-height
    />
  </Dialog>
  <WhatsappTemplatesModal
    v-if="showTemplates"
    v-model:show="showTemplates"
    :inbox-id="props.inbox.read_only_redirect_inbox_id"
    @on-send="send"
    @cancel="showTemplates = false"
  />
</template>
