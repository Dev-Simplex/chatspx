<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { useMapGetter } from 'dashboard/composables/store';
import { useTeamIsolation } from 'dashboard/composables/useTeamIsolation';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import CardLabels from 'dashboard/components-next/Conversation/ConversationCard/CardLabels.vue';
import SLACardLabel from 'dashboard/components-next/Conversation/ConversationCard/SLACardLabel.vue';
import { CONTENT_TYPES } from 'dashboard/components-next/message/constants.js';

const props = defineProps({
  conversation: {
    type: Object,
    required: true,
  },
  accountLabels: {
    type: Array,
    required: true,
  },
});

const { t } = useI18n();

const slaCardLabelRef = ref(null);

const { getPlainText } = useMessageFormatter();
const { isMessageRestricted } = useTeamIsolation();
const inboxById = useMapGetter('inboxes/getInboxById');

const lastNonActivityMessageContent = computed(() => {
  const { lastNonActivityMessage = {}, customAttributes = {} } =
    props.conversation;

  const inbox = inboxById.value(
    props.conversation.inboxId || props.conversation.inbox_id
  );
  if (isMessageRestricted(lastNonActivityMessage, inbox)) return '🔒';
  const { email: { subject } = {} } = customAttributes;
  if (subject) return getPlainText(subject);
  if (lastNonActivityMessage?.content)
    return getPlainText(lastNonActivityMessage.content);

  const contentType =
    lastNonActivityMessage?.contentType ?? lastNonActivityMessage?.content_type;
  const contentAttributes =
    lastNonActivityMessage?.contentAttributes ??
    lastNonActivityMessage?.content_attributes ??
    {};
  const attachments = lastNonActivityMessage?.attachments ?? [];

  if (Array.isArray(attachments) && attachments.length > 0) {
    const fileType = attachments[0]?.file_type;
    if (fileType) {
      return getPlainText(t(`CHAT_LIST.ATTACHMENTS.${fileType}.CONTENT`));
    }
  }

  if (contentAttributes?.isUnsupported || contentAttributes?.is_unsupported) {
    return getPlainText(t('CONVERSATION.UNSUPPORTED_MESSAGE'));
  }

  if (contentType === CONTENT_TYPES.INPUT_NPS) {
    const fallback =
      'De 0 a 10, o quanto voc\u00ea recomendaria nossa empresa?';
    const translated = t('CONVERSATION.NPS_REPLY_MESSAGE', {
      default: fallback,
    });
    return getPlainText(
      translated === 'CONVERSATION.NPS_REPLY_MESSAGE' ? fallback : translated
    );
  }

  if (contentType === CONTENT_TYPES.INPUT_CSAT) {
    return getPlainText(t('CONVERSATION.CSAT_REPLY_MESSAGE'));
  }

  if (contentType === CONTENT_TYPES.VOICE_CALL) {
    const status = contentAttributes?.data?.status?.toString();
    const messageType =
      lastNonActivityMessage?.messageType ??
      lastNonActivityMessage?.message_type;
    const isOutbound = messageType === 1;
    const isFailed = ['no-answer', 'failed'].includes(status);

    if (status === 'in-progress') {
      return getPlainText(t('CONVERSATION.VOICE_CALL.CALL_IN_PROGRESS'));
    }
    if (status === 'completed') {
      return getPlainText(t('CONVERSATION.VOICE_CALL.CALL_ENDED'));
    }
    if (status === 'ringing') {
      return getPlainText(
        t(
          isOutbound
            ? 'CONVERSATION.VOICE_CALL.OUTGOING_CALL'
            : 'CONVERSATION.VOICE_CALL.INCOMING_CALL'
        )
      );
    }
    return getPlainText(
      t(
        isFailed
          ? 'CONVERSATION.VOICE_CALL.MISSED_CALL'
          : 'CONVERSATION.VOICE_CALL.INCOMING_CALL'
      )
    );
  }

  if (
    contentType &&
    (contentType.startsWith('input_') || contentType === CONTENT_TYPES.FORM)
  ) {
    const submittedValues =
      contentAttributes?.submittedValues ||
      contentAttributes?.submitted_values ||
      [];
    const [first = {}] = Array.isArray(submittedValues) ? submittedValues : [];
    const preview = first.title || first.value || first.label;
    return getPlainText(preview || t('CONVERSATION.NO_RESPONSE'));
  }

  return getPlainText(t('CHAT_LIST.NO_CONTENT'));
});

const assignee = computed(() => {
  const { meta: { assignee: agent } = {} } = props.conversation;
  if (!agent) return { name: null, thumbnail: null, status: null };
  return {
    name: agent.name ?? agent.availableName ?? agent.available_name,
    thumbnail: agent.thumbnail,
    status: agent.availabilityStatus ?? agent.availability_status,
  };
});

const unreadMessagesCount = computed(() => {
  const { unreadCount } = props.conversation;
  return unreadCount;
});

const hasSlaThreshold = computed(() => {
  return (
    slaCardLabelRef.value?.hasSlaThreshold && props.conversation?.slaPolicyId
  );
});

defineExpose({
  hasSlaThreshold,
});
</script>

<template>
  <div class="flex flex-col w-full gap-0.5">
    <!-- Line 2: Message preview + Unread badge -->
    <div class="flex items-center justify-between w-full gap-2">
      <p class="mb-0 text-sm text-n-slate-11 truncate leading-5">
        {{ lastNonActivityMessageContent }}
      </p>
      <div
        v-if="unreadMessagesCount > 0"
        class="inline-flex items-center justify-center flex-shrink-0 rounded-full min-w-[20px] h-5 px-1.5 bg-n-brand"
      >
        <span class="text-xs font-medium text-white">
          {{ unreadMessagesCount }}
        </span>
      </div>
    </div>

    <!-- Line 3: Metadata - SLA + Labels + Assignee -->
    <div class="flex items-center gap-1.5 mt-0.5">
      <SLACardLabel
        v-show="hasSlaThreshold"
        ref="slaCardLabelRef"
        :conversation="conversation"
      />
      <div v-if="hasSlaThreshold" class="w-px h-3 bg-n-slate-4" />
      <div class="flex-1 min-w-0 overflow-hidden">
        <CardLabels
          :conversation-labels="conversation.labels"
          :account-labels="accountLabels"
        />
      </div>
      <Avatar
        v-if="assignee.name"
        :name="assignee.name"
        :src="assignee.thumbnail"
        :size="20"
        :status="assignee.status"
        rounded-full
        class="flex-shrink-0"
      />
    </div>
  </div>
</template>
