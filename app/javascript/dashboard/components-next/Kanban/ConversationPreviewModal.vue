<script setup>
import { ref, computed, watch, nextTick } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { format, isToday } from 'date-fns';
import { enUS, ptBR } from 'date-fns/locale';

import { useStore } from 'vuex';
import MessageApi from 'dashboard/api/inbox/message';
import KanbanAPI from 'dashboard/api/kanban';
import TasksAPI from 'dashboard/api/captain/tasks';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import {
  rawFieldValue,
  dropdownChoices,
  serializeFieldValue,
} from './composables/useCustomFields';
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

const store = useStore();
const getContactById = useMapGetter('contacts/getContactById');
const inboxById = useMapGetter('inboxes/getInboxById');
const activeFunnelId = useMapGetter('kanban/getActiveFunnelId');
const { isMessageRestricted } = useTeamIsolation();
const { isMessageRestricted: isAgentMessageRestricted } = useAgentIsolation();

const dialogRef = ref(null);
const scrollRef = ref(null);
const messages = ref([]);
const isLoading = ref(false);
const hasError = ref(false);
const replyText = ref('');
const isSending = ref(false);
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

// The kanban conversation object usually omits `can_reply`; only disable when
// the backend explicitly says false (default: replying is enabled).
const canReply = computed(() => props.conversation?.can_reply !== false);

// ── Custom fields (Fase 2): inline edit of values for the active funnel ──
const customFieldDefs = computed(() =>
  store.getters['kanban/getFunnelCustomFields'](activeFunnelId.value)
);
const conversationNumericId = computed(() => props.conversation?.id ?? null);
const funnelItemId = computed(() =>
  store.getters['kanban/getItemIdByConversation'](
    activeFunnelId.value,
    conversationNumericId.value
  )
);
const customAttributes = computed(
  () =>
    props.conversation?.custom_attributes ||
    props.conversation?.customAttributes ||
    {}
);
const fieldValues = ref({});
const savingFieldKey = ref(null);

const resetFieldValues = () => {
  const next = {};
  customFieldDefs.value.forEach(field => {
    const raw = rawFieldValue(field, customAttributes.value);
    if (field.fieldType === 'checkbox') {
      next[field.key] = raw === true || raw === 'true' || raw === '1';
    } else {
      next[field.key] = raw == null ? '' : String(raw);
    }
  });
  fieldValues.value = next;
};
watch([() => props.conversation, customFieldDefs], resetFieldValues, {
  immediate: true,
});

const choicesFor = field => dropdownChoices(field);

// Persist a single field on commit (blur / change / toggle).
const commitField = async field => {
  if (!funnelItemId.value || !activeFunnelId.value) return;
  const attrKey =
    field.attributeKey || `funnel_${activeFunnelId.value}_${field.key}`;
  const value = serializeFieldValue(field, fieldValues.value[field.key]);
  // Skip if unchanged from what's stored.
  const current = rawFieldValue(field, customAttributes.value);
  if (String(current ?? '') === value) return;

  savingFieldKey.value = field.key;
  try {
    await store.dispatch('kanban/updateItemCustomAttributes', {
      funnelId: activeFunnelId.value,
      itemId: funnelItemId.value,
      conversationId: conversationNumericId.value,
      attributes: { [attrKey]: value },
    });
  } catch (_) {
    useAlert(t('KANBAN.CUSTOM_FIELDS.SAVE_ERROR'));
    resetFieldValues();
  } finally {
    savingFieldKey.value = null;
  }
};

// ── Internal notes (Fase 4): the card's memory / shift handoff ──────────
const currentUserId = useMapGetter('getCurrentUserID');
const notes = ref([]);
const noteDraft = ref('');
const notesLoading = ref(false);
const noteSaving = ref(false);

const loadNotes = async () => {
  notes.value = [];
  if (!funnelItemId.value || !activeFunnelId.value) return;
  notesLoading.value = true;
  try {
    const { data } = await KanbanAPI.getItemNotes(
      activeFunnelId.value,
      funnelItemId.value
    );
    notes.value = Array.isArray(data) ? data : [];
  } catch (_) {
    // best effort
  } finally {
    notesLoading.value = false;
  }
};
watch([() => props.conversation, funnelItemId], loadNotes, { immediate: true });

