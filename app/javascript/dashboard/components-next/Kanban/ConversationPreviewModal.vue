<script setup>
import { ref, computed, watch, nextTick } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { format, isToday } from 'date-fns';
import { enUS, ptBR } from 'date-fns/locale';

import MessageApi from 'dashboard/api/inbox/message';
import { useMapGetter } from 'dashboard/composables/store';
import { useTeamIsolation } from 'dashboard/composables/useTeamIsolation';
import { useAgentIsolation } from 'dashboard/composables/useAgentIsolation';
import { MESSAGE_TYPE } from 'shared/constants/messages';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import MessageBubbleSkeleton from 'dashboard/components-next/skeleton/MessageBubbleSkeleton.vue';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  conversation: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['close']);

const router = useRouter();
const { t, locale } = useI18n();

const getContactById = useMapGetter('contacts/getContactById');
const inboxById = useMapGetter('inboxes/getInboxById');
const { isMessageRestricted } = useTeamIsolation();
const { isMessageRestricted: isAgentMessageRestricted } = useAgentIsolation();

const dialogRef = ref(null);
const scrollRef = ref(null);
const messages = ref([]);
const isLoading = ref(false);
const hasError = ref(false);
// Token of the in-flight request — lets us discard stale responses when the
// user jumps from one card to another before the fetch resolves.
let activeRequestId = null;

const dateLocale = computed(() =>
  String(locale.value || '').startsWith('pt') ? ptBR : enUS
);

// ── Conversation / contact / inbox derivation (mirrors KanbanCard) ──────
const displayId = computed(
  () =>
    props.conversation?.displayId ||
    props.conversation?.display_id ||
    props.conversation?.id ||
    null
);

const contactId = computed(
  () =>
    props.conversation?.contactId ||
    props.conversation?.contact_id ||
    props.conversation?.contact?.id ||
    props.conversation?.meta?.sender?.id ||
    props.conversation?.sender?.id ||
    null
);

const contactFromConversation = computed(
  () =>
    props.conversation?.contact ||
    props.conversation?.meta?.sender ||
    props.conversation?.sender ||
    null
);

const contactFromStore = computed(() => {
  if (!contactId.value) return null;
  const getter = getContactById.value;
  if (typeof getter !== 'function') return null;
  return getter(contactId.value);
});

const contact = computed(
  () => contactFromConversation.value || contactFromStore.value || null
);

const contactName = computed(
  () => contact.value?.name || t('KANBAN.ITEMS.UNNAMED_CONTACT')
);

const contactThumbnail = computed(
  () =>
    contact.value?.thumbnail ||
    contact.value?.avatar_url ||
    contact.value?.avatar ||
    contact.value?.profile_image_url ||
    ''
);

const inbox = computed(() => {
  const getter = inboxById.value;
  if (typeof getter !== 'function') return null;
  return getter(props.conversation?.inboxId || props.conversation?.inbox_id);
});

const inboxName = computed(() => inbox.value?.name || '');

// ── Message processing ──────────────────────────────────────────────────
const messageTimestamp = message => {
  const raw = message?.created_at ?? message?.createdAt ?? null;
  if (!raw) return null;
  const value = typeof raw === 'number' ? raw * 1000 : raw;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
};

const formatTime = message => {
  const date = messageTimestamp(message);
  if (!date) return '';
  const pattern = isToday(date) ? 'HH:mm' : 'dd MMM HH:mm';
  return format(date, pattern, { locale: dateLocale.value });
};

const isOutgoing = message => {
  const type = message?.message_type ?? message?.messageType;
  return type === MESSAGE_TYPE.OUTGOING;
};

const messageContent = message =>
  message?.content || message?.processed_message_content || '';

const messageAttachments = message =>
  Array.isArray(message?.attachments) ? message.attachments : [];

const hasAttachments = message => messageAttachments(message).length > 0;

// Placeholder for an attachment-only message (no text content). Held in a
// constant so the i18n bare-string lint doesn't flag the emoji literal.
const ATTACHMENT_GLYPH = '📎';

const scrollToBottom = () => {
  nextTick(() => {
    const el = scrollRef.value;
    if (el) el.scrollTop = el.scrollHeight;
  });
};

const fetchMessages = async () => {
  if (!displayId.value) return;

  const requestId = displayId.value;
  activeRequestId = requestId;

  isLoading.value = true;
  hasError.value = false;
  messages.value = [];

  try {
    const { data } = await MessageApi.getPreviousMessages({
      conversationId: requestId,
      limit: 20,
      includeMeta: false,
    });

    // Discard if the user switched cards while this request was in flight.
    if (activeRequestId !== requestId) return;

    const payload = data?.payload || data || [];
    const list = Array.isArray(payload) ? payload : [];

    messages.value = list
      .filter(message => {
        const type = message?.message_type ?? message?.messageType;
        if (type === MESSAGE_TYPE.ACTIVITY) return false;
        if (message?.private === true) return false;
        if (isMessageRestricted(message, inbox.value)) return false;
        if (isAgentMessageRestricted(message, inbox.value)) return false;
        return true;
      })
      .sort((a, b) => {
        const aTime = messageTimestamp(a)?.getTime() ?? 0;
        const bTime = messageTimestamp(b)?.getTime() ?? 0;
        return aTime - bTime;
      });

    scrollToBottom();
  } catch (error) {
    if (activeRequestId !== requestId) return;
    hasError.value = true;
  } finally {
    if (activeRequestId === requestId) {
      isLoading.value = false;
    }
  }
};

