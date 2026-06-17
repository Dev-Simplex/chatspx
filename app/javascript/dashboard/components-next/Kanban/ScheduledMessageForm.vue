<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import { DirectUpload } from 'activestorage';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { useAlert } from 'dashboard/composables';
import ContactAPI from 'dashboard/api/contacts';
import ScheduleRecipientPicker from './ScheduleRecipientPicker.vue';
import ScheduleComposer from './ScheduleComposer.vue';
import ScheduleDateTimePicker from './ScheduleDateTimePicker.vue';
import {
  checkFileSizeLimit,
  DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE,
  getMaxUploadSizeByChannel,
  resolveMaximumFileUploadSize,
  effectiveMaxUploadSize,
  formatBytes,
  buildAttachmentThumbUrl,
} from 'shared/helpers/FileHelper';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  conversation: {
    type: Object,
    default: null,
  },
  scheduledMessage: {
    type: Object,
    default: null,
  },
  requireConversation: {
    type: Boolean,
    default: false,
  },
  selectedDate: {
    type: Date,
    default: null,
  },
});

const emit = defineEmits(['close', 'saved']);

const store = useStore();
const { t } = useI18n();

const formData = ref({
  message: '',
  scheduledAt: '',
  inboxId: null,
  conversationId: null,
  contactId: null,
});

const searchQuery = ref('');
const searchResults = ref([]);
const isSearching = ref(false);
const selectedContact = ref(null);
const selectedConversation = ref(null);
const isFetchingConversations = ref(false);
const attachedFiles = ref([]);
const uploadCount = ref(0);
const dialogRef = ref(null);
const dateTimePickerRef = ref(null);

const inboxes = computed(() => store.getters['kanban/getWahaInboxes']);
const isEditMode = computed(() => Boolean(props.scheduledMessage?.id));
const isLoading = computed(() => {
  const flags = store.getters['kanban/getUIFlags'];
  return isEditMode.value ? flags.isUpdating : flags.isCreating;
});
const globalConfig = computed(() => store.getters['globalConfig/get']);
const currentUser = computed(() => store.getters.getCurrentUser);
const accountId = computed(() => store.getters.getCurrentAccountId);
const accountFeatureGetter = computed(
  () => store.getters['accounts/isFeatureEnabledonAccount']
);
const isKanbanUxV2Enabled = computed(() => {
  if (typeof accountFeatureGetter.value === 'function' && accountId.value) {
    return accountFeatureGetter.value(Number(accountId.value), 'kanban_ux_v2');
  }

  return true;
});
const directUploadsEnabled = computed(
  () => globalConfig.value?.directUploadsEnabled
);
const installationLimit = computed(() =>
  resolveMaximumFileUploadSize(globalConfig.value?.maximumFileUploadSize)
);
const isUploadingAttachments = computed(() => uploadCount.value > 0);
const dialogTitle = computed(() =>
  isEditMode.value
    ? t('KANBAN.SCHEDULED_MESSAGES.EDIT_TITLE')
    : t('KANBAN.SCHEDULED_MESSAGES.CREATE_TITLE')
);
const dialogSubtitle = computed(() =>
  isEditMode.value
    ? t('KANBAN.SCHEDULED_MESSAGES.EDIT_SUBTITLE')
    : t('KANBAN.SCHEDULED_MESSAGES.CREATE_SUBTITLE')
);
const submitButtonLabel = computed(() =>
  isEditMode.value
    ? t('KANBAN.SCHEDULED_MESSAGES.SAVE_CHANGES')
    : t('KANBAN.SCHEDULED_MESSAGES.CONFIRM_SCHEDULE')
);
const showContactSelector = computed(
  () => !isEditMode.value && !props.requireConversation && !props.conversation
);
const timezoneLabel = computed(
  () => Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC'
);

const getContactName = contact =>
  contact?.name ||
  contact?.identifier ||
  contact?.email ||
  t('KANBAN.ITEMS.UNNAMED_CONTACT');

const getContactPhone = contact =>
  contact?.phone_number ||
  contact?.phoneNumber ||
  contact?.identifier ||
  contact?.email ||
  '';

const getContactAvatar = contact =>
  contact?.thumbnail || contact?.avatar_url || contact?.avatar || '';

