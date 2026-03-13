<script setup>
import { reactive, ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, requiredIf } from '@vuelidate/validators';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import {
  appendSignature,
  removeSignature,
  getEffectiveChannelType,
  stripUnsupportedMarkdown,
} from 'dashboard/helper/editorHelper';
import {
  buildContactableInboxesList,
  prepareNewMessagePayload,
  prepareWhatsAppMessagePayload,
} from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper.js';

import ContactAPI from 'dashboard/api/contacts';
import { useAlert } from 'dashboard/composables';
import ContactSelector from './ContactSelector.vue';
import InboxSelector from './InboxSelector.vue';
import EmailOptions from './EmailOptions.vue';
import MessageEditor from './MessageEditor.vue';
import ActionButtons from './ActionButtons.vue';
import InboxEmptyState from './InboxEmptyState.vue';
import AttachmentPreviews from './AttachmentPreviews.vue';

const props = defineProps({
  contacts: { type: Array, default: () => [] },
  contactId: { type: String, default: null },
  selectedContact: { type: Object, default: null },
  targetInbox: { type: Object, default: null },
  currentUser: { type: Object, default: null },
  isCreatingContact: { type: Boolean, default: false },
  isFetchingInboxes: { type: Boolean, default: false },
  isLoading: { type: Boolean, default: false },
  isDirectUploadsEnabled: { type: Boolean, default: false },
  contactConversationsUiFlags: { type: Object, default: null },
  contactsUiFlags: { type: Object, default: null },
  messageSignature: { type: String, default: '' },
  sendWithSignature: { type: Boolean, default: false },
});

const emit = defineEmits([
  'searchContacts',
  'discard',
  'updateSelectedContact',
  'updateTargetInbox',
  'clearSelectedContact',
  'createConversation',
]);

const { t } = useI18n();

const DEFAULT_FORMATTING = 'Context::Default';

const showContactsDropdown = ref(false);
const showInboxesDropdown = ref(false);
const showCcEmailsDropdown = ref(false);
const showBccEmailsDropdown = ref(false);

const isCreating = computed(() => props.contactConversationsUiFlags.isCreating);

const state = reactive({
  message: '',
  subject: '',
  ccEmails: '',
  bccEmails: '',
  attachedFiles: [],
});

const inboxTypes = computed(() => ({
  isEmail: props.targetInbox?.channelType === INBOX_TYPES.EMAIL,
  isTwilio: props.targetInbox?.channelType === INBOX_TYPES.TWILIO,
  isWhatsapp: props.targetInbox?.channelType === INBOX_TYPES.WHATSAPP,
  isWebWidget: props.targetInbox?.channelType === INBOX_TYPES.WEB,
  isApi: props.targetInbox?.channelType === INBOX_TYPES.API,
  isEmailOrWebWidget:
    props.targetInbox?.channelType === INBOX_TYPES.EMAIL ||
    props.targetInbox?.channelType === INBOX_TYPES.WEB,
  isTwilioSMS:
    props.targetInbox?.channelType === INBOX_TYPES.TWILIO &&
    props.targetInbox?.medium === 'sms',
  isTwilioWhatsapp:
    props.targetInbox?.channelType === INBOX_TYPES.TWILIO &&
    props.targetInbox?.medium === 'whatsapp',
}));

const whatsappInvalidMessage = computed(() =>
  t('CONVERSATION.REPLYBOX.WHATSAPP_INVALID')
);

const whatsappCustomAttributes = computed(() => {
  const contact = props.selectedContact || {};
  return (
    contact.customAttributes ||
    contact.custom_attributes ||
    contact.custom_attributes ||
    {}
  );
});

const whatsappNumberExists = computed(() => {
  const attributes = whatsappCustomAttributes.value || {};
  const snakeValue = attributes.whatsapp_number_exists;
  if (snakeValue !== undefined) return snakeValue;
  return attributes.whatsappNumberExists;
});