const resetState = () => {
  activeRequestId = null;
  messages.value = [];
  isLoading.value = false;
  hasError.value = false;
};

const close = () => {
  emit('close');
};

const openConversation = () => {
  if (displayId.value) {
    router.push({
      name: 'inbox_conversation',
      params: { conversation_id: displayId.value },
    });
  }
  emit('close');
};

watch(
  () => props.show,
  newShow => {
    if (newShow && props.conversation) {
      nextTick(() => {
        dialogRef.value?.open();
        fetchMessages();
      });
    } else {
      resetState();
    }
  }
);
</script>

<template>
  <Dialog
    v-if="show"
    ref="dialogRef"
    width="xl"
    position="center"
    :title="t('KANBAN.PREVIEW.TITLE')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="close"
  >
    <!-- Header: contact + inbox -->
    <div class="flex items-center gap-3">
      <Avatar
        :name="contactName"
        :src="contactThumbnail"
        :size="40"
        rounded-full
      />
      <div class="min-w-0 flex-1">
        <h4
          class="truncate text-sm font-semibold leading-tight text-n-slate-12"
        >
          {{ contactName }}
        </h4>
        <p
          v-if="inboxName"
          class="mt-0.5 truncate text-xs leading-none text-n-slate-10"
        >
          {{ inboxName }}
        </p>
      </div>
    </div>

    <!-- Body -->
    <div
      ref="scrollRef"
      class="kanban-preview__body flex flex-col gap-2 overflow-y-auto rounded-lg bg-n-alpha-1 p-3"
    >
      <MessageBubbleSkeleton v-if="isLoading" :count="4" />

      <div
        v-else-if="hasError"
        class="flex flex-col items-center justify-center gap-2 py-10 text-center"
      >
        <Icon icon="i-lucide-triangle-alert" class="size-5 text-n-ruby-11" />
        <p class="m-0 text-sm text-n-slate-11">
          {{ t('KANBAN.PREVIEW.ERROR') }}
        </p>
      </div>

      <div
        v-else-if="!messages.length"
        class="flex flex-col items-center justify-center gap-2 py-10 text-center"
      >
        <Icon
          icon="i-lucide-message-circle-dashed"
          class="size-5 text-n-slate-10"
        />
        <p class="m-0 text-sm text-n-slate-10">
          {{ t('KANBAN.PREVIEW.EMPTY') }}
        </p>
      </div>

      <template v-else>
        <div
          v-for="message in messages"
          :key="message.id"
          class="flex"
          :class="isOutgoing(message) ? 'justify-end' : 'justify-start'"
        >
          <div
            class="flex max-w-[75%] flex-col gap-1 rounded-lg px-3 py-2"
            :class="
              isOutgoing(message)
                ? 'bg-n-teal-3 rounded-br-sm'
                : 'bg-n-alpha-2 rounded-bl-sm'
            "
          >
            <p
              v-if="messageContent(message)"
              class="m-0 whitespace-pre-line break-words text-[13px] leading-snug text-n-slate-12"
            >
              {{ messageContent(message) }}
            </p>
            <p
              v-else-if="hasAttachments(message)"
              class="m-0 text-[13px] leading-snug text-n-slate-12"
            >
              {{ ATTACHMENT_GLYPH }}
            </p>
            <span
              v-if="hasAttachments(message)"
              class="flex items-center gap-1 text-[11px] text-n-slate-10"
            >
              <Icon icon="i-lucide-paperclip" class="size-3 shrink-0" />
              {{ t('KANBAN.PREVIEW.ATTACHMENT') }}
            </span>
            <span class="self-end text-[10px] leading-none text-n-slate-10">
              {{ formatTime(message) }}
            </span>
          </div>
        </div>
      </template>
    </div>

    <template #footer>
      <div class="flex items-center justify-between gap-3">
        <Button
          variant="faded"
          color="slate"
          type="button"
          :label="t('DIALOG.BUTTONS.CANCEL')"
          @click="close"
        />
        <Button
          color="blue"
          type="button"
          icon="i-lucide-arrow-up-right"
          :label="t('KANBAN.PREVIEW.OPEN')"
          @click="openConversation"
        />
      </div>
    </template>
  </Dialog>
</template>

<style scoped>
.kanban-preview__body {
  max-height: 60vh;
  min-height: 8rem;
}
</style>
