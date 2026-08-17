<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { getInboxIconByType } from 'dashboard/helper/inbox';
import { useRouter, useRoute } from 'vue-router';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper.js';
import { shortTimeAgo } from 'shared/helpers/timeHelper';
import { useMapGetter } from 'dashboard/composables/store';
import { useConversationUrgency } from 'dashboard/composables/useConversationUrgency';
import { useUISettings } from 'dashboard/composables/useUISettings';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import CardMessagePreview from './CardMessagePreview.vue';
import CardMessagePreviewWithMeta from './CardMessagePreviewWithMeta.vue';
import CardPriorityIcon from './CardPriorityIcon.vue';
import { usePinnedConversations } from 'dashboard/composables/usePinnedConversations';

const props = defineProps({
  conversation: {
    type: Object,
    required: true,
  },
  contact: {
    type: Object,
    required: true,
  },
  stateInbox: {
    type: Object,
    required: true,
  },
  accountLabels: {
    type: Array,
    required: true,
  },
});

const router = useRouter();
const route = useRoute();
const store = useStore();
const { uiSettings } = useUISettings();

const densityClass = computed(() => {
  const d = uiSettings.value?.conversation_density || 'comfortable';
  if (d === 'compact') return 'py-1';
  if (d === 'spacious') return 'py-4';
  return 'py-2.5';
});

const cardMessagePreviewWithMetaRef = ref(null);

const currentContact = computed(() => props.contact);

const currentContactName = computed(() => currentContact.value?.name);
const currentContactThumbnail = computed(() => currentContact.value?.thumbnail);
const currentContactStatus = computed(
  () => currentContact.value?.availabilityStatus
);

const inbox = computed(() => props.stateInbox);

const inboxName = computed(() => inbox.value?.name);

const inboxIcon = computed(() => {
  const { channelType, medium } = inbox.value;
  return getInboxIconByType(channelType, medium);
});

const lastActivityAt = computed(() => {
  const timestamp = props.conversation?.timestamp;
  return timestamp ? shortTimeAgo(timestamp) : '';
});

// Pin support — pin_mode by inbox decides whether storage is per-agent or per-inbox.
const { isPinned, togglePin } = usePinnedConversations();
const inboxIdForPin = computed(
  () => props.conversation?.inbox_id || inbox.value?.id
);
const conversationIsPinned = computed(() =>
  isPinned(props.conversation?.id, inboxIdForPin.value)
);
const onTogglePin = e => {
  e.stopPropagation();
  togglePin(props.conversation?.id, inboxIdForPin.value);
};

// Urgência: destaca conversas atribuídas a mim com mensagens não respondidas,
// escalando cor por tempo (5min âmbar / 15min laranja / 30min vermelho).
const currentUser = useMapGetter('getCurrentUser');
const currentUserId = computed(() => currentUser.value?.id);
const conversationRef = computed(() => props.conversation);
const { urgencyClass } = useConversationUrgency(
  conversationRef,
  currentUserId,
  inbox
);

const showMessagePreviewWithoutMeta = computed(() => {
  const { labels = [] } = props.conversation;
  return (
    !cardMessagePreviewWithMetaRef.value?.hasSlaThreshold && labels.length === 0
  );
});

const onCardClick = e => {
  const path = frontendURL(
    conversationUrl({
      accountId: route.params.accountId,
      id: props.conversation.id,
    })
  );

  if (e.metaKey || e.ctrlKey) {
    window.open(
      window.chatwootConfig.hostURL + path,
      '_blank',
      'noopener noreferrer nofollow'
    );
    return;
  }
  router.push({ path });
};

// Swipe gestures (touch only) — mobile UX.
// swipe-left ≥80px: archive (status → resolved)
// swipe-right ≥80px: pin/unpin (mark-unread requires backend that doesn't exist here)
const SWIPE_THRESHOLD = 80;
const swipeOffset = ref(0);
const isSwiping = ref(false);
let swipeStartX = 0;
let swipeMoved = false;

