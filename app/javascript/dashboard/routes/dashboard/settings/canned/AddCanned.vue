<script>
import { useVuelidate } from '@vuelidate/core';
import { required, minLength, requiredIf } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';

import NextButton from 'dashboard/components-next/button/Button.vue';
import Modal from '../../../../components/Modal.vue';
import WootMessageEditor from 'dashboard/components/widgets/WootWriter/Editor.vue';
import CannedVisibilityField from './CannedVisibilityField.vue';

export default {
  name: 'AddCanned',
  components: {
    NextButton,
    Modal,
    WootMessageEditor,
    CannedVisibilityField,
  },
  props: {
    responseContent: {
      type: String,
      default: '',
    },
    onClose: {
      type: Function,
      default: () => {},
    },
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      shortCode: '',
      content: this.responseContent || '',
      attachmentFiles: [],
      visibility: 'everyone',
      teamId: null,
      addCanned: {
        showLoading: false,
        message: '',
      },
      show: true,
    };
  },
  validations: {
    shortCode: {
      required,
      minLength: minLength(2),
    },
    content: {
      required,
    },
    visibility: {},
    teamId: {
      requiredIf: requiredIf((_value, model) => model?.visibility === 'team'),
    },
  },
  computed: {
    teamErrorMessage() {
      return this.v$.teamId.$error
        ? this.$t('CANNED_MGMT.VISIBILITY.TEAM_SELECT.REQUIRED_ERROR')
        : '';
    },
    attachmentSummary() {
      return this.attachmentFiles.map(file => file.name).join(', ');
    },
  },
  methods: {
    resetForm() {
      this.shortCode = '';
      this.content = '';
      this.attachmentFiles = [];
      this.visibility = 'everyone';
      this.teamId = null;
      this.v$.shortCode.$reset();
      this.v$.content.$reset();
      this.v$.teamId.$reset();
      this.clearAttachmentInput();
    },
    openAttachmentPicker() {
      this.$refs.attachmentInput?.click();
    },
    clearAttachmentInput() {
      if (this.$refs.attachmentInput) this.$refs.attachmentInput.value = '';
    },
    clearAttachments() {
      this.attachmentFiles = [];
      this.clearAttachmentInput();
    },
    onAttachmentChange(event) {
      this.attachmentFiles = Array.from(event.target.files || []);
    },
    addCannedResponse() {
      // Show loading on button
      this.addCanned.showLoading = true;
      // Make API Calls
      this.$store
        .dispatch('createCannedResponse', {
          short_code: this.shortCode,
          content: this.content,
          attachments: this.attachmentFiles,
          visibility: this.visibility,
          team_id: this.visibility === 'team' ? this.teamId : null,
        })
        .then(() => {
          // Reset Form, Show success message
          this.addCanned.showLoading = false;
          useAlert(this.$t('CANNED_MGMT.ADD.API.SUCCESS_MESSAGE'));
          this.resetForm();
          this.onClose();
        })
        .catch(error => {
          this.addCanned.showLoading = false;
          const errorMessage =
            error?.message || this.$t('CANNED_MGMT.ADD.API.ERROR_MESSAGE');
          useAlert(errorMessage);
        });
    },
  },
};
</script>

<template>
  <Modal v-model:show="show" :on-close="onClose">
    <div class="flex flex-col h-auto overflow-auto">
      <woot-modal-header
        :header-title="$t('CANNED_MGMT.ADD.TITLE')"
        :header-content="$t('CANNED_MGMT.ADD.DESC')"
      />
      <form class="flex flex-col w-full" @submit.prevent="addCannedResponse()">
        <div class="w-full">
          <label :class="{ error: v$.shortCode.$error }">
            {{ $t('CANNED_MGMT.ADD.FORM.SHORT_CODE.LABEL') }}
            <input
              v-model="shortCode"
              type="text"
              :placeholder="$t('CANNED_MGMT.ADD.FORM.SHORT_CODE.PLACEHOLDER')"
              @blur="v$.shortCode.$touch"
            />
          </label>
        </div>

        <div class="w-full">
          <label :class="{ error: v$.content.$error }">
            {{ $t('CANNED_MGMT.ADD.FORM.CONTENT.LABEL') }}
          </label>
          <div class="editor-wrap">
            <WootMessageEditor
              v-model="content"
              class="message-editor [&>div]:px-1"
              :class="{ editor_warning: v$.content.$error }"
              channel-type="Context::Default"
              enable-variables
              :enable-canned-responses="false"
              :placeholder="$t('CANNED_MGMT.ADD.FORM.CONTENT.PLACEHOLDER')"
              @blur="v$.content.$touch"
            />
          </div>
        </div>
        <div class="w-full mt-4">
          <label class="block mb-1">
            {{ $t('CANNED_MGMT.ADD.FORM.ATTACHMENT.LABEL') }}
          </label>
          <input
            ref="attachmentInput"
            type="file"
            multiple
            accept="image/*,video/*,application/pdf"
            class="hidden"
            @change="onAttachmentChange"
          />
          <div class="flex items-center flex-wrap gap-2">
            <NextButton
              type="button"
              faded
              slate
              sm
              icon="i-lucide-paperclip"
              :label="$t('CANNED_MGMT.ATTACHMENT.CHOOSE')"
              @click="openAttachmentPicker"
            />
            <template v-if="attachmentFiles.length">
              <span
                v-tooltip.top="attachmentSummary"
                class="text-sm text-n-slate-11 truncate max-w-[55%]"
              >
                {{ attachmentSummary }}
              </span>
              <NextButton
                type="button"
                ghost
                slate
                xs
                icon="i-lucide-x"
                :label="$t('CANNED_MGMT.ATTACHMENT.CLEAR')"
                @click="clearAttachments"
              />
            </template>
          </div>
        </div>

        <div class="w-full mt-4">
          <CannedVisibilityField
            v-model:visibility="visibility"
            v-model:team-id="teamId"
            :team-error="teamErrorMessage"
          />
        </div>

        <div class="flex flex-row justify-end w-full gap-2 px-0 py-2">
          <NextButton
            faded
            slate
            type="reset"
            :label="$t('CANNED_MGMT.ADD.CANCEL_BUTTON_TEXT')"
            @click.prevent="onClose"
          />
          <NextButton
            type="submit"
            :label="$t('CANNED_MGMT.ADD.FORM.SUBMIT')"
            :disabled="
              v$.content.$invalid ||
              v$.shortCode.$invalid ||
              v$.teamId.$invalid ||
              addCanned.showLoading
            "
            :is-loading="addCanned.showLoading"
          />
        </div>
      </form>
    </div>
  </Modal>
</template>

<style scoped lang="scss">
:deep(.ProseMirror-menubar) {
  @apply hidden;
}

:deep(.ProseMirror-woot-style) {
  @apply min-h-[12.5rem];
}
</style>