const isWhatsappInvalid = computed(() => whatsappNumberExists.value === false);

const isApiInbox = computed(() => inboxTypes.value.isApi);

const isWhatsappTargetInbox = computed(
  () =>
    inboxTypes.value.isWhatsapp ||
    inboxTypes.value.isTwilioWhatsapp ||
    isApiInbox.value
);

const hasOnlyWhatsappInboxes = computed(() => {
  if (!contactableInboxesList.value?.length) return false;
  return contactableInboxesList.value.every(inbox => {
    const isWhatsapp =
      inbox.channelType === INBOX_TYPES.WHATSAPP ||
      (inbox.channelType === INBOX_TYPES.TWILIO && inbox.medium === 'whatsapp');
    const isApiWaha = inbox.channelType === INBOX_TYPES.API;
    return isWhatsapp || isApiWaha;
  });
});

const shouldShowWhatsappInvalidBanner = computed(
  () =>
    isWhatsappInvalid.value &&
    (isWhatsappTargetInbox.value || hasOnlyWhatsappInboxes.value)
);

const shouldBlockWhatsappSend = computed(
  () => isWhatsappInvalid.value && isWhatsappTargetInbox.value
);

const isRevalidatingWhatsapp = ref(false);
const revalidateBannerMessage = ref('');

async function revalidateWhatsappNumber() {
  if (isRevalidatingWhatsapp.value) return;
  const contactId = props.selectedContact?.id;
  if (!contactId) return;

  isRevalidatingWhatsapp.value = true;
  revalidateBannerMessage.value = '';
  try {
    const { data } = await ContactAPI.revalidateWhatsapp(contactId);
    if (data.whatsapp_number_exists) {
      useAlert(t('CONVERSATION.REPLYBOX.WHATSAPP_REVALIDATE_SUCCESS'));
      const contact = props.selectedContact;
      if (contact) {
        const attrs =
          contact.customAttributes || contact.custom_attributes || {};
        attrs.whatsapp_number_exists = true;
        contact.customAttributes = attrs;
        contact.custom_attributes = attrs;
      }
    } else {
      revalidateBannerMessage.value = t(
        'CONVERSATION.REPLYBOX.WHATSAPP_REVALIDATE_STILL_INVALID'
      );
    }
  } catch (error) {
    const status = error?.response?.status;
    revalidateBannerMessage.value =
      status === 429
        ? t('CONVERSATION.REPLYBOX.WHATSAPP_REVALIDATE_COOLDOWN')
        : t('CONVERSATION.REPLYBOX.WHATSAPP_REVALIDATE_ERROR');
  } finally {
    isRevalidatingWhatsapp.value = false;
  }
}

const whatsappMessageTemplates = computed(() =>
  Object.keys(props.targetInbox?.messageTemplates || {}).length
    ? props.targetInbox.messageTemplates
    : []
);

const inboxChannelType = computed(() => props.targetInbox?.channelType || '');

const inboxMedium = computed(() => props.targetInbox?.medium || '');

const effectiveChannelType = computed(() =>
  getEffectiveChannelType(inboxChannelType.value, inboxMedium.value)
);

const validationRules = computed(() => ({
  selectedContact: { required },
  targetInbox: { required },
  message: { required: requiredIf(!inboxTypes.value.isWhatsapp) },
  subject: { required: requiredIf(inboxTypes.value.isEmail) },
}));

const v$ = useVuelidate(validationRules, {
  selectedContact: computed(() => props.selectedContact),
  targetInbox: computed(() => props.targetInbox),
  message: computed(() => state.message),
  subject: computed(() => state.subject),
});

const validationStates = computed(() => ({
  isContactInvalid:
    v$.value.selectedContact.$dirty && v$.value.selectedContact.$invalid,
  isInboxInvalid: v$.value.targetInbox.$dirty && v$.value.targetInbox.$invalid,
  isSubjectInvalid: v$.value.subject.$dirty && v$.value.subject.$invalid,
  isMessageInvalid: v$.value.message.$dirty && v$.value.message.$invalid,
}));