const contactInfo = computed(() => {
  const source = props.conversation?.contact || selectedContact.value;
  if (!source) return null;

  return {
    name: getContactName(source),
    phone: getContactPhone(source),
    avatar: getContactAvatar(source),
  };
});

const activeConversationId = computed(
  () => props.conversation?.id || formData.value.conversationId
);

const activeInboxId = computed(() => {
  return (
    formData.value.inboxId ||
    props.conversation?.inboxId ||
    props.conversation?.inbox_id ||
    selectedConversation.value?.inboxId ||
    selectedConversation.value?.inbox_id ||
    null
  );
});

const activeInbox = computed(() => {
  if (!activeInboxId.value) return null;
  return inboxes.value.find(
    inbox => Number(inbox.id) === Number(activeInboxId.value)
  );
});

const dateToLocalInput = date => {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  const hours = String(date.getHours()).padStart(2, '0');
  const minutes = String(date.getMinutes()).padStart(2, '0');
  return `${year}-${month}-${day}T${hours}:${minutes}`;
};

const localToUTC = localDateString => {
  const localDate = new Date(localDateString);
  if (Number.isNaN(localDate.getTime())) {
    throw new Error('invalid_datetime');
  }
  return localDate.toISOString();
};

const utcToLocal = utcDateString => {
  const utcDate = new Date(utcDateString);
  return dateToLocalInput(utcDate);
};

const alertOverLimit = (maxSizeMB, file) => {
  const fileSize = file?.file?.size || file?.size;
  useAlert(
    t('CONVERSATION.FILE_SIZE_LIMIT_HARD', {
      MAXIMUM_SUPPORTED_FILE_UPLOAD_SIZE: maxSizeMB,
      fileSize: fileSize ? formatBytes(fileSize) : '',
    }),
    // Centered + error styling so the limit warning is hard to miss.
    {
      position: 'center',
      variant: 'error',
      icon: 'i-lucide-alert-triangle',
      duration: 4000,
    }
  );
};

// The hard 100MB ceiling is always applied on top of the
// channel/installation limit (see effectiveMaxUploadSize).
const maxSizeFor = mime => {
  let rawLimit = installationLimit.value;

  const channelType = activeInbox.value?.channel_type;

  if (channelType && channelType !== INBOX_TYPES.WEB) {
    const channelLimit = getMaxUploadSizeByChannel({
      channelType,
      medium: activeInbox.value?.medium,
      mime,
    });

    if (channelLimit !== DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE) {
      rawLimit = Math.min(channelLimit, installationLimit.value);
    }
  }

  return effectiveMaxUploadSize(rawLimit);
};

const attachFile = ({ blob, file }) => {
  if (!file) return;
  const fileToRead = file?.file || file;
  if (!(fileToRead instanceof Blob)) return;

  // Synchronous object URL preview (image/video only) instead of reading the
  // whole file into a base64 string — no main-thread block, no memory spike.
  const newFile = {
    resource: blob || fileToRead,
    isPrivate: false,
    thumb: buildAttachmentThumbUrl(fileToRead),
    blobSignedId: blob?.signed_id,
  };
  attachedFiles.value = [...attachedFiles.value, newFile];
};

const mapExistingAttachment = attachment => {
  const signedId = attachment.blobSignedId || attachment.blob_signed_id;
  const filename = attachment.filename || attachment.name || 'attachment';
  const dataUrl = attachment.url || attachment.data_url || '';

  return {
    resource: {
      id: attachment.id || signedId || filename,
      signed_id: signedId,
      blob_signed_id: signedId,
      filename,
      name: filename,
      content_type: attachment.contentType || attachment.content_type || '',
      contentType: attachment.contentType || attachment.content_type || '',
      type: attachment.contentType || attachment.content_type || '',
      byte_size: attachment.byteSize || attachment.byte_size || 0,
      data_url: dataUrl,
    },
    thumb: attachment.thumbUrl || attachment.thumb_url || dataUrl,
    blobSignedId: signedId,
  };
};

