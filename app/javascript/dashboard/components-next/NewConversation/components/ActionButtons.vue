<script setup>
import { defineAsyncComponent, ref, computed, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useFileUpload } from 'dashboard/composables/useFileUpload';
import { vOnClickOutside } from '@vueuse/components';
import { useEventListener } from '@vueuse/core';
import { ALLOWED_FILE_TYPES } from 'shared/constants/messages';
import { buildAttachmentThumbUrl } from 'shared/helpers/FileHelper';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import FileUpload from 'vue-upload-component';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

import Button from 'dashboard/components-next/button/Button.vue';
import WhatsAppOptions from './WhatsAppOptions.vue';
import ContentTemplateSelector from './ContentTemplateSelector.vue';

const props = defineProps({
  attachedFiles: { type: Array, default: () => [] },
  isWhatsappInbox: { type: Boolean, default: false },
  isEmailOrWebWidgetInbox: { type: Boolean, default: false },
  isApiInbox: { type: Boolean, default: false },
  isTwilioWhatsAppInbox: { type: Boolean, default: false },
  messageTemplates: { type: Array, default: () => [] },
  channelType: { type: String, default: '' },
  medium: { type: String, default: '' },
  isLoading: { type: Boolean, default: false },
  disableSendButton: { type: Boolean, default: false },
  hasSelectedInbox: { type: Boolean, default: false },
  hasNoInbox: { type: Boolean, default: false },
  isDropdownActive: { type: Boolean, default: false },
  messageSignature: { type: String, default: '' },
  inboxId: { type: Number, default: null },
});

const emit = defineEmits([
  'discard',
  'sendMessage',
  'sendWhatsappMessage',
  'sendTwilioMessage',
  'insertEmoji',
  'addSignature',
  'removeSignature',
  'attachFile',
]);

const { t } = useI18n();

const attachmentId = ref(0);
const generateUid = () => {
  attachmentId.value += 1;
  return `attachment-${attachmentId.value}`;
};

const uploadAttachment = ref(null);
const isEmojiPickerOpen = ref(false);

const EmojiInput = defineAsyncComponent(
  () => import('shared/components/emoji/EmojiInput.vue')
);

const {
  fetchSignatureFlagFromUISettings,
  setSignatureFlagForInbox,
  isEditorHotKeyEnabled,
} = useUISettings();

const sendWithSignature = computed(() => {
  return fetchSignatureFlagFromUISettings(props.channelType);
});

const showTwilioContentTemplates = computed(() => {
  return props.isTwilioWhatsAppInbox && props.inboxId;
});

const shouldShowEmojiButton = computed(() => {
  return (
    !props.isWhatsappInbox && !props.isTwilioWhatsAppInbox && !props.hasNoInbox
  );
});

const isRegularMessageMode = computed(() => {
  return !props.isWhatsappInbox && !props.isTwilioWhatsAppInbox;
});

const isVoiceInbox = computed(() => props.channelType === INBOX_TYPES.VOICE);

const shouldShowSignatureButton = computed(() => {
  return (
    props.hasSelectedInbox && isRegularMessageMode.value && !isVoiceInbox.value
  );
});

const setSignature = () => {
  if (props.messageSignature) {
    if (sendWithSignature.value) {
      emit('addSignature', props.messageSignature);
    } else {
      emit('removeSignature', props.messageSignature);
    }
  }
};

const toggleMessageSignature = () => {
  setSignatureFlagForInbox(props.channelType, !sendWithSignature.value);
};

// Added this watch to dynamically set signature on target inbox change.
// Only targetInbox has value and is Advance Editor(used by isEmailOrWebWidgetInbox)
// Set the signature only if the inbox based flag is true
watch(
  () => props.hasSelectedInbox,
  newValue => {
    nextTick(() => {
      if (newValue && !isVoiceInbox.value) setSignature();
    });
  },
  { immediate: true }
);

const onClickInsertEmoji = emoji => {
  emit('insertEmoji', emoji);
};

// Email/WebWidget always allow attachments; WAHA (Channel::Api) supports
// free-form media too (unlike official WhatsApp, which is template-gated for a
// brand-new conversation), so it gets the attach/paste affordance as well.
const canAttachFiles = computed(
  () => props.isEmailOrWebWidgetInbox || props.isApiInbox
);

// Plain object with getters so useFileUpload reads the CURRENT channel on each
// upload (the composable captures `inbox` once, but the target inbox only
// becomes known after the user picks it). Without this the per-channel size
// rules never applied — uploads fell back to the installation default.
const composerInbox = {
  get channel_type() {
    return props.channelType;
  },
  get medium() {
    return props.medium;
  },
};