const newMessagePayload = () => {
  const { message, subject, ccEmails, bccEmails, attachedFiles } = state;
  return prepareNewMessagePayload({
    targetInbox: props.targetInbox,
    selectedContact: props.selectedContact,
    message,
    subject,
    ccEmails,
    bccEmails,
    currentUser: props.currentUser,
    attachedFiles,
    directUploadsEnabled: props.isDirectUploadsEnabled,
  });
};

const contactableInboxesList = computed(() => {
  return buildContactableInboxesList(props.selectedContact?.contactInboxes);
});

const showNoInboxAlert = computed(() => {
  return (
    props.selectedContact &&
    contactableInboxesList.value.length === 0 &&
    !props.contactsUiFlags.isFetchingInboxes &&
    !props.isFetchingInboxes
  );
});

const isAnyDropdownActive = computed(() => {
  return (
    showContactsDropdown.value ||
    showInboxesDropdown.value ||
    showCcEmailsDropdown.value ||
    showBccEmailsDropdown.value
  );
});

const handleContactSearch = value => {
  showContactsDropdown.value = true;
  const query = typeof value === 'string' ? value.trim() : '';
  const hasAlphabet = Array.from(query).some(char => {
    const lower = char.toLowerCase();
    const upper = char.toUpperCase();
    return lower !== upper;
  });
  const isEmailLike = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(query);

  const keys = ['email', 'phone_number', 'name'].filter(key => {
    if (key === 'phone_number' && hasAlphabet) return false;
    if (key === 'name' && isEmailLike) return false;
    return true;
  });

  emit('searchContacts', { keys, query: value });
};

const handleDropdownUpdate = (type, value) => {
  if (type === 'cc') {
    showCcEmailsDropdown.value = value;
  } else if (type === 'bcc') {
    showBccEmailsDropdown.value = value;
  } else {
    showContactsDropdown.value = value;
  }
};

const searchCcEmails = value => {
  showCcEmailsDropdown.value = true;
  emit('searchContacts', { keys: ['email'], query: value });
};

const searchBccEmails = value => {
  showBccEmailsDropdown.value = true;
  emit('searchContacts', { keys: ['email'], query: value });
};

const setSelectedContact = async ({ value, action, ...rest }) => {
  v$.value.$reset();
  emit('updateSelectedContact', { value, action, ...rest });
  showContactsDropdown.value = false;
  showInboxesDropdown.value = true;
};

const stripMessageFormatting = channelType => {
  if (!state.message || !channelType) return;

  state.message = stripUnsupportedMarkdown(state.message, channelType, false);
};

const handleInboxAction = ({ value, action, channelType, medium, ...rest }) => {
  v$.value.$reset();

  // Strip unsupported formatting when changing the target inbox
  if (channelType) {
    const newChannelType = getEffectiveChannelType(channelType, medium);
    stripMessageFormatting(newChannelType);
  }

  emit('updateTargetInbox', { ...rest, channelType, medium });
  showInboxesDropdown.value = false;
  state.attachedFiles = [];
};

const removeSignatureFromMessage = () => {
  // Always remove the signature from message content when inbox/contact is removed
  // to ensure no leftover signature content remains
  if (props.messageSignature) {
    state.message = removeSignature(
      state.message,
      props.messageSignature,
      effectiveChannelType.value
    );
  }
};

const removeTargetInbox = value => {
  v$.value.$reset();
  removeSignatureFromMessage();

  stripMessageFormatting(DEFAULT_FORMATTING);

  emit('updateTargetInbox', value);
  state.attachedFiles = [];
};

const clearSelectedContact = () => {
  removeSignatureFromMessage();
  emit('clearSelectedContact');
  state.message = '';
  state.attachedFiles = [];
};