const handleFileUpload = (file, oldFile) => {
  if (!file || oldFile) return;
  const nativeFile = file.file || file;
  if (!(nativeFile instanceof File)) return;

  const mime = nativeFile.type || file.type;
  const maxSizeMB = maxSizeFor(mime);

  if (!checkFileSizeLimit(file, maxSizeMB)) {
    alertOverLimit(maxSizeMB, file);
    return;
  }

  if (directUploadsEnabled.value && activeConversationId.value) {
    uploadCount.value += 1;

    const upload = new DirectUpload(
      nativeFile,
      `/api/v1/accounts/${accountId.value}/conversations/${activeConversationId.value}/direct_uploads`,
      {
        directUploadWillCreateBlobWithXHR: xhr => {
          xhr.setRequestHeader(
            'api_access_token',
            currentUser.value?.access_token
          );
        },
      }
    );

    upload.create((error, blob) => {
      uploadCount.value -= 1;
      if (error) {
        useAlert(error);
        return;
      }

      attachFile({ blob, file });
    });
    return;
  }

  attachFile({ file });
};

const prepareAttachmentsPayload = () => {
  if (!attachedFiles.value.length) return [];

  return attachedFiles.value
    .map(attachment => {
      const existingSignedId =
        attachment.blobSignedId ??
        attachment.blob_signed_id ??
        attachment.resource?.signed_id ??
        attachment.resource?.blob_signed_id;

      if (existingSignedId) {
        return existingSignedId;
      }

      if (attachment.resource?.file) return attachment.resource.file;
      if (attachment.file) return attachment.file;
      if (attachment.resource instanceof File) return attachment.resource;
      return null;
    })
    .filter(Boolean);
};

const setDefaultScheduledDate = () => {
  const now = new Date();
  let defaultDate = new Date(now);

  const scheduledDateValue =
    props.scheduledMessage?.scheduledAt || props.scheduledMessage?.scheduled_at;

  if (isEditMode.value && scheduledDateValue) {
    formData.value.scheduledAt = utcToLocal(scheduledDateValue);
    return;
  }

  const preferredDate = props.selectedDate || props.conversation?.date;
  if (preferredDate) {
    const parsedPreferredDate = new Date(preferredDate);
    if (!Number.isNaN(parsedPreferredDate.getTime())) {
      // Keep the selected day, but default to the user's current time.
      defaultDate.setFullYear(
        parsedPreferredDate.getFullYear(),
        parsedPreferredDate.getMonth(),
        parsedPreferredDate.getDate()
      );
    }
  }

  if (Number.isNaN(defaultDate.getTime())) {
    defaultDate = new Date(now);
  }

  defaultDate.setSeconds(0, 0);
  if (defaultDate <= now) {
    defaultDate = new Date(now);
    defaultDate.setSeconds(0, 0);
    defaultDate.setMinutes(defaultDate.getMinutes() + 60);
  }

  formData.value.scheduledAt = dateToLocalInput(defaultDate);
};

const resetDialogState = () => {
  const scheduledMessage = props.scheduledMessage || {};

  formData.value = {
    message: isEditMode.value
      ? (scheduledMessage.message || '').toString()
      : '',
    scheduledAt: '',
    inboxId:
      scheduledMessage.inboxId ||
      scheduledMessage.inbox_id ||
      props.conversation?.inboxId ||
      props.conversation?.inbox_id ||
      null,
    conversationId:
      scheduledMessage.conversationId ||
      scheduledMessage.conversation_id ||
      props.conversation?.id ||
      null,
    contactId: null,
  };

  selectedContact.value = null;
  selectedConversation.value = null;
  searchQuery.value = '';
  searchResults.value = [];
  isSearching.value = false;
  isFetchingConversations.value = false;
  uploadCount.value = 0;
  attachedFiles.value = isEditMode.value
    ? Array(scheduledMessage.attachments || []).map(mapExistingAttachment)
    : [];

  setDefaultScheduledDate();
};

const searchContacts = debounce(async query => {
  if (!query?.trim()) {
    searchResults.value = [];
    isSearching.value = false;
    return;
  }

  isSearching.value = true;
  try {
    if (isKanbanUxV2Enabled.value) {
      const {
        data: { payload = [] },
      } = await ContactAPI.searchForSchedule({
        q: query.trim(),
        page: 1,
        perPage: 10,
      });

      searchResults.value = payload;
    } else {
      const {
        data: { payload = [] },
      } = await ContactAPI.search(query.trim(), 1, 'name');
      searchResults.value = payload.map(contact => ({
        ...contact,
        primary_conversation: null,
        recommended_inbox: null,
      }));
    }
  } catch (_) {
    searchResults.value = [];
  } finally {
    isSearching.value = false;
  }
}, 250);