const onTouchStart = e => {
  if (!e.touches?.length) return;
  swipeStartX = e.touches[0].clientX;
  swipeMoved = false;
  isSwiping.value = true;
};

const onTouchMove = e => {
  if (!isSwiping.value || !e.touches?.length) return;
  const delta = e.touches[0].clientX - swipeStartX;
  swipeOffset.value = Math.max(-160, Math.min(160, delta));
  if (Math.abs(delta) > 6) swipeMoved = true;
};

const onTouchEnd = async () => {
  if (!isSwiping.value) return;
  const delta = swipeOffset.value;
  isSwiping.value = false;
  swipeOffset.value = 0;
  if (delta <= -SWIPE_THRESHOLD) {
    await store.dispatch('toggleStatus', {
      conversationId: props.conversation.id,
      status: 'resolved',
    });
  } else if (delta >= SWIPE_THRESHOLD) {
    onTogglePin({ stopPropagation: () => {} });
  }
  // Suppress click-after-swipe so router.push doesn't fire.
  if (swipeMoved) {
    setTimeout(() => {
      swipeMoved = false;
    }, 100);
  }
};

const onCardClickGuard = e => {
  if (swipeMoved) return;
  onCardClick(e);
};

const cardTransformStyle = computed(() =>
  swipeOffset.value === 0
    ? null
    : { transform: `translateX(${swipeOffset.value}px)` }
);
</script>

<template>
  <div
    role="button"
    class="flex w-full gap-[12px] pl-3 pr-3 transition-all duration-150 ease-in-out cursor-pointer wa-conversation-card relative group"
    :class="[
      urgencyClass,
      densityClass,
      { 'wa-conversation-card--pinned': conversationIsPinned },
    ]"
    :style="cardTransformStyle"
    @click="onCardClickGuard"
    @touchstart.passive="onTouchStart"
    @touchmove.passive="onTouchMove"
    @touchend.passive="onTouchEnd"
    @touchcancel.passive="onTouchEnd"
  >
    <button
      type="button"
      :title="
        conversationIsPinned
          ? $t('CONVERSATION.PIN.UNPIN')
          : $t('CONVERSATION.PIN.PIN')
      "
      class="!p-0 !border-0 absolute top-1 right-1 z-10 grid place-content-center size-5 rounded text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-brand transition-opacity"
      :class="
        conversationIsPinned
          ? 'opacity-100 !text-n-brand'
          : 'opacity-0 group-hover:opacity-100'
      "
      @click="onTogglePin"
    >
      <Icon
        :icon="conversationIsPinned ? 'i-lucide-pin' : 'i-lucide-pin-off'"
        class="size-3"
      />
    </button>
    <Avatar
      :name="currentContactName"
      :src="currentContactThumbnail"
      :size="48"
      :status="currentContactStatus"
      rounded-full
    />
    <div class="flex flex-col w-full gap-0.5 min-w-0">
      <div class="flex items-center justify-between h-6 gap-2">
        <h4
          class="text-[14.2px] leading-[19px] font-medium truncate text-n-slate-12"
        >
          {{ currentContactName }}
        </h4>
        <div class="flex items-center gap-2">
          <CardPriorityIcon :priority="conversation.priority || null" />
          <div
            v-tooltip.left="inboxName"
            class="flex items-center justify-center flex-shrink-0 rounded-full bg-n-alpha-2 size-5"
          >
            <Icon
              :icon="inboxIcon"
              class="flex-shrink-0 text-n-slate-11 size-3"
            />
          </div>
          <span class="text-xs text-n-slate-10">
            {{ lastActivityAt }}
          </span>
        </div>
      </div>
      <CardMessagePreview
        v-show="showMessagePreviewWithoutMeta"
        :conversation="conversation"
      />
      <CardMessagePreviewWithMeta
        v-show="!showMessagePreviewWithoutMeta"
        ref="cardMessagePreviewWithMetaRef"
        :conversation="conversation"
        :contact="contact"
        :account-labels="accountLabels"
      />
    </div>
  </div>
</template>