const onClickInsertEmoji = emoji => {
  state.message += emoji;
};

const handleAddSignature = signature => {
  state.message = appendSignature(
    state.message,
    signature,
    effectiveChannelType.value
  );
};

const handleRemoveSignature = signature => {
  state.message = removeSignature(
    state.message,
    signature,
    effectiveChannelType.value
  );
};

const handleAttachFile = files => {
  state.attachedFiles = files;
};

const clearForm = () => {
  Object.assign(state, {
    message: '',
    subject: '',
    ccEmails: '',
    bccEmails: '',
    attachedFiles: [],
  });
  v$.value.$reset();
};

const handleSendMessage = async () => {
  const isValid = await v$.value.$validate();
  if (!isValid) return;

  if (shouldBlockWhatsappSend.value) return;

  try {
    const success = await emit('createConversation', {
      payload: newMessagePayload(),
      isFromWhatsApp: false,
    });
    if (success) {
      clearForm();
    }
  } catch (error) {
    // Form will not be cleared if conversation creation fails
  }
};

const handleSendWhatsappMessage = async ({ message, templateParams }) => {
  if (shouldBlockWhatsappSend.value) return;

  const whatsappMessagePayload = prepareWhatsAppMessagePayload({
    targetInbox: props.targetInbox,
    selectedContact: props.selectedContact,
    message,
    templateParams,
    currentUser: props.currentUser,
  });
  await emit('createConversation', {
    payload: whatsappMessagePayload,
    isFromWhatsApp: true,
  });
};

const handleSendTwilioMessage = async ({ message, templateParams }) => {
  if (shouldBlockWhatsappSend.value) return;

  const twilioMessagePayload = prepareWhatsAppMessagePayload({
    targetInbox: props.targetInbox,
    selectedContact: props.selectedContact,
    message,
    templateParams,
    currentUser: props.currentUser,
  });
  await emit('createConversation', {
    payload: twilioMessagePayload,
    isFromWhatsApp: true,
  });
};

const shouldShowMessageEditor = computed(() => {
  return (
    !inboxTypes.value.isWhatsapp &&
    !showNoInboxAlert.value &&
    !inboxTypes.value.isTwilioWhatsapp
  );
});
</script>