const addNote = async () => {
  const content = noteDraft.value.trim();
  if (!content || !funnelItemId.value || noteSaving.value) return;
  noteSaving.value = true;
  try {
    const { data } = await KanbanAPI.createItemNote(
      activeFunnelId.value,
      funnelItemId.value,
      content
    );
    notes.value = [data, ...notes.value];
    noteDraft.value = '';
  } catch (_) {
    useAlert(t('KANBAN.NOTES.SAVE_ERROR'));
  } finally {
    noteSaving.value = false;
  }
};

const removeNote = async note => {
  try {
    await KanbanAPI.deleteItemNote(
      activeFunnelId.value,
      funnelItemId.value,
      note.id
    );
    notes.value = notes.value.filter(n => n.id !== note.id);
  } catch (_) {
    useAlert(t('KANBAN.NOTES.SAVE_ERROR'));
  }
};

const canDeleteNote = note =>
  Number(note.user_id) === Number(currentUserId.value);

const noteTime = note => {
  const date = new Date(note.created_at);
  if (Number.isNaN(date.getTime())) return '';
  const pattern = isToday(date) ? 'HH:mm' : 'dd MMM HH:mm';
  return format(date, pattern, { locale: dateLocale.value });
};

// ── AI actions (Fase 7) — reuse Chatwoot's Captain tasks, gated by config ─
const aiAvailable = ref(false);
const aiBusy = ref(null); // 'summary' | 'reply' | 'sentiment' | 'labels'
const aiResult = ref('');

const checkAiAvailability = async () => {
  aiAvailable.value = false;
  aiResult.value = '';
  try {
    const { data } = await KanbanAPI.getAiStatus();
    aiAvailable.value = Boolean(data?.available);
  } catch (_) {
    aiAvailable.value = false;
  }
};
watch(
  () => props.show,
  value => value && checkAiAvailability(),
  {
    immediate: true,
  }
);

const runAiTask = async (key, request, onSuccess) => {
  if (!displayId.value || aiBusy.value) return;
  aiBusy.value = key;
  aiResult.value = '';
  try {
    const { data } = await request();
    if (data?.error) {
      useAlert(data.error);
    } else {
      onSuccess(data?.message || '');
    }
  } catch (_) {
    useAlert(t('KANBAN.AI.ERROR'));
  } finally {
    aiBusy.value = null;
  }
};

const runSummarize = () =>
  runAiTask(
    'summary',
    () => TasksAPI.summarize(displayId.value),
    msg => {
      aiResult.value = msg;
    }
  );
const runSentiment = () =>
  runAiTask(
    'sentiment',
    () => TasksAPI.sentimentAnalysis(displayId.value),
    msg => {
      aiResult.value = msg;
    }
  );
const runLabels = () =>
  runAiTask(
    'labels',
    () => TasksAPI.labelSuggestion(displayId.value),
    msg => {
      aiResult.value = msg;
    }
  );
// Reply suggestion drops the draft straight into the composer to edit + send.
const runReply = () =>
  runAiTask(
    'reply',
    () => TasksAPI.replySuggestion(displayId.value),
    msg => {
      if (msg) {
        replyText.value = msg;
        useAlert(t('KANBAN.AI.REPLY_FILLED'));
      }
    }
  );

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