const selectContact = contact => {
  selectedContact.value = contact;
  formData.value.contactId = contact.id;

  const primaryConversation =
    contact.primaryConversation || contact.primary_conversation || null;
  selectedConversation.value = primaryConversation;
  formData.value.conversationId = primaryConversation?.id || null;

  const recommendedInbox =
    contact.recommendedInbox || contact.recommended_inbox || null;

  formData.value.inboxId =
    primaryConversation?.inboxId ||
    primaryConversation?.inbox_id ||
    recommendedInbox?.id ||
    formData.value.inboxId;

  searchQuery.value = '';
  searchResults.value = [];
};

const clearContactSelection = () => {
  selectedContact.value = null;
  selectedConversation.value = null;
  formData.value.contactId = null;
  formData.value.conversationId = null;
};

const save = async () => {
  if (isUploadingAttachments.value) {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.ATTACHMENTS_UPLOADING'));
    return;
  }

  if (isEditMode.value && props.scheduledMessage?.status !== 'pending') {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.ONLY_PENDING_EDIT'));
    return;
  }

  const hasText = Boolean((formData.value.message || '').trim());
  const hasAttachments = attachedFiles.value.length > 0;
  if (!hasText && !hasAttachments) {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.MESSAGE_REQUIRED_FRIENDLY'));
    return;
  }

  if (!formData.value.scheduledAt) {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.DATE_REQUIRED_FRIENDLY'));
    return;
  }

  let scheduledAtUTC;
  try {
    scheduledAtUTC = localToUTC(formData.value.scheduledAt);
  } catch (_) {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.DATE_INVALID'));
    return;
  }

  if (new Date(scheduledAtUTC).getTime() - Date.now() < 60 * 1000) {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.DATE_FUTURE_FRIENDLY'));
    return;
  }

  const conversationId =
    props.conversation?.id ||
    formData.value.conversationId ||
    props.scheduledMessage?.conversationId ||
    props.scheduledMessage?.conversation_id;
  const contactId = formData.value.contactId;

  if (props.requireConversation && !conversationId) {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.CONVERSATION_REQUIRED'));
    return;
  }

  if (!isEditMode.value && !conversationId && !contactId) {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.CONTACT_REQUIRED'));
    return;
  }

  if (!isEditMode.value && !conversationId && !formData.value.inboxId) {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.INBOX_REQUIRED'));
    return;
  }

  const attachmentsPayload = prepareAttachmentsPayload();
  const hasFileAttachments = attachmentsPayload.some(
    attachment => attachment instanceof File
  );

  const messagePayload = {
    message: (formData.value.message || '').trim(),
    scheduled_at: scheduledAtUTC,
  };

  if (formData.value.inboxId) {
    messagePayload.inbox_id = formData.value.inboxId;
  }

  if (!isEditMode.value) {
    if (conversationId) {
      messagePayload.conversation_id = conversationId;
    } else {
      messagePayload.contact_id = contactId;
    }
  }

  if (attachmentsPayload.length && !hasFileAttachments) {
    messagePayload.attachments = attachmentsPayload;
  }

  let payload;
  if (hasFileAttachments) {
    const formDataPayload = new FormData();
    Object.entries(messagePayload).forEach(([key, value]) => {
      if (value == null) return;
      formDataPayload.append(`scheduled_message[${key}]`, value);
    });

    attachmentsPayload.forEach(attachment => {
      if (attachment instanceof File || typeof attachment === 'string') {
        formDataPayload.append('scheduled_message[attachments][]', attachment);
      }
    });

    payload = formDataPayload;
  } else {
    payload = isEditMode.value
      ? messagePayload
      : { scheduled_message: messagePayload };
  }

  try {
    if (isEditMode.value) {
      await store.dispatch('kanban/updateScheduledMessage', {
        messageId: props.scheduledMessage.id,
        data: payload,
      });
    } else {
      await store.dispatch('kanban/createScheduledMessage', payload);
    }

    emit('saved');
    emit('close');
  } catch (_) {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.SAVE_ERROR_FRIENDLY'));
  }
};

