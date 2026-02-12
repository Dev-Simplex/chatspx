<script setup>
import { computed, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useElementSize } from '@vueuse/core';
import BackButton from '../BackButton.vue';
import InboxName from '../InboxName.vue';
import MoreActions from './MoreActions.vue';
import Thumbnail from '../Thumbnail.vue';
import SLACardLabel from './components/SLACardLabel.vue';
import ConversationMessageSearch from './ConversationMessageSearch.vue';
import ButtonV4 from 'dashboard/components-next/button/Button.vue';
import wootConstants from 'dashboard/constants/globals';
import { conversationListPageURL } from 'dashboard/helper/URLHelper';
import { snoozedReopenTime } from 'dashboard/helper/snoozeHelpers';
import { getTypingUsersText } from 'dashboard/helper/commons';
import { useInbox } from 'dashboard/composables/useInbox';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  chat: {
    type: Object,
    default: () => ({}),
  },
  showBackButton: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const conversationHeader = ref(null);
const { width } = useElementSize(conversationHeader);
const { isAWebWidgetInbox } = useInbox();
const showMessageSearch = ref(false);

const currentChat = computed(() => store.getters.getSelectedChat);
const accountId = computed(() => store.getters.getCurrentAccountId);

const chatMetadata = computed(() => props.chat.meta);

const backButtonUrl = computed(() => {
  const {
    params: { inbox_id: inboxId, label, teamId, id: customViewId },
    name,
  } = route;

  const conversationTypeMap = {
    conversation_through_mentions: 'mention',
    conversation_through_unattended: 'unattended',
  };
  return conversationListPageURL({
    accountId: accountId.value,
    inboxId,
    label,
    teamId,
    conversationType: conversationTypeMap[name],
    customViewId,
  });
});

const isHMACVerified = computed(() => {
  if (!isAWebWidgetInbox.value) {
    return true;
  }
  return chatMetadata.value.hmac_verified;
});

const currentContact = computed(() =>
  store.getters['contacts/getContact'](props.chat.meta.sender.id)
);

const typingUsersList = computed(() => {
  if (!currentChat.value?.id) return [];
  return store.getters['conversationTypingStatus/getUserList'](
    currentChat.value.id
  );
});

const isAnyoneTyping = computed(
  () => typingUsersList.value && typingUsersList.value.length > 0
);

const typingSubtitleText = computed(() => {
  if (!isAnyoneTyping.value) return '';
  const [i18nKey, params] = getTypingUsersText(typingUsersList.value);
  return t(i18nKey, params);
});

const headerSubtitleText = computed(() => {
  if (isSnoozed.value) return null;
  if (isAnyoneTyping.value) return typingSubtitleText.value;
  if (currentContact.value?.availability_status === 'online') {
    return t('CONVERSATION.HEADER.ONLINE');
  }
  return null;
});

const isSnoozed = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.SNOOZED
);

const snoozedDisplayText = computed(() => {
  const { snoozed_until: snoozedUntil } = currentChat.value;
  if (snoozedUntil) {
    return `${t('CONVERSATION.HEADER.SNOOZED_UNTIL')} ${snoozedReopenTime(snoozedUntil)}`;
  }
  return t('CONVERSATION.HEADER.SNOOZED_UNTIL_NEXT_REPLY');
});

const inbox = computed(() => {
  const { inbox_id: inboxId } = props.chat;
  return store.getters['inboxes/getInbox'](inboxId);
});

const hasMultipleInboxes = computed(
  () => store.getters['inboxes/getInboxes'].length > 1
);

const hasSlaPolicyId = computed(() => props.chat?.sla_policy_id);
</script>

<template>
  <div
    ref="conversationHeader"
    class="flex flex-col gap-2 items-center justify-between flex-1 w-full min-w-0 xl:flex-row px-3 py-1.5 border-b bg-n-background border-n-weak h-14 xl:h-10 min-h-[2.5rem]"
  >
    <div
      class="flex items-center justify-start w-full xl:w-auto max-w-full min-w-0 xl:flex-1"
    >
      <BackButton
        v-if="showBackButton"
        :back-url="backButtonUrl"
        class="ltr:mr-2 rtl:ml-2"
      />
      <Thumbnail
        :src="currentContact.thumbnail"
        :username="currentContact.name"
        :status="currentContact.availability_status"
        size="32px"
        class="flex-shrink-0"
        allow-preview
      />
      <div
        class="flex flex-col items-start min-w-0 ml-2 overflow-hidden rtl:ml-0 rtl:mr-2"
      >
        <div class="flex flex-row items-center max-w-full gap-1 p-0 m-0">
          <span
            class="text-sm font-medium truncate leading-tight text-n-slate-12"
          >
            {{ currentContact.name }}
          </span>
          <fluent-icon
            v-if="!isHMACVerified"
            v-tooltip="$t('CONVERSATION.UNVERIFIED_SESSION')"
            size="14"
            class="text-n-amber-10 my-0 mx-0 min-w-[14px] flex-shrink-0"
            icon="warning"
          />
        </div>

        <div
          class="flex items-center gap-2 overflow-hidden text-xs conversation--header--actions text-ellipsis whitespace-nowrap text-n-slate-11"
        >
          <template v-if="headerSubtitleText">
            <span
              v-if="isAnyoneTyping"
              class="inline-flex items-center font-normal typing-ellipsis"
            >
              {{ typingSubtitleText }}
              <span class="typing-dots" aria-hidden="true">
                <span>.</span><span>.</span><span>.</span>
              </span>
            </span>
            <span v-else class="font-normal text-n-teal-10">
              {{ headerSubtitleText }}
            </span>
          </template>
          <template v-else>
            <span v-if="isSnoozed" class="font-medium text-n-amber-10">
              {{ snoozedDisplayText }}
            </span>
            <InboxName
              v-else-if="hasMultipleInboxes"
              :inbox="inbox"
              class="!mx-0"
            />
          </template>
        </div>
      </div>
    </div>
    <div
      class="flex flex-row items-center justify-start xl:justify-end flex-shrink-0 gap-2 w-full xl:w-auto header-actions-wrap"
    >
      <SLACardLabel
        v-if="hasSlaPolicyId"
        :chat="chat"
        show-extended-info
        :parent-width="width"
        class="hidden md:flex"
      />
      <ButtonV4
        v-tooltip="$t('SEARCH.SEARCH_IN_CONVERSATION')"
        size="sm"
        variant="ghost"
        color="slate"
        icon="i-lucide-search"
        class="rounded-md hover:bg-n-alpha-2"
        @click="showMessageSearch = true"
      />
      <MoreActions :conversation-id="currentChat.id" />
    </div>
    <ConversationMessageSearch
      v-if="currentChat.id"
      :conversation-id="currentChat.id"
      :show="showMessageSearch"
      @close="showMessageSearch = false"
    />
  </div>
</template>

<style scoped lang="scss">
.typing-dots {
  display: inline-flex;
  margin-left: 1px;

  span {
    animation: typing-dot 1.4s ease-in-out infinite;
    opacity: 0;

    &:nth-child(1) {
      animation-delay: 0s;
    }
    &:nth-child(2) {
      animation-delay: 0.2s;
    }
    &:nth-child(3) {
      animation-delay: 0.4s;
    }
  }
}

@keyframes typing-dot {
  0%,
  60%,
  100% {
    opacity: 0;
  }
  30% {
    opacity: 1;
  }
}
</style>
