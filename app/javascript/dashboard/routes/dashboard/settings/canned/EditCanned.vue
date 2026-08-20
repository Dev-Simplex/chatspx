<script>
/* eslint no-console: 0 */
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength, requiredIf } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import WootMessageEditor from 'dashboard/components/widgets/WootWriter/Editor.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Modal from '../../../../components/Modal.vue';
import CannedVisibilityField from './CannedVisibilityField.vue';

export default {
  components: {
    NextButton,
    Modal,
    WootMessageEditor,
    CannedVisibilityField,
  },
  props: {
    id: { type: Number, default: null },
    edcontent: { type: String, default: '' },
    edshortCode: { type: String, default: '' },
    edvisibility: { type: String, default: 'everyone' },
    edteamId: { type: Number, default: null },
    edcreatedBy: { type: Object, default: null },
    onClose: { type: Function, default: () => {} },
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      editCanned: {
        showAlert: false,
        showLoading: false,
      },
      shortCode: this.edshortCode,
      content: this.edcontent,
      attachmentFiles: [],
      visibility: this.edvisibility || 'everyone',
      teamId: this.edteamId || null,
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
    ...mapGetters({
      currentUser: 'getCurrentUser',
      currentRole: 'getCurrentRole',
      myTeams: 'teams/getMyTeams',
    }),
    pageTitle() {
      return `${this.$t('CANNED_MGMT.EDIT.TITLE')} - ${this.edshortCode}`;
    },
    teamErrorMessage() {
      return this.v$.teamId.$error
        ? this.$t('CANNED_MGMT.VISIBILITY.TEAM_SELECT.REQUIRED_ERROR')
        : '';
    },
    attachmentSummary() {
      return this.attachmentFiles.map(file => file.name).join(', ');
    },
    isAuthor() {
      return !!this.edcreatedBy && this.currentUser?.id === this.edcreatedBy.id;
    },
    // Mirrors the backend CannedResponsePolicy#manage? — the 403 is the source of truth,
    // this only keeps the UI from offering an action the backend would reject.
    canManage() {
      if (this.currentRole === 'administrator') return true;
      if (this.edvisibility === 'team') {
        return this.myTeams.some(team => team.id === this.edteamId);
      }
      // Public content is editable by any agent; private is author-only.
      return this.edvisibility === 'everyone' || this.isAuthor;
    },
    // Re-scoping a SHARED response (public or team) is restricted to author/admin
    // (validate_visibility_change). Lock the selector for a non-author on a shared one;
    // private responses are already author-managed, so leave those editable.
    canChangeVisibility() {
      if (this.currentRole === 'administrator') return true;
      if (this.edvisibility === 'personal') return true;
      return this.isAuthor;
    },
  },
  methods: {
    setPageName({ name }) {
      this.v$.content.$touch();
      this.content = name;
    },
    resetForm() {
      this.shortCode = '';
      this.content = '';
      this.attachmentFiles = [];
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
    editCannedResponse() {
      // Show loading on button
      this.editCanned.showLoading = true;
      // Make API Calls
      this.$store
        .dispatch('updateCannedResponse', {
          id: this.id,
          short_code: this.shortCode,
          content: this.content,
          attachments: this.attachmentFiles,
          visibility: this.visibility,
          team_id: this.visibility === 'team' ? this.teamId : null,
        })
        .then(() => {
          // Reset Form, Show success message
          this.editCanned.showLoading = false;
          useAlert(this.$t('CANNED_MGMT.EDIT.API.SUCCESS_MESSAGE'));
          this.resetForm();
          setTimeout(() => {
            this.onClose();
          }, 10);
        })
        .catch(error => {
          this.editCanned.showLoading = false;
          const errorMessage =
            error?.message || this.$t('CANNED_MGMT.EDIT.API.ERROR_MESSAGE');
          useAlert(errorMessage);
        });
    },
  },
};
</script>

<template>
  <Modal v-model:show="show" :on-close="onClose">
    <div class="flex flex-col h-auto overflow-auto">
      <woot-modal-header :header-title="pageTitle" />
      <div
        v-if="!canManage"
        class="flex items-start w-full p-2 mt-2 rounded-md bg-n-alpha-1 dark:bg-n-solid-3"
      >
        <p class="mb-0 text-n-slate-11 text-body-para">
          {{ $t('CANNED_MGMT.VISIBILITY.NO_MANAGE_PERMISSION') }}
        </p>
      </div>
      <form class="flex flex-col w-full" @submit.prevent="editCannedResponse()">
        <div class="w-full">
          <label :class="{ error: v$.shortCode.$error }">
            {{ $t('CANNED_MGMT.EDIT.FORM.SHORT_CODE.LABEL') }}
            <input
              v-model="shortCode"
              type="text"
              :placeholder="$t('CANNED_MGMT.EDIT.FORM.SHORT_CODE.PLACEHOLDER')"
              @input="v$.shortCode.$touch"
            />
          </label>
        </div>

        <div class="w-full">
          <label :class="{ error: v$.content.$error }">
            {{ $t('CANNED_MGMT.EDIT.FORM.CONTENT.LABEL') }}
          </label>
          <div class="editor-wrap">
            <WootMessageEditor
              v-model="content"
              class="message-editor [&>div]:px-1"
              :class="{ editor_warning: v$.content.$error }"
              channel-type="Context::Default"
              enable-variables
              :enable-canned-responses="false"
              :placeholder="$t('CANNED_MGMT.EDIT.FORM.CONTENT.PLACEHOLDER')"
              @blur="v$.content.$touch"
            />
          </div>
        </div>
        <div class="w-full mt-4">
          <label class="block mb-1">
            {{ $t('CANNED_MGMT.EDIT.FORM.ATTACHMENT.LABEL') }}
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
            :disabled="!canChangeVisibility"
          />
        </div>

        <div class="flex flex-row justify-end w-full gap-2 px-0 py-2">
          <NextButton
            faded
            slate
            type="reset"
            :label="$t('CANNED_MGMT.EDIT.CANCEL_BUTTON_TEXT')"
            @click.prevent="onClose"
          />
          <NextButton
            type="submit"
            :label="$t('CANNED_MGMT.EDIT.FORM.SUBMIT')"
            :disabled="
              !canManage ||
              v$.content.$invalid ||
              v$.shortCode.$invalid ||
              v$.teamId.$invalid ||
              editCanned.showLoading
            "
            :is-loading="editCanned.showLoading"
          />
        </div>
      </form>
    </div>
  </Modal>
</template>

<style scoped lang="scss">
::v-deep {
  .ProseMirror-menubar {
    @apply hidden;
  }

  .ProseMirror-woot-style {
    @apply min-h-[12.5rem];

    p {
      @apply text-base;
    }
  }
}
</style>
