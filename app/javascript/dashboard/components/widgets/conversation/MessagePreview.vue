<script>
import { MESSAGE_TYPE } from 'widget/helpers/constants';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { ATTACHMENT_ICONS } from 'shared/constants/messages';

export default {
  name: 'MessagePreview',
  props: {
    message: {
      type: Object,
      required: true,
    },
    showMessageType: {
      type: Boolean,
      default: true,
    },
    defaultEmptyMessage: {
      type: String,
      default: '',
    },
  },
  setup() {
    const { getPlainText } = useMessageFormatter();
    return {
      getPlainText,
    };
  },
  computed: {
    messageByAgent() {
      const { message_type: messageType } = this.message;
      return messageType === MESSAGE_TYPE.OUTGOING;
    },
    isMessageAnActivity() {
      const { message_type: messageType } = this.message;
      return messageType === MESSAGE_TYPE.ACTIVITY;
    },
    isMessagePrivate() {
      const { private: isPrivate } = this.message;
      return isPrivate;
    },
    parsedLastMessage() {
      const { content_attributes: contentAttributes } = this.message;
      const { email: { subject } = {} } = contentAttributes || {};
      return this.getPlainText(subject || this.message.content);
    },
    contentType() {
      return this.message?.content_type || this.message?.contentType;
    },
    contentAttributes() {
      return (
        this.message?.content_attributes ||
        this.message?.contentAttributes ||
        {}
      );
    },
    hasAttachments() {
      return (
        Array.isArray(this.message?.attachments) &&
        this.message.attachments.length > 0
      );
    },
    isNpsMessage() {
      return this.contentType === 'input_nps';
    },
    isCsatMessage() {
      return this.contentType === 'input_csat';
    },
    isVoiceCallMessage() {
      return this.contentType === 'voice_call';
    },
    isUnsupportedMessage() {
      return (
        this.contentAttributes?.isUnsupported ||
        this.contentAttributes?.is_unsupported
      );
    },
    voiceCallStatus() {
      return this.contentAttributes?.data?.status?.toString();
    },
    voiceCallLabel() {
      if (!this.isVoiceCallMessage) return '';
      const status = this.voiceCallStatus;
      const isOutbound = this.messageByAgent;
      const isFailed = ['no-answer', 'failed'].includes(status);

      if (status === 'in-progress') {
        return this.$t('CONVERSATION.VOICE_CALL.CALL_IN_PROGRESS');
      }
      if (status === 'completed') {
        return this.$t('CONVERSATION.VOICE_CALL.CALL_ENDED');
      }
      if (status === 'ringing') {
        return this.$t(
          isOutbound
            ? 'CONVERSATION.VOICE_CALL.OUTGOING_CALL'
            : 'CONVERSATION.VOICE_CALL.INCOMING_CALL'
        );
      }
      return this.$t(
        isFailed
          ? 'CONVERSATION.VOICE_CALL.MISSED_CALL'
          : 'CONVERSATION.VOICE_CALL.INCOMING_CALL'
      );
    },
    submittedValuesPreview() {
      const submittedValues =
        this.contentAttributes?.submittedValues ||
        this.contentAttributes?.submitted_values ||
        [];
      if (!Array.isArray(submittedValues) || submittedValues.length === 0) {
        return '';
      }
      const [first = {}] = submittedValues;
      const preview = first.title || first.value || first.label || '';
      return preview ? this.getPlainText(preview) : '';
    },
    npsFallbackMessage() {
      if (!this.isNpsMessage || this.message?.content) return '';
      const fallback =
        'De 0 a 10, o quanto voc\u00ea recomendaria nossa empresa?';
      const translated = this.$t('CONVERSATION.NPS_REPLY_MESSAGE', {
        default: fallback,
      });
      return translated === 'CONVERSATION.NPS_REPLY_MESSAGE'
        ? fallback
        : translated;
    },
    inputFallbackMessage() {
      if (!this.contentType) return '';
      if (
        this.contentType.startsWith('input_') ||
        this.contentType === 'form'
      ) {
        return (
          this.submittedValuesPreview || this.$t('CONVERSATION.NO_RESPONSE')
        );
      }
      return '';
    },
    fallbackMessage() {
      if (this.message?.content || this.hasAttachments) return '';
      if (this.isUnsupportedMessage)
        return this.$t('CONVERSATION.UNSUPPORTED_MESSAGE');
      if (this.npsFallbackMessage) return this.npsFallbackMessage;
      if (this.isCsatMessage) return this.$t('CONVERSATION.CSAT_REPLY_MESSAGE');
      if (this.isVoiceCallMessage) return this.voiceCallLabel;
      if (this.inputFallbackMessage) return this.inputFallbackMessage;
      return '';
    },
    lastMessageFileType() {
      const attachments = this.message?.attachments || [];
      const [{ file_type: fileType } = {}] = attachments;
      return fileType;
    },
    attachmentIcon() {
      return ATTACHMENT_ICONS[this.lastMessageFileType];
    },
    attachmentMessageContent() {
      return `CHAT_LIST.ATTACHMENTS.${this.lastMessageFileType}.CONTENT`;
    },
    isMessageSticker() {
      return this.message && this.message.content_type === 'sticker';
    },
  },
};
</script>

<template>
  <div class="overflow-hidden text-ellipsis whitespace-nowrap">
    <template v-if="showMessageType">
      <fluent-icon
        v-if="isMessagePrivate"
        size="16"
        class="-mt-0.5 align-middle text-n-slate-11 inline-block"
        icon="lock-closed"
      />
      <fluent-icon
        v-else-if="messageByAgent"
        size="16"
        class="-mt-0.5 align-middle text-n-slate-11 inline-block"
        icon="arrow-reply"
      />
      <fluent-icon
        v-else-if="isMessageAnActivity"
        size="16"
        class="-mt-0.5 align-middle text-n-slate-11 inline-block"
        icon="info"
      />
    </template>
    <span v-if="message.content && isMessageSticker">
      <fluent-icon
        size="16"
        class="-mt-0.5 align-middle inline-block text-n-slate-11"
        icon="image"
      />
      {{ $t('CHAT_LIST.ATTACHMENTS.image.CONTENT') }}
    </span>
    <span v-else-if="message.content">
      {{ parsedLastMessage }}
    </span>
    <span v-else-if="hasAttachments">
      <fluent-icon
        v-if="attachmentIcon && showMessageType"
        size="16"
        class="-mt-0.5 align-middle inline-block text-n-slate-11"
        :icon="attachmentIcon"
      />
      {{ $t(`${attachmentMessageContent}`) }}
    </span>
    <span v-else-if="fallbackMessage">
      {{ fallbackMessage }}
    </span>
    <span v-else>
      {{ defaultEmptyMessage || $t('CHAT_LIST.NO_CONTENT') }}
    </span>
  </div>
</template>