const { onFileUpload } = useFileUpload({
  inbox: composerInbox,
  attachFile: ({ blob, file }) => {
    if (!file) return;
    // Synchronous object URL preview (image/video only) — no base64 read of the
    // whole file blocking the main thread, no memory spike.
    const newFile = {
      resource: blob || file,
      isPrivate: false,
      thumb: buildAttachmentThumbUrl(file),
      blobSignedId: blob?.signed_id,
    };
    emit('attachFile', [...props.attachedFiles, newFile]);
  },
});

const sendButtonLabel = computed(() => {
  const keyCode = isEditorHotKeyEnabled('cmd_enter') ? '⌘ + ↵' : '↵';
  return t('COMPOSE_NEW_CONVERSATION.FORM.ACTION_BUTTONS.SEND', {
    keyCode,
  });
});

const keyboardEvents = {
  Enter: {
    action: () => {
      if (
        isEditorHotKeyEnabled('enter') &&
        isRegularMessageMode.value &&
        !props.isDropdownActive
      ) {
        emit('sendMessage');
      }
    },
  },
  '$mod+Enter': {
    action: () => {
      if (
        isEditorHotKeyEnabled('cmd_enter') &&
        isRegularMessageMode.value &&
        !props.isDropdownActive
      ) {
        emit('sendMessage');
      }
    },
  },
};
useKeyboardEvents(keyboardEvents);

const onPaste = e => {
  if (!canAttachFiles.value) return;

  const files = e.clipboardData?.files;
  if (!files?.length) return;

  // Filter valid files (non-zero size)
  Array.from(files)
    .filter(file => file.size > 0)
    .forEach(file => {
      const { name, type, size } = file;
      // Add unique ID for clipboard-pasted files
      onFileUpload({ file, name, type, size, id: generateUid() });
    });
};

useEventListener(document, 'paste', onPaste);
</script>

<template>
  <div
    class="flex items-center justify-between w-full h-14 gap-2 px-6 py-3 border-t border-n-weak/60 bg-n-alpha-1 rounded-b-3xl"
  >
    <div class="flex gap-2 items-center">
      <WhatsAppOptions
        v-if="isWhatsappInbox"
        :inbox-id="inboxId"
        :message-templates="messageTemplates"
        @send-message="emit('sendWhatsappMessage', $event)"
      />
      <ContentTemplateSelector
        v-if="showTwilioContentTemplates"
        :inbox-id="inboxId"
        @send-message="emit('sendTwilioMessage', $event)"
      />
      <div
        v-if="shouldShowEmojiButton"
        v-on-click-outside="() => (isEmojiPickerOpen = false)"
        class="relative"
      >
        <Button
          icon="i-lucide-smile-plus"
          color="slate"
          size="sm"
          class="!w-10"
          @click="isEmojiPickerOpen = !isEmojiPickerOpen"
        />
        <EmojiInput
          v-if="isEmojiPickerOpen"
          class="top-full mt-1.5 ltr:left-0 rtl:right-0"
          :on-click="onClickInsertEmoji"
        />
      </div>
      <FileUpload
        v-if="canAttachFiles"
        ref="uploadAttachment"
        input-id="composeNewConversationAttachment"
        :size="4096 * 4096"
        :accept="ALLOWED_FILE_TYPES"
        multiple
        :drop-directory="false"
        :data="{
          direct_upload_url: '/rails/active_storage/direct_uploads',
          direct_upload: true,
        }"
        class="p-px"
        @input-file="onFileUpload"
      >
        <Button
          icon="i-lucide-plus"
          color="slate"
          size="sm"
          class="!w-10 relative"
        />
      </FileUpload>
      <Button
        v-if="shouldShowSignatureButton"
        icon="i-lucide-signature"
        color="slate"
        size="sm"
        class="!w-10"
        @click="toggleMessageSignature"
      />
    </div>

    <div class="flex gap-2 items-center">
      <Button
        :label="t('COMPOSE_NEW_CONVERSATION.FORM.ACTION_BUTTONS.DISCARD')"
        variant="faded"
        color="slate"
        size="sm"
        class="!text-xs font-medium"
        @click="emit('discard')"
      />
      <Button
        v-if="isRegularMessageMode"
        :label="sendButtonLabel"
        size="md"
        color="green"
        icon="i-lucide-send"
        class="font-semibold px-4 shadow-sm"
        :disabled="isLoading || disableSendButton"
        :is-loading="isLoading"
        @click="emit('sendMessage')"
      />
    </div>
  </div>
</template>

<style scoped lang="scss">
.emoji-dialog::before {
  @apply hidden;
}

// The <label> tag inside the file-upload component overlaps the button due to its position.
// This causes the button's hover state to not work, as it's positioned below the label (z-index).
// Increasing the button's z-index would break the file upload functionality.
// This style ensures the label remains clickable while preserving the button's hover effect.
:deep() {
  .file-uploads.file-uploads-html5 {
    label {
      @apply hover:cursor-pointer;
    }

    &:hover button {
      @apply dark:bg-n-solid-2 bg-n-alpha-2;
    }
  }
}
</style>
