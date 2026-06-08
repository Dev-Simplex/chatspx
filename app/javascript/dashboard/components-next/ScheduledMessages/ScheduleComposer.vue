<script setup>
import { useI18n } from 'vue-i18n';
import FileUpload from 'vue-upload-component';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AttachmentPreviews from 'dashboard/components-next/NewConversation/components/AttachmentPreviews.vue';
import { ALLOWED_FILE_TYPES } from 'shared/constants/messages';

defineProps({
  inboxes: {
    type: Array,
    default: () => [],
  },
  inboxId: {
    type: [Number, String, null],
    default: null,
  },
  message: {
    type: String,
    default: '',
  },
  attachedFiles: {
    type: Array,
    default: () => [],
  },
  canAttach: {
    type: Boolean,
    default: false,
  },
  isUploadingAttachments: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'update:inboxId',
  'update:message',
  'update:attachedFiles',
  'file-upload',
]);

const { t } = useI18n();
</script>

<template>
  <div class="space-y-4">
    <div>
      <label class="mb-2 block text-sm font-semibold text-n-slate-12">
        {{ t('KANBAN.SCHEDULED_MESSAGES.INBOX') }}
      </label>
      <select
        :value="inboxId"
        :disabled="inboxes.length === 0"
        class="h-11 w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 text-sm text-n-slate-12"
        @change="
          emit(
            'update:inboxId',
            $event.target.value ? Number($event.target.value) : null
          )
        "
      >
        <option value="">
          {{ t('KANBAN.SCHEDULED_MESSAGES.INBOX_SELECT_PLACEHOLDER') }}
        </option>
        <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
          {{ inbox.name }}
        </option>
      </select>
      <p v-if="inboxes.length === 0" class="mt-1 text-xs text-n-slate-10">
        {{ t('KANBAN.SCHEDULED_MESSAGES.NO_INBOXES') }}
      </p>
    </div>

    <div>
      <label class="mb-2 block text-sm font-semibold text-n-slate-12">
        {{ t('KANBAN.SCHEDULED_MESSAGES.MESSAGE') }}
      </label>
      <textarea
        :value="message"
        rows="5"
        class="w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2.5 text-sm text-n-slate-12"
        :placeholder="t('KANBAN.SCHEDULED_MESSAGES.MESSAGE_PLACEHOLDER')"
        @input="emit('update:message', $event.target.value)"
      />
      <p class="mt-1 text-xs text-n-slate-10">
        {{ message.length }} {{ t('KANBAN.SCHEDULED_MESSAGES.CHARACTERS') }}
      </p>
    </div>

    <div>
      <label class="mb-2 block text-sm font-semibold text-n-slate-12">
        {{ t('KANBAN.SCHEDULED_MESSAGES.ATTACHMENTS') }}
      </label>

      <div class="flex items-center gap-3">
        <FileUpload
          input-id="scheduledMessageAttachment"
          :size="4096 * 4096"
          :accept="ALLOWED_FILE_TYPES"
          multiple
          :drop-directory="false"
          class="p-px"
          @input-file="(file, oldFile) => emit('file-upload', file, oldFile)"
        >
          <Button
            icon="i-lucide-paperclip"
            color="slate"
            size="sm"
            class="!w-10"
          />
        </FileUpload>
        <div class="text-xs text-n-slate-10">
          <span v-if="attachedFiles.length > 0">
            {{
              t('KANBAN.SCHEDULED_MESSAGES.ATTACHMENTS_SELECTED', {
                count: attachedFiles.length,
              })
            }}
          </span>
          <span v-else>
            {{ t('KANBAN.SCHEDULED_MESSAGES.ATTACH_FILE') }}
          </span>
        </div>
      </div>
      <p v-if="!canAttach" class="mt-2 text-xs text-n-slate-10">
        {{ t('KANBAN.SCHEDULED_MESSAGES.ATTACHMENTS_REQUIRED') }}
      </p>
      <p
        v-if="isUploadingAttachments"
        class="mt-2 flex items-center gap-1 text-xs text-n-slate-10"
      >
        <Spinner class="!size-3" />
        {{ t('KANBAN.SCHEDULED_MESSAGES.ATTACHMENTS_UPLOADING') }}
      </p>

      <AttachmentPreviews
        v-if="attachedFiles.length"
        :attachments="attachedFiles"
        @update:attachments="emit('update:attachedFiles', $event)"
      />
    </div>
  </div>
</template>