const close = () => {
  emit('close');
};

watch(
  () => props.show,
  async isVisible => {
    if (isVisible) {
      resetDialogState();
      await nextTick();
      dialogRef.value?.open?.();
      await nextTick();
      dateTimePickerRef.value?.focusFirstQuickOption?.();
      return;
    }

    dialogRef.value?.close?.();
  },
  { immediate: true }
);

watch(searchQuery, query => {
  if (!query?.trim()) {
    searchResults.value = [];
    isSearching.value = false;
    return;
  }

  searchContacts(query);
});

onMounted(async () => {
  await store.dispatch('kanban/fetchWahaInboxes');
});
</script>

<template>
  <Dialog
    v-if="show"
    ref="dialogRef"
    :show-cancel-button="false"
    :show-confirm-button="false"
    width="2xl"
    overflow-y-auto
    @close="close"
  >
    <div class="space-y-5">
      <header class="flex items-start gap-3">
        <div
          class="flex size-10 shrink-0 items-center justify-center rounded-full bg-n-brand/10 text-n-brand"
          aria-hidden="true"
        >
          <span class="i-lucide-send-horizontal size-5" />
        </div>
        <div class="min-w-0">
          <h2
            id="scheduled-message-title"
            class="text-lg font-semibold leading-6 text-n-slate-12"
          >
            {{ dialogTitle }}
          </h2>
          <p class="mt-1 text-sm text-n-slate-11">
            {{ dialogSubtitle }}
          </p>
        </div>
      </header>

      <ScheduleRecipientPicker
        :show-selector="showContactSelector"
        :search-query="searchQuery"
        :search-results="searchResults"
        :is-searching="isSearching"
        :selected-contact="selectedContact"
        :selected-conversation="selectedConversation"
        :contact-info="contactInfo"
        :is-fetching-conversations="isFetchingConversations"
        @update:search-query="searchQuery = $event"
        @select-contact="selectContact"
        @clear-contact="clearContactSelection"
      />

      <section
        class="rounded-xl border border-n-weak bg-n-solid-2/40 p-4"
        aria-labelledby="schedule-when-heading"
      >
        <h3 id="schedule-when-heading" class="sr-only">
          {{ t('KANBAN.SCHEDULED_MESSAGES.WHEN_TO_SEND') }}
        </h3>
        <ScheduleDateTimePicker
          ref="dateTimePickerRef"
          :scheduled-at="formData.scheduledAt"
          :timezone-label="timezoneLabel"
          @update:scheduled-at="formData.scheduledAt = $event"
        />
      </section>

      <section
        class="rounded-xl border border-n-weak bg-n-solid-2/40 p-4"
        aria-labelledby="schedule-message-heading"
      >
        <h3
          id="schedule-message-heading"
          class="mb-3 text-sm font-semibold text-n-slate-12"
        >
          {{ t('KANBAN.SCHEDULED_MESSAGES.YOUR_MESSAGE_HEADING') }}
        </h3>
        <ScheduleComposer
          :message="formData.message"
          :inbox-id="formData.inboxId"
          :inboxes="inboxes"
          :attached-files="attachedFiles"
          :is-uploading-attachments="isUploadingAttachments"
          can-attach
          @update:message="formData.message = $event"
          @update:inbox-id="formData.inboxId = $event"
          @update:attached-files="attachedFiles = $event"
          @file-upload="handleFileUpload"
        />
      </section>
    </div>

    <template #footer>
      <div
        class="flex w-full flex-col-reverse items-stretch gap-2 sm:flex-row sm:items-center sm:justify-end sm:gap-3"
      >
        <Button
          :label="t('KANBAN.SCHEDULED_MESSAGES.BACK')"
          type="button"
          variant="faded"
          color="slate"
          class="h-10 sm:w-auto"
          @click="close"
        />
        <Button
          :label="submitButtonLabel"
          color="blue"
          type="button"
          icon="i-lucide-send-horizontal"
          :is-loading="isLoading || isUploadingAttachments"
          :disabled="isUploadingAttachments"
          class="h-10 sm:w-auto"
          @click="save"
        />
      </div>
    </template>
  </Dialog>
</template>