const sendReply = async () => {
  const content = replyText.value.trim();
  if (!content || !displayId.value || isSending.value) return;

  isSending.value = true;
  try {
    const { data } = await MessageApi.create({
      conversationId: displayId.value,
      message: content,
      private: false,
    });
    // Append to the local list so the new message shows on the right
    // (OUTGOING) at the bottom, matching the fetch render contract.
    messages.value.push(data);
    replyText.value = '';
    scrollToBottom();
    useAlert(t('KANBAN.PREVIEW.SENT'));
  } catch (error) {
    useAlert(error?.response?.data?.error || t('KANBAN.PREVIEW.SEND_ERROR'));
  } finally {
    isSending.value = false;
  }
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
  replyText.value = '';
  isSending.value = false;
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
    overflow-y-auto
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

    <!-- Custom fields (Fase 2): inline edit of the active funnel's fields -->
    <div
      v-if="customFieldDefs.length"
      class="mt-3 grid grid-cols-2 gap-x-3 gap-y-2 rounded-lg border border-n-weak bg-n-alpha-1 p-3"
    >
      <div
        v-for="field in customFieldDefs"
        :key="field.key"
        class="flex min-w-0 flex-col gap-1"
        :class="{ 'col-span-2': field.fieldType === 'long_text' }"
      >
        <label
          class="flex items-center gap-1 truncate text-[11px] font-medium text-n-slate-11"
        >
          {{ field.label }}
          <Icon
            v-if="savingFieldKey === field.key"
            icon="i-lucide-loader-2"
            class="size-3 animate-spin text-n-slate-10"
          />
        </label>

        <textarea
          v-if="field.fieldType === 'long_text'"
          v-model="fieldValues[field.key]"
          rows="2"
          class="kanban-cf-input resize-y"
          @blur="commitField(field)"
        />
        <select
          v-else-if="field.fieldType === 'dropdown'"
          v-model="fieldValues[field.key]"
          class="kanban-cf-input"
          @change="commitField(field)"
        >
          <option value="">—</option>
          <option
            v-for="choice in choicesFor(field)"
            :key="choice"
            :value="choice"
          >
            {{ choice }}
          </option>
        </select>
        <label
          v-else-if="field.fieldType === 'checkbox'"
          class="flex h-[30px] items-center"
        >
          <input
            v-model="fieldValues[field.key]"
            type="checkbox"
            class="size-4 accent-n-brand"
            @change="commitField(field)"
          />
        </label>
        <input
          v-else
          v-model="fieldValues[field.key]"
          :type="
            field.fieldType === 'number' || field.fieldType === 'rating'
              ? 'number'
              : field.fieldType === 'date'
                ? 'date'
                : field.fieldType === 'email'
                  ? 'email'
                  : 'text'
          "
          :min="field.fieldType === 'rating' ? 0 : undefined"
          :max="field.fieldType === 'rating' ? 5 : undefined"
          class="kanban-cf-input"
          @blur="commitField(field)"
          @keyup.enter="commitField(field)"
        />
      </div>
    </div>

    <!-- Internal notes (Fase 4): card memory / shift handoff -->
    <div v-if="funnelItemId" class="mt-3">
      <div class="mb-1 flex items-center gap-1.5">
        <Icon icon="i-lucide-sticky-note" class="size-3.5 text-n-slate-10" />
        <span
          class="text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
        >
          {{ t('KANBAN.NOTES.TITLE') }}
        </span>
      </div>
      <div class="flex items-center gap-2">
        <input
          v-model="noteDraft"
          type="text"
          class="kanban-cf-input flex-1"
          :placeholder="t('KANBAN.NOTES.PLACEHOLDER')"
          :disabled="noteSaving"
          @keyup.enter="addNote"
        />
        <Button
          size="sm"
          variant="ghost"
          :is-loading="noteSaving"
          :disabled="!noteDraft.trim()"
          @click="addNote"
        >
          {{ t('KANBAN.NOTES.ADD') }}
        </Button>
      </div>
      <ul
        v-if="notes.length"
        class="mt-2 flex max-h-28 flex-col gap-1.5 overflow-y-auto"
      >
        <li
          v-for="note in notes"
          :key="note.id"
          class="group flex items-start gap-2 rounded-lg bg-n-alpha-1 px-2.5 py-1.5"
        >
          <div class="min-w-0 flex-1">
            <p
              class="whitespace-pre-wrap break-words text-[13px] text-n-slate-12"
            >
              {{ note.content }}
            </p>
            <p class="mt-0.5 text-[10px] text-n-slate-10">
              {{ note.user?.name || t('KANBAN.NOTES.UNKNOWN_AUTHOR') }} ·
              {{ noteTime(note) }}
            </p>
          </div>
          <button
            v-if="canDeleteNote(note)"
            type="button"
            class="shrink-0 rounded p-1 text-n-slate-10 opacity-0 transition hover:bg-n-ruby-3 hover:text-n-ruby-11 group-hover:opacity-100"
            :title="t('KANBAN.NOTES.DELETE')"
            @click="removeNote(note)"
          >
            <Icon icon="i-lucide-trash-2" class="size-3" />
          </button>
        </li>
      </ul>
    </div>

    <!-- AI actions (Fase 7) — only when AI is configured for the account -->
    <div
      v-if="aiAvailable"
      class="mt-3 rounded-lg border border-n-weak bg-n-alpha-1 p-2"
    >
      <div class="flex flex-wrap items-center gap-1.5">
        <span
          class="mr-1 flex items-center gap-1 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
        >
          <Icon icon="i-lucide-sparkles" class="size-3.5" />
          {{ t('KANBAN.AI.TITLE') }}
        </span>
        <Button
          size="sm"
          variant="ghost"
          :is-loading="aiBusy === 'summary'"
          @click="runSummarize"
        >
          {{ t('KANBAN.AI.SUMMARIZE') }}
        </Button>
        <Button
          size="sm"
          variant="ghost"
          :is-loading="aiBusy === 'reply'"
          @click="runReply"
        >
          {{ t('KANBAN.AI.REPLY') }}
        </Button>
        <Button
          size="sm"
          variant="ghost"
          :is-loading="aiBusy === 'sentiment'"
          @click="runSentiment"
        >
          {{ t('KANBAN.AI.SENTIMENT') }}
        </Button>
        <Button
          size="sm"
          variant="ghost"
          :is-loading="aiBusy === 'labels'"
          @click="runLabels"
        >
          {{ t('KANBAN.AI.LABELS') }}
        </Button>
      </div>
      <p
        v-if="aiResult"
        class="mt-2 whitespace-pre-wrap rounded-lg bg-n-solid-1 p-2 text-[13px] leading-snug text-n-slate-12"
      >
        {{ aiResult }}
      </p>
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

    <!-- Reply composer -->
    <div class="kanban-preview__composer mt-3 flex flex-col gap-2">
      <p
        v-if="!canReply"
        class="m-0 flex items-center gap-1 text-xs text-n-slate-10"
      >
        <Icon icon="i-lucide-info" class="size-3 shrink-0" />
        {{ t('KANBAN.PREVIEW.REPLY_DISABLED') }}
      </p>
      <div class="flex items-end gap-2">
        <textarea
          v-model="replyText"
          :disabled="!canReply || isSending"
          :placeholder="t('KANBAN.PREVIEW.REPLY_PLACEHOLDER')"
          rows="2"
          class="kanban-preview__textarea min-w-0 flex-1 resize-none rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-[13px] leading-snug text-n-slate-12 outline-none focus:border-n-brand disabled:opacity-60"
          @keydown.enter.ctrl.exact.prevent="sendReply"
          @keydown.enter.meta.exact.prevent="sendReply"
        />
        <Button
          color="blue"
          type="button"
          icon="i-lucide-send"
          :label="t('KANBAN.PREVIEW.SEND')"
          :is-loading="isSending"
          :disabled="!canReply || !replyText.trim() || isSending"
          @click="sendReply"
        />
      </div>
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
  /* Capped so the composer + footer buttons stay visible on the screen.
     The dialog itself is overflow-y-auto as a safety net on short screens. */
  max-height: 42vh;
  min-height: 6rem;
}

/* Compact inputs for the inline custom-fields panel */
.kanban-cf-input {
  width: 100%;
  border-radius: 0.5rem;
  border: 1px solid var(--color-border-weak, rgba(0, 0, 0, 0.1));
  background-color: var(--color-background, #fff);
  padding: 0.3rem 0.5rem;
  font-size: 12px;
  line-height: 1.2;
  color: inherit;
}
.kanban-cf-input:focus {
  outline: none;
  border-color: var(--color-woot, #1f93ff);
}
</style>