<template>
  <div
    class="w-[42rem] divide-y divide-n-strong overflow-visible transition-all duration-300 ease-in-out top-full flex flex-col bg-n-alpha-3 border border-n-strong shadow-sm backdrop-blur-[100px] rounded-xl min-w-0 max-h-[calc(100vh-8rem)]"
  >
    <div class="flex-1 overflow-y-auto divide-y divide-n-strong">
      <transition name="whatsapp-invalid">
        <div
          v-if="shouldShowWhatsappInvalidBanner"
          class="mx-4 mt-4 mb-2 flex items-center gap-2 rounded-lg border border-n-ruby-5/40 bg-n-ruby-3 px-3 py-2 text-sm font-medium text-n-ruby-12 shadow-sm"
        >
          <span
            class="i-lucide-message-circle-x size-4 text-n-ruby-9 animate-pulse"
          />
          <span class="flex-1">{{
            revalidateBannerMessage || whatsappInvalidMessage
          }}</span>
          <button
            class="shrink-0 rounded-md bg-n-ruby-5/40 px-2.5 py-1 text-xs font-semibold text-n-ruby-12 transition-colors hover:bg-n-ruby-5/60 disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="isRevalidatingWhatsapp"
            @click="revalidateWhatsappNumber"
          >
            {{
              isRevalidatingWhatsapp
                ? t('CONVERSATION.REPLYBOX.WHATSAPP_REVALIDATING')
                : t('CONVERSATION.REPLYBOX.WHATSAPP_REVALIDATE')
            }}
          </button>
        </div>
      </transition>
      <ContactSelector
        :contacts="contacts"
        :selected-contact="selectedContact"
        :show-contacts-dropdown="showContactsDropdown"
        :is-loading="isLoading"
        :is-creating-contact="isCreatingContact"
        :contact-id="contactId"
        :contactable-inboxes-list="contactableInboxesList"
        :show-inboxes-dropdown="showInboxesDropdown"
        :has-errors="validationStates.isContactInvalid"
        @search-contacts="handleContactSearch"
        @set-selected-contact="setSelectedContact"
        @clear-selected-contact="clearSelectedContact"
        @update-dropdown="handleDropdownUpdate"
      />
      <InboxEmptyState v-if="showNoInboxAlert" />
      <InboxSelector
        v-else
        :target-inbox="targetInbox"
        :selected-contact="selectedContact"
        :show-inboxes-dropdown="showInboxesDropdown"
        :contactable-inboxes-list="contactableInboxesList"
        :has-errors="validationStates.isInboxInvalid"
        @update-inbox="removeTargetInbox"
        @toggle-dropdown="showInboxesDropdown = $event"
        @handle-inbox-action="handleInboxAction"
      />

      <EmailOptions
        v-if="inboxTypes.isEmail"
        v-model:cc-emails="state.ccEmails"
        v-model:bcc-emails="state.bccEmails"
        v-model:subject="state.subject"
        :contacts="contacts"
        :show-cc-emails-dropdown="showCcEmailsDropdown"
        :show-bcc-emails-dropdown="showBccEmailsDropdown"
        :is-loading="isLoading"
        :has-errors="validationStates.isSubjectInvalid"
        @search-cc-emails="searchCcEmails"
        @search-bcc-emails="searchBccEmails"
        @update-dropdown="handleDropdownUpdate"
      />

      <MessageEditor
        v-if="shouldShowMessageEditor"
        v-model="state.message"
        :message-signature="messageSignature"
        :send-with-signature="sendWithSignature"
        :has-errors="validationStates.isMessageInvalid"
        :channel-type="inboxChannelType"
        :medium="targetInbox?.medium || ''"
      />

      <AttachmentPreviews
        v-if="state.attachedFiles.length > 0"
        :attachments="state.attachedFiles"
        @update:attachments="state.attachedFiles = $event"
      />
    </div>

    <ActionButtons
      :attached-files="state.attachedFiles"
      :is-whatsapp-inbox="inboxTypes.isWhatsapp"
      :is-email-or-web-widget-inbox="inboxTypes.isEmailOrWebWidget"
      :is-twilio-sms-inbox="inboxTypes.isTwilioSMS"
      :is-twilio-whats-app-inbox="inboxTypes.isTwilioWhatsapp"
      :message-templates="whatsappMessageTemplates"
      :channel-type="inboxChannelType"
      :is-loading="isCreating"
      :disable-send-button="isCreating || shouldBlockWhatsappSend"
      :has-selected-inbox="!!targetInbox"
      :inbox-id="targetInbox?.id"
      :has-no-inbox="showNoInboxAlert"
      :is-dropdown-active="isAnyDropdownActive"
      :message-signature="messageSignature"
      @insert-emoji="onClickInsertEmoji"
      @add-signature="handleAddSignature"
      @remove-signature="handleRemoveSignature"
      @attach-file="handleAttachFile"
      @discard="$emit('discard')"
      @send-message="handleSendMessage"
      @send-whatsapp-message="handleSendWhatsappMessage"
      @send-twilio-message="handleSendTwilioMessage"
    />
  </div>
</template>

<style scoped>
.whatsapp-invalid-enter-active,
.whatsapp-invalid-leave-active {
  transition:
    opacity 180ms ease,
    transform 220ms ease;
}

.whatsapp-invalid-enter-from,
.whatsapp-invalid-leave-to {
  opacity: 0;
  transform: translateY(-4px);
}
</style>
